import Foundation

/// Single global Core ML synth work queue for all Listen audio.
///
/// Actions **reorganize** this queue — they do not spawn separate bake systems.
///
/// Priority rules:
/// 1. `openArticle` — that article becomes #1; synthesize from start (or resume) downward.
/// 2. `focusPlayhead` — same article stays #1; cursor moves to paragraph→end, then gap-fill top.
/// 3. Opening a different article demotes the previous #1 (cache kept); worker switches to new #1.
/// 4. One worker drains #1’s next missing unit, then continues.
///
/// Work granularity is a **synth chunk** (`TextChunker`, sized by the engine's limits), not a whole
/// paragraph: the worker re-evaluates priority after every chunk (so a playhead request waits
/// at most one chunk, not one 30 s paragraph), and a listening producer can play chunk 0 of the
/// playhead paragraph while chunks 1… render (`ensureChunk`). A paragraph is Ready (bake mark,
/// `p-NNNN.caf`) only once all its chunks are rendered and stitched.
///
/// Never silently skip: a chunk the local engine cannot render (after recursive re-split in
/// `LocalChunkRenderer`) is rendered with Apple TTS instead. Only if that also fails is the
/// paragraph marked failed (no hot retry loop) and its waiters get the error.
///
/// Saved vs unsaved only changes the persistence key (`cacheKey`), not queue behavior.
///
/// Background (`AppRunState`): which model calls may start is `RenderAdmission`. On a Core ML
/// route nothing renders while the app is backgrounded: live chunk requests for audio that isn't
/// rendered yet throw `LocalSynthError.deferredInBackground` at once (the producer speaks that
/// paragraph with Apple TTS — never silent, never skipped, and the Apple audio is NOT written into
/// the engine's cache); bake-ahead waits and the worker is restarted when the app becomes active.
/// While `inactive` only chunks a listener waits for render.
///
/// Priority: renders for an article someone is listening to (a chunk waiter, or its audio playing)
/// run at `.listener` priority; everything else is bake-ahead — a cooler QoS, and held while the
/// device is hot or in Low Power Mode (`BakeConditions`).
///
/// Exception — hosts that render in the background (`SynthQueueContext.activeRouteRendersInBackground`,
/// Kokoro's ONNX CPU route): no Core ML is involved, so the worker keeps rendering while the app
/// is backgrounded — live requests as usual, bake-ahead only for the article that is playing
/// (battery) — and `inactive` is treated like `active`.
///
/// Depends only on `SynthQueueContext` (cache, active engine's key + limits, renderer), never on
/// a concrete engine — the app passes `LocalTTSCoordinator`, tests pass a fake.
@MainActor
final class GlobalSynthQueue {
    struct ArticleJob: Equatable {
        var cacheKey: UUID
        var paragraphs: [String] {
            didSet {
                if paragraphs != oldValue { paragraphHashes = paragraphs.map(ArticleIdentity.paragraphHash) }
            }
        }
        /// `ArticleIdentity.paragraphHash` of each paragraph (chunk scratch dirs, failure marks):
        /// hashed when the text is set, not again for every chunk the worker picks.
        private(set) var paragraphHashes: [String]
        var voiceID: String
        var plan: BakePriorityPlan
        /// FIFO demotion order among non-#1 articles (lower = older / demoted earlier).
        var demoteOrder: Int
        var isEphemeral: Bool

        init(cacheKey: UUID, paragraphs: [String], voiceID: String, plan: BakePriorityPlan,
             demoteOrder: Int, isEphemeral: Bool) {
            self.cacheKey = cacheKey
            self.paragraphs = paragraphs
            self.paragraphHashes = paragraphs.map(ArticleIdentity.paragraphHash)
            self.voiceID = voiceID
            self.plan = plan
            self.demoteOrder = demoteOrder
            self.isEphemeral = isEphemeral
        }
    }

    private weak var coordinator: SynthQueueContext?
    private var jobs: [UUID: ArticleJob] = [:]
    /// Ordered stack: `stack[0]` is current #1.
    private var stack: [UUID] = []
    private var demoteCounter = 0
    private var worker: Task<Void, Never>?
    private var chunkWaiters: [ChunkKey: [CheckedContinuation<ChunkResolution, Error>]] = [:]
    /// Paragraphs whose chunk files a live player may reference — keep their scratch after
    /// stitching (cleaned on next open / launch). Pure bake-ahead paragraphs drop scratch at once.
    private var liveChunkParagraphs: Set<ParagraphKey> = []
    /// (key|index|textHash) that failed the engine *and* Apple fallback — skipped by the worker so a
    /// bad unit cannot spin forever. A live request for the unit clears its mark (fresh try).
    private var failedUnits: Set<String> = []
    private var chunkPlanCache: [ChunkPlanKey: [String]] = [:]

    private struct ChunkPlanKey: Hashable {
        var engine: String
        var text: String
    }

    private struct ParagraphKey: Hashable {
        var cacheKey: UUID
        var index: Int
    }

    private struct ChunkKey: Hashable {
        var cacheKey: UUID
        var index: Int
        var chunk: Int
    }

    /// What the producer should play for (paragraph, chunk).
    enum ChunkResolution {
        /// Per-chunk CAF (paragraph still building, or kept scratch).
        case chunk(URL)
        /// Paragraph already stitched; play `url` from `startTime` (chunk boundary).
        case paragraph(URL, startTime: TimeInterval)
    }

    /// Foreground / background gate for Core ML (injectable for tests).
    var runState: AppRunState = .shared {
        didSet { observeRunState() }
    }
    private var runStateObserver: NSObjectProtocol?
    /// Live requests answered with "deferred" because the app was in the background.
    private(set) var backgroundDeferrals = 0
    #if canImport(UIKit)
    /// Lets an in-flight chunk (and its CAF write) finish when the app leaves the foreground.
    private lazy var drainGrace = BackgroundGrace(name: "ReaderSynthDrain")
    /// Off in unit tests that flip the fake run state.
    var usesBackgroundGrace = true
    #endif
    /// Thermal state / Low Power Mode (injectable for tests).
    var bakeConditions: () -> BakeConditions = { .current }
    private var deviceObservers: [NSObjectProtocol] = []

    init() {
        observeRunState()
        for name in [ProcessInfo.thermalStateDidChangeNotification, .NSProcessInfoPowerStateDidChange] {
            deviceObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated { self?.bakeConditionsChanged() }
            })
        }
    }

    /// Thermal state or Low Power Mode changed: held bake-ahead resumes once nothing holds it.
    func bakeConditionsChanged() {
        guard bakeConditions().bakeAheadHold == nil, !stack.isEmpty else { return }
        kickWorker()
    }

    /// `.listener` while someone listens to the article — waits on one of its chunks or is
    /// playing it — else `.bakeAhead`.
    private func renderPriority(for cacheKey: UUID) -> RenderPriority {
        let listening = chunkWaiters.keys.contains { $0.cacheKey == cacheKey }
            || coordinator?.playingCacheKey == cacheKey
        return listening ? .listener : .bakeAhead
    }

    private func observeRunState() {
        if let runStateObserver { NotificationCenter.default.removeObserver(runStateObserver) }
        runStateObserver = NotificationCenter.default.addObserver(
            forName: AppRunState.didChange, object: runState, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.runStateChanged() }
        }
    }

    /// App moved between active / inactive / background.
    func runStateChanged() {
        let phase = runState.phase
        ListenTimingLog.log("synth_queue_phase", [
            "phase": phase.rawValue, "worker_busy": worker != nil,
            "active_key": ListenTimingLog.shortKey(activeBakeCacheKey), "active_p": activeBakeIndex ?? -1,
        ])
        if worker != nil, phase == .background {
            // The in-flight chunk finishes (its waiter gets it, and its file is written); the
            // worker then decides what may run next.
            #if canImport(UIKit)
            if usesBackgroundGrace { drainGrace.begin() }
            #endif
        } else if admission(isLiveRequest: true, cacheKey: nil) == .deferToApple {
            failAllLiveWaiters(LocalSynthError.deferredInBackground)
        }
        if let primary = stack.first, admission(isLiveRequest: hasLiveWaiters, cacheKey: primary) == .render {
            kickWorker()
        }
    }

    private var hasLiveWaiters: Bool { !chunkWaiters.isEmpty }

    /// The active host renders without Core ML/GPU and may run while backgrounded.
    private var rendersInBackground: Bool { coordinator?.activeRouteRendersInBackground ?? false }

    /// `RenderAdmission` for audio of `cacheKey` now.
    private func admission(isLiveRequest: Bool, cacheKey: UUID?) -> RenderAdmission {
        RenderAdmission.decide(phase: runState.phase, rendersInBackground: rendersInBackground,
                               isLiveRequest: isLiveRequest,
                               isPlayingArticle: cacheKey != nil && cacheKey == coordinator?.playingCacheKey)
    }

    private func failAllLiveWaiters(_ error: Error) {
        for key in Array(chunkWaiters.keys) {
            for cont in chunkWaiters.removeValue(forKey: key) ?? [] { cont.resume(throwing: error) }
        }
    }

    private func noteBackgroundDeferral(_ cacheKey: UUID, _ index: Int, chunk: Int?) {
        backgroundDeferrals += 1
        lastBakeEvent = "background: \(cacheKey.uuidString.prefix(8)) p\(index) → Apple (no Core ML in background)"
        ListenTimingLog.log("bg_deferred", [
            "key": ListenTimingLog.shortKey(cacheKey), "p": index, "c": chunk ?? -1,
        ])
    }

    func attach(coordinator: SynthQueueContext) {
        self.coordinator = coordinator
    }

    // MARK: - Reshuffle APIs

    /// Article becomes #1. Synthesize from `resumeParagraph` (default 0) → end, then gap-fill.
    func openArticle(
        cacheKey: UUID,
        paragraphs: [String],
        voiceID: String,
        resumeParagraph: Int = 0,
        isEphemeral: Bool
    ) {
        guard !paragraphs.isEmpty else { return }
        let plan: BakePriorityPlan = resumeParagraph <= 0
            ? .topDown(paragraphCount: paragraphs.count)
            : .fromPlayhead(resumeParagraph, paragraphCount: paragraphs.count)
        upsert(
            cacheKey: cacheKey,
            paragraphs: paragraphs,
            voiceID: voiceID,
            plan: plan,
            isEphemeral: isEphemeral,
            makePrimary: true
        )
        kickWorker()
    }

    /// Same article stays #1; move priority cursor to `paragraph` → end, then gap-fill top.
    func focusPlayhead(
        cacheKey: UUID,
        paragraph: Int,
        paragraphs: [String]? = nil,
        voiceID: String? = nil
    ) {
        guard var job = jobs[cacheKey] else {
            if let paragraphs, let voiceID {
                openArticle(
                    cacheKey: cacheKey,
                    paragraphs: paragraphs,
                    voiceID: voiceID,
                    resumeParagraph: paragraph,
                    isEphemeral: false
                )
            }
            return
        }
        if let paragraphs { job.paragraphs = paragraphs }
        if let voiceID { job.voiceID = voiceID }
        job.plan = .fromPlayhead(paragraph, paragraphCount: job.paragraphs.count)
        jobs[cacheKey] = job
        promoteToPrimary(cacheKey)
        kickWorker()
    }

    /// Ensure article is in the queue without stealing #1 (e.g. background save FIFO).
    /// `resumeParagraph` > 0 keeps a mid-article plan (from there → end, then gap-fill) for when
    /// this job's turn comes; it never changes the stack position.
    func enqueueDemoted(
        cacheKey: UUID,
        paragraphs: [String],
        voiceID: String,
        resumeParagraph: Int = 0,
        isEphemeral: Bool
    ) {
        guard !paragraphs.isEmpty else { return }
        if jobs[cacheKey] != nil {
            // Refresh payload but keep stack position.
            var job = jobs[cacheKey]!
            job.paragraphs = paragraphs
            job.voiceID = voiceID
            job.isEphemeral = isEphemeral
            jobs[cacheKey] = job
        } else {
            demoteCounter += 1
            jobs[cacheKey] = ArticleJob(
                cacheKey: cacheKey,
                paragraphs: paragraphs,
                voiceID: voiceID,
                plan: resumeParagraph <= 0
                    ? .topDown(paragraphCount: paragraphs.count)
                    : .fromPlayhead(resumeParagraph, paragraphCount: paragraphs.count),
                demoteOrder: demoteCounter,
                isEphemeral: isEphemeral
            )
            stack.append(cacheKey)
        }
        kickWorker()
    }

    /// Pending bake job (persisted by `PendingBakeJobStore`).
    struct PendingWork: Equatable {
        var cacheKey: UUID
        var paragraphs: [String]
        var voiceID: String
        var priorityStart: Int
        var isEphemeral: Bool
    }

    /// Fold persisted pending jobs into the queue after the local engine warms.
    ///
    /// The active article / playhead stays #1:
    /// - `focusKey` (the article the user most recently opened / listened to) is adopted first
    ///   and becomes #1 unless it already is (its live plan is then left alone);
    /// - any other job becomes #1 only when the queue has no #1 at all;
    /// - everything else — including jobs started mid-article (`priorityStart > 0`) — is demoted
    ///   behind #1, keeping its mid-article plan for when its turn comes.
    func adoptPending(_ pending: [PendingWork], focusKey: UUID? = nil) {
        var ordered = pending
        if let focusKey, let i = ordered.firstIndex(where: { $0.cacheKey == focusKey }) {
            ordered.insert(ordered.remove(at: i), at: 0)
        }
        for job in ordered {
            let primary = primaryCacheKey
            if primary == job.cacheKey {
                continue // already #1 with a live plan; don't reset its playhead cursor
            } else if primary == nil || job.cacheKey == focusKey {
                openArticle(cacheKey: job.cacheKey, paragraphs: job.paragraphs,
                            voiceID: job.voiceID, resumeParagraph: job.priorityStart, isEphemeral: job.isEphemeral)
            } else {
                enqueueDemoted(cacheKey: job.cacheKey, paragraphs: job.paragraphs,
                               voiceID: job.voiceID, resumeParagraph: job.priorityStart, isEphemeral: job.isEphemeral)
            }
        }
    }

    /// Drop an article from the queue (delete / clear audio). Does not delete disk files.
    func remove(cacheKey: UUID) {
        jobs[cacheKey] = nil
        stack.removeAll { $0 == cacheKey }
        failWaiters(cacheKey: cacheKey, error: CancellationError())
    }

    /// Flip persistence kind for queued work (Save / Unsave) without touching plan or #1.
    /// Without this, a job opened as ephemeral kept re-marking a saved cache ephemeral.
    func setEphemeral(cacheKey: UUID, _ isEphemeral: Bool) {
        guard var job = jobs[cacheKey], job.isEphemeral != isEphemeral else { return }
        job.isEphemeral = isEphemeral
        jobs[cacheKey] = job
    }

    func hasJob(cacheKey: UUID) -> Bool { jobs[cacheKey] != nil }

    /// The article's audio was just aligned with `paragraphs` (Save, or an open with newer text):
    /// its job renders them from now on, so a render of the text it had isn't published over
    /// them (`stillWants`). Its place in the queue, voice and plan stay; the plan's start moves
    /// to the same place in the new text.
    func updateParagraphs(cacheKey: UUID, paragraphs: [String]) {
        guard !paragraphs.isEmpty, var job = jobs[cacheKey], job.paragraphs != paragraphs else { return }
        let start = ParagraphPositionMap.mapParagraphStart(job.plan.priorityStart, from: ParagraphDocument(parts: job.paragraphs),
                                                           to: ParagraphDocument(parts: paragraphs))
        job.plan = BakePriorityPlan(priorityStart: start, fillGapsFromTopAfterPriority: job.plan.fillGapsFromTopAfterPriority,
                                    paragraphCount: paragraphs.count)
        job.paragraphs = paragraphs
        jobs[cacheKey] = job
        kickWorker()
    }

    /// Rekey queued work after Save migrates ephemeral → saved UUID.
    func rekey(from oldKey: UUID, to newKey: UUID) {
        guard oldKey != newKey, let job = jobs[oldKey] else { return }
        jobs[oldKey] = nil
        var moved = job
        moved.cacheKey = newKey
        jobs[newKey] = moved
        if let idx = stack.firstIndex(of: oldKey) {
            stack[idx] = newKey
        }
        for key in chunkWaiters.keys.filter({ $0.cacheKey == oldKey }) {
            let conts = chunkWaiters.removeValue(forKey: key) ?? []
            chunkWaiters[ChunkKey(cacheKey: newKey, index: key.index, chunk: key.chunk), default: []]
                .append(contentsOf: conts)
        }
        kickWorker()
    }

    // MARK: - Chunk-level live ensure (play-while-building)

    /// Synth chunks for a paragraph's text (deterministic; cached per engine and text).
    func chunkTexts(for text: String) -> [String] {
        let key = ChunkPlanKey(engine: coordinator?.cacheEngineID ?? "?", text: text)
        if let cached = chunkPlanCache[key] { return cached }
        let chunks = TextChunker.chunks(for: text, limits: coordinator?.activeChunkLimits ?? .kokoro)
        chunkPlanCache[key] = chunks
        return chunks
    }

    /// The local engine or its voice changed: drop chunk plans, chunk scratch and failure marks
    /// (they belong to the old engine/voice) and retarget every queued article to the new cache
    /// voice so the worker re-renders in it. Paragraph CAFs are keyed by engine+voice in
    /// `index.json`: old-voice ones stay playable until each paragraph is replaced
    /// (`playableAudioURL`) but never count as ready.
    func engineDidChange() {
        chunkPlanCache.removeAll()
        failedUnits.removeAll()
        liveChunkParagraphs.removeAll()
        coordinator?.audioCache.removeAllChunkScratch()
        if let coordinator {
            for key in jobs.keys {
                if let v = jobs[key]?.voiceID { jobs[key]?.voiceID = coordinator.normalizedCacheVoice(v) }
            }
        }
        if !stack.isEmpty { kickWorker() }
    }

    /// Await a playable URL for chunk `chunk` of `paragraphIndex`. Moves the playhead cursor
    /// to this paragraph so the worker renders its next missing chunk before any bake-ahead.
    func ensureChunk(
        cacheKey: UUID,
        paragraphIndex: Int,
        chunk: Int,
        text: String,
        paragraphs: [String],
        voiceID: String,
        isEphemeral: Bool
    ) async throws -> ChunkResolution {
        guard let coordinator else {
            throw NSError(domain: "GlobalSynthQueue", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Coordinator not attached"])
        }
        let cache = coordinator.audioCache
        let hash = ArticleIdentity.paragraphHash(text)
        let unit = ParagraphKey(cacheKey: cacheKey, index: paragraphIndex)
        liveChunkParagraphs.insert(unit)
        failedUnits.remove(failedID(cacheKey, paragraphIndex, hash)) // live request = fresh try

        let chunkURL = cache.chunkURL(articleID: cacheKey, paragraphIndex: paragraphIndex, textHash: hash, chunk: chunk)
        if cache.isUsableAudioFile(chunkURL) { return .chunk(chunkURL) }
        if let resolved = paragraphResolution(cacheKey: cacheKey, index: paragraphIndex, chunk: chunk, voiceID: voiceID) {
            return resolved
        }

        // Background on a Core ML route: don't wait for a render that can't happen — the producer
        // speaks it with Apple. Don't move the cursor either (the producer pre-renders Apple units
        // far ahead); on return the listen engine refocuses at the paragraph it restarts from.
        guard admission(isLiveRequest: true, cacheKey: cacheKey) == .render else {
            noteBackgroundDeferral(cacheKey, paragraphIndex, chunk: chunk)
            throw LocalSynthError.deferredInBackground
        }
        // Make this article #1 with the cursor on this paragraph.
        if jobs[cacheKey] == nil || jobs[cacheKey]?.paragraphs.count != paragraphs.count {
            openArticle(cacheKey: cacheKey, paragraphs: paragraphs, voiceID: voiceID,
                        resumeParagraph: paragraphIndex, isEphemeral: isEphemeral)
        }
        focusPlayhead(cacheKey: cacheKey, paragraph: paragraphIndex, voiceID: voiceID)
        if var job = jobs[cacheKey], job.paragraphs.indices.contains(paragraphIndex),
           job.paragraphs[paragraphIndex] != text {
            job.paragraphs[paragraphIndex] = text
            jobs[cacheKey] = job
        }

        let t0 = ListenTimingLog.now()
        let busyOther = activeBakeCacheKey != nil
            && (activeBakeCacheKey != cacheKey || activeBakeIndex != paragraphIndex)
        let otherKey = activeBakeCacheKey
        let otherIndex = activeBakeIndex
        let result = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<ChunkResolution, Error>) in
            chunkWaiters[ChunkKey(cacheKey: cacheKey, index: paragraphIndex, chunk: chunk), default: []].append(cont)
            kickWorker()
        }
        var fields: [String: Any] = [
            "key": ListenTimingLog.shortKey(cacheKey), "p": paragraphIndex, "c": chunk,
            "wait_ms": ListenTimingLog.ms(since: t0), "worker_busy_other": busyOther,
        ]
        if busyOther {
            fields["other_key"] = ListenTimingLog.shortKey(otherKey)
            fields["other_p"] = otherIndex ?? -1
            fields["other_article"] = otherKey != cacheKey
        }
        ListenTimingLog.log("unit_wait", fields)
        return result
    }

    /// Is (paragraph, chunk) playable right now without waiting for a render?
    func isChunkReady(cacheKey: UUID, paragraphIndex: Int, chunk: Int, text: String, voiceID: String) -> Bool {
        guard let coordinator else { return false }
        let cache = coordinator.audioCache
        let url = cache.chunkURL(articleID: cacheKey, paragraphIndex: paragraphIndex,
                                 textHash: ArticleIdentity.paragraphHash(text), chunk: chunk)
        if cache.isUsableAudioFile(url) { return true }
        return paragraphResolution(cacheKey: cacheKey, index: paragraphIndex, chunk: chunk, voiceID: voiceID) != nil
    }

    private func paragraphResolution(cacheKey: UUID, index: Int, chunk: Int, voiceID: String) -> ChunkResolution? {
        guard let coordinator,
              let url = coordinator.audioCache.audioURL(
                articleID: cacheKey, paragraphIndex: index,
                engineID: coordinator.cacheEngineID, voiceID: voiceID)
        else { return nil }
        guard chunk > 0 else { return .paragraph(url, startTime: 0) }
        let durations = coordinator.audioCache.entry(articleID: cacheKey, paragraphIndex: index)?.chunkDurations ?? []
        let offset = durations.prefix(chunk).reduce(0, +)
        return .paragraph(url, startTime: offset)
    }

    private func failedID(_ key: UUID, _ index: Int, _ hash: String) -> String {
        "\(key.uuidString)|\(index)|\(hash)"
    }

    /// The queue still has `cacheKey` with the text of hash `hash` on paragraph `index`.
    private func stillWants(_ cacheKey: UUID, _ index: Int, _ hash: String) -> Bool {
        guard let hashes = jobs[cacheKey]?.paragraphHashes, hashes.indices.contains(index) else { return false }
        return hashes[index] == hash
    }

    // MARK: - Diagnostics

    /// Currently rendering unit (nil when idle between units / empty queue).
    private(set) var activeBakeCacheKey: UUID?
    private(set) var activeBakeIndex: Int?
    /// One-line last bake success/fail for the listen debug overlay.
    private(set) var lastBakeEvent: String = "—"

    var primaryCacheKey: UUID? { stack.first }
    /// Articles behind #1 (demoted / FIFO).
    var demotedCount: Int { max(0, stack.count - 1) }
    var isWorkerRunning: Bool { worker != nil }

    func pendingUnitCount(for cacheKey: UUID) -> Int {
        guard let job = jobs[cacheKey], let coordinator else { return 0 }
        return coordinator.audioCache.missingIndices(
            articleID: cacheKey,
            paragraphCount: job.paragraphs.count,
            engineID: coordinator.cacheEngineID,
            voiceID: job.voiceID
        ).count
    }

    func planDescription(for cacheKey: UUID) -> String? {
        guard let job = jobs[cacheKey] else { return nil }
        return String(describing: job.plan)
    }

    func isEphemeral(cacheKey: UUID) -> Bool? {
        jobs[cacheKey]?.isEphemeral
    }

    /// Next missing unit index for #1 under its current plan (nil if none / empty).
    func nextMissingIndex(for cacheKey: UUID? = nil) -> Int? {
        guard let coordinator else { return nil }
        let key = cacheKey ?? stack.first
        guard let key, let job = jobs[key] else { return nil }
        let missing = coordinator.audioCache.missingIndices(
            articleID: job.cacheKey,
            paragraphCount: job.paragraphs.count,
            engineID: coordinator.cacheEngineID,
            voiceID: job.voiceID
        )
        return job.plan.orderedWork(missing: missing).first
    }

    // MARK: - Private

    private func upsert(
        cacheKey: UUID,
        paragraphs: [String],
        voiceID: String,
        plan: BakePriorityPlan,
        isEphemeral: Bool,
        makePrimary: Bool
    ) {
        demoteCounter += 1
        let existing = jobs[cacheKey]
        // Reusing the job keeps its paragraph hashes when the text is unchanged (every play / seek
        // re-opens the article).
        var job = existing ?? ArticleJob(cacheKey: cacheKey, paragraphs: paragraphs, voiceID: voiceID,
                                         plan: plan, demoteOrder: demoteCounter, isEphemeral: isEphemeral)
        job.paragraphs = paragraphs
        job.voiceID = voiceID
        job.plan = plan
        job.demoteOrder = makePrimary ? (existing?.demoteOrder ?? demoteCounter) : demoteCounter
        job.isEphemeral = isEphemeral
        jobs[cacheKey] = job
        if makePrimary {
            promoteToPrimary(cacheKey)
        } else if !stack.contains(cacheKey) {
            stack.append(cacheKey)
        }
    }

    private func promoteToPrimary(_ cacheKey: UUID) {
        stack.removeAll { $0 == cacheKey }
        stack.insert(cacheKey, at: 0)
    }

    /// Debug engine probe: hold the worker between chunks so probe timings aren't interleaved.
    var isPausedForProbe = false {
        didSet { if !isPausedForProbe { kickWorker() } }
    }

    /// Nothing renders or stitches until the launch's library maintenance has finished
    /// (`LocalTTSCoordinator.holdRenderingForLaunch`); jobs and chunk requests wait.
    var isHeldForLaunch = false {
        didSet { if !isHeldForLaunch { kickWorker() } }
    }

    #if DEBUG
    /// Tests: runs once a paragraph is stitched, before it is published (key, paragraph), as
    /// something landing on the main actor while the stitch was in flight would.
    var beforePublishing: ((UUID, Int) -> Void)?
    #endif

    private func kickWorker() {
        guard worker == nil, !isPausedForProbe, !isHeldForLaunch else { return }
        worker = Task { [weak self] in
            await self?.drain()
        }
    }

    private func drain() async {
        defer {
            worker = nil
            activeBakeCacheKey = nil
            activeBakeIndex = nil
            #if canImport(UIKit)
            drainGrace.end()
            #endif
        }
        while !isPausedForProbe, !isHeldForLaunch, let next = nextWorkUnit() {
            guard let coordinator else { break }
            // Check the app state before every chunk (see `RenderAdmission`).
            let phase = runState.phase
            switch admission(isLiveRequest: hasLiveWaiters, cacheKey: next.0.cacheKey) {
            case .render:
                // CPU route in the background: keep the app alive through the call.
                #if canImport(UIKit)
                if phase == .background, usesBackgroundGrace { drainGrace.begin() }
                #endif
            case .deferToApple, .park:
                // Restarted by `runStateChanged` (or a listener's request).
                failAllLiveWaiters(LocalSynthError.deferredInBackground)
                noteParked(phase: phase, engine: coordinator.synthRenderer.engineShortName)
                return
            }
            let (job, index) = next
            let priority = renderPriority(for: job.cacheKey)
            if priority == .bakeAhead, let hold = bakeConditions().bakeAheadHold {
                lastBakeEvent = "bake-ahead held: \(hold.label) (resumes when it clears)"
                ListenTimingLog.log("synth_queue_parked", ["phase": runState.phase.rawValue, "reason": hold.label])
                return // `bakeConditionsChanged` (or a listener's request) restarts the worker
            }
            let engineID = coordinator.cacheEngineID
            let cache = coordinator.audioCache
            // Already ready?
            if cache.audioURL(articleID: job.cacheKey, paragraphIndex: index,
                              engineID: engineID, voiceID: job.voiceID) != nil {
                resumeChunkWaitersWithParagraph(cacheKey: job.cacheKey, index: index, voiceID: job.voiceID)
                continue
            }
            guard job.paragraphs.indices.contains(index) else { continue }
            let text = job.paragraphs[index]
            let hash = job.paragraphHashes[index]
            let chunks = chunkTexts(for: text)
            guard !chunks.isEmpty else {
                // Nothing speakable (punctuation only). Mark failed so we don't spin; producer
                // treats an empty chunk plan as nothing to play.
                failedUnits.insert(failedID(job.cacheKey, index, hash))
                failWaiters(cacheKey: job.cacheKey, index: index, error: NothingSpeakable())
                continue
            }
            activeBakeCacheKey = job.cacheKey
            activeBakeIndex = index
            let chunkURLs = chunks.indices.map {
                cache.chunkURL(articleID: job.cacheKey, paragraphIndex: index, textHash: hash, chunk: $0)
            }
            do {
                try Task.checkCancellation()
                // A listener waiting on a later chunk (scrubbed to a sentence mid-paragraph)
                // gets that chunk first; otherwise chunks render in order.
                let waited = chunkWaiters.keys
                    .filter { $0.cacheKey == job.cacheKey && $0.index == index }
                    .map(\.chunk).sorted()
                    .first { chunkURLs.indices.contains($0) && !cache.isUsableAudioFile(chunkURLs[$0]) }
                if let k = waited ?? chunkURLs.firstIndex(where: { !cache.isUsableAudioFile($0) }) {
                    // Render ONE chunk, then loop (re-evaluates priority between chunks).
                    try await renderChunk(job: job, index: index, chunk: k, of: chunks.count,
                                          text: chunks[k], next: k + 1 < chunks.count ? chunks[k + 1] : nil,
                                          to: chunkURLs[k], hash: hash, priority: priority)
                    resumeChunkWaiters(cacheKey: job.cacheKey, index: index, chunk: k, url: chunkURLs[k])
                    if chunkURLs.allSatisfy(cache.isUsableAudioFile) == false {
                        activeBakeCacheKey = nil
                        activeBakeIndex = nil
                        continue
                    }
                }
                // All chunks present → stitch them off the main actor (a read / convert / write
                // of the whole paragraph) into a file of their own, then publish it here only if
                // the queue still wants this text on this paragraph. Meanwhile the article's audio
                // may have been aligned with other paragraphs (opening it with newer text, a
                // merge) and its job given them, or the article left the queue (audio cleared,
                // deleted, rekeyed): a render of the old paragraph isn't filed on the new one.
                let staged = cache.stitchingURL(articleID: job.cacheKey, paragraphIndex: index, textHash: hash)
                let stitched: ChunkAudioStitcher.Result
                do {
                    stitched = try await Task.detached(priority: priority.taskPriority) {
                        try ArticleAudioCache.stitchParagraph(chunkURLs, to: staged)
                    }.value
                } catch where !chunkURLs.allSatisfy(cache.isUsableAudioFile) {
                    // The chunk scratch went away meanwhile (engine / voice change, identity
                    // prep): not this paragraph's failure — look again.
                    try? FileManager.default.removeItem(at: staged)
                    activeBakeCacheKey = nil
                    activeBakeIndex = nil
                    continue
                }
                #if DEBUG
                beforePublishing?(job.cacheKey, index)
                #endif
                guard stillWants(job.cacheKey, index, hash), cache.isUsableAudioFile(staged) else {
                    try? FileManager.default.removeItem(at: staged)
                    ListenTimingLog.log("paragraph_discarded", ["key": ListenTimingLog.shortKey(job.cacheKey), "p": index])
                    activeBakeCacheKey = nil
                    activeBakeIndex = nil
                    continue
                }
                try cache.publishParagraph(
                    staged: staged,
                    articleID: job.cacheKey,
                    paragraphIndex: index,
                    duration: stitched.duration,
                    engineID: engineID,
                    voiceID: job.voiceID,
                    textHash: hash,
                    chunkDurations: chunks.count > 1 ? stitched.chunkDurations : nil
                )
                coordinator.noteBakeMarksChanged()
                if job.isEphemeral {
                    cache.markEphemeral(cacheKey: job.cacheKey, lastAccess: Date())
                }
                if !liveChunkParagraphs.contains(ParagraphKey(cacheKey: job.cacheKey, index: index)) {
                    try? FileManager.default.removeItem(
                        at: cache.chunkDirectory(articleID: job.cacheKey, paragraphIndex: index, textHash: hash))
                }
                resumeChunkWaitersWithParagraph(cacheKey: job.cacheKey, index: index, voiceID: job.voiceID)
                let readyMsg = "bake ok \(job.cacheKey.uuidString.prefix(8)) p\(index) (\(chunks.count) chunk\(chunks.count == 1 ? "" : "s"))"
                lastBakeEvent = readyMsg
                ListenDebugLog.shared.append(readyMsg)
                ListenTimingLog.log("paragraph_ready", [
                    "key": ListenTimingLog.shortKey(job.cacheKey), "p": index, "chunks": chunks.count,
                    "chars": text.count, "audio_s": (stitched.duration * 100).rounded() / 100,
                    "primary": stack.first == job.cacheKey,
                ])
            } catch is CancellationError {
                activeBakeCacheKey = nil
                activeBakeIndex = nil
                failWaiters(cacheKey: job.cacheKey, index: index, error: CancellationError())
                return
            } catch LocalSynthError.deferredInBackground {
                // Went to background mid-paragraph: finished chunks stay on disk; not a failure.
                failAllLiveWaiters(LocalSynthError.deferredInBackground)
                lastBakeEvent = "background: \(coordinator.synthRenderer.engineShortName) paused at "
                    + "\(job.cacheKey.uuidString.prefix(8)) p\(index)"
                ListenTimingLog.log("synth_queue_parked", ["phase": runState.phase.rawValue, "p": index])
                return
            } catch {
                // Engine AND Apple fallback failed (or stitch/store failed). Don't hot-loop.
                failedUnits.insert(failedID(job.cacheKey, index, hash))
                let failMsg = "bake FAIL \(job.cacheKey.uuidString.prefix(8)) p\(index): \(error.localizedDescription)"
                lastBakeEvent = failMsg
                ListenDebugLog.shared.append(failMsg)
                ListenTimingLog.log("paragraph_failed", [
                    "key": ListenTimingLog.shortKey(job.cacheKey), "p": index, "err": error.localizedDescription,
                ])
                print("[SynthQueue] fail key=\(job.cacheKey.uuidString.prefix(8)) p=\(index): \(error.localizedDescription)")
                failWaiters(cacheKey: job.cacheKey, index: index, error: error)
            }
            activeBakeCacheKey = nil
            activeBakeIndex = nil
        }
        // Drop completed articles from stack.
        compactCompleted()
    }

    /// The worker stopped before a chunk (`RenderAdmission` said not now).
    private func noteParked(phase: AppRunState.Phase, engine: String) {
        switch phase {
        case .background where rendersInBackground:
            // CPU route: the listener's chunks and the playing article render; other articles
            // wait for the foreground (battery).
            lastBakeEvent = "background: holding bake of other articles"
            ListenTimingLog.log("synth_queue_parked", ["phase": phase.rawValue, "reason": "not_playing_article"])
        case .background:
            lastBakeEvent = "background: \(engine) paused (bake resumes in foreground)"
            ListenTimingLog.log("synth_queue_parked", ["phase": phase.rawValue])
        case .inactive, .active:
            // Inactive: bake-ahead resumes on becoming active (or when a listener waits).
            ListenTimingLog.log("synth_queue_parked", ["phase": phase.rawValue])
        }
    }

    private struct NothingSpeakable: LocalizedError {
        var errorDescription: String? { "Nothing speakable in paragraph" }
    }

    /// Engine first (recursive re-split inside the renderer); Apple TTS for this chunk if the engine
    /// still fails. Throws only when both fail.
    private func renderChunk(
        job: ArticleJob, index: Int, chunk: Int, of count: Int, text: String, next: String? = nil,
        to url: URL, hash: String, priority: RenderPriority
    ) async throws {
        guard let coordinator else { throw CancellationError() }
        let engine = coordinator.synthRenderer
        let t0 = ListenTimingLog.now()
        let ctx: [String: Any] = [
            "key": ListenTimingLog.shortKey(job.cacheKey), "p": index, "c": chunk,
            "primary": stack.first == job.cacheKey, "bake_ahead": priority == .bakeAhead,
        ]
        // Full key rides along for the crash marker only (auto-resume); not logged per chunk.
        var callCtx = ctx
        callCtx["article"] = job.cacheKey.uuidString
        callCtx["last"] = chunk == count - 1
        // Join pause: a cut before "and/but/which…" is a clause join (ChunkEdgeTrim).
        if let word = next?.split(separator: " ").first { callCtx["nextWord"] = String(word) }
        do {
            let duration = try await engine.renderChunkToFile(text: text, destination: url, context: callCtx,
                                                              priority: priority)
            ListenTimingLog.log("chunk_ready", ctx.merging([
                "n": count, "chars": text.count, "ms": ListenTimingLog.ms(since: t0),
                "audio_s": (duration * 100).rounded() / 100, "engine": engine.engineShortName,
            ]) { a, _ in a })
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Backgrounded (or the call was refused because of it): don't write Apple audio into
            // the engine's cache — the chunk renders with the engine once it may run again.
            if case LocalSynthError.deferredInBackground = error { throw error }
            if admission(isLiveRequest: hasLiveWaiters, cacheKey: job.cacheKey) != .render {
                throw LocalSynthError.deferredInBackground
            }
            let localError = error.localizedDescription
            let msg = "\(engine.engineShortName) FAIL p\(index) c\(chunk) → Apple TTS: \(localError)"
            ListenDebugLog.shared.append(msg)
            lastBakeEvent = msg
            // Engine cache voice keys ("kokoro.af_heart") are not Apple voice ids.
            let voice = coordinator.fallbackAppleVoice(forCacheVoice: job.voiceID)
            let duration = try await engine.renderAppleFallback(text: text, destination: url, voiceID: voice)
            ListenTimingLog.log("fallback_apple", ctx.merging([
                "chars": text.count, "ms": ListenTimingLog.ms(since: t0),
                "audio_s": (duration * 100).rounded() / 100, "engine": engine.engineShortName, "local_err": localError,
            ]) { a, _ in a })
        }
    }

    /// Next missing unit: always from current #1’s plan; if #1 complete, advance stack.
    private func nextWorkUnit() -> (ArticleJob, Int)? {
        guard let coordinator else { return nil }
        while let primary = stack.first {
            guard let job = jobs[primary] else {
                stack.removeFirst()
                continue
            }
            let missing = coordinator.audioCache.missingIndices(
                articleID: job.cacheKey,
                paragraphCount: job.paragraphs.count,
                engineID: coordinator.cacheEngineID,
                voiceID: job.voiceID
            )
            let ordered = job.plan.orderedWork(missing: missing).filter { idx in
                guard job.paragraphHashes.indices.contains(idx) else { return false }
                return !failedUnits.contains(failedID(job.cacheKey, idx, job.paragraphHashes[idx]))
            }
            if let index = ordered.first {
                return (job, index)
            }
            // #1 fully baked — demote off the front and try next.
            finishJob(job, missing: missing)
            jobs[primary] = nil
            stack.removeFirst()
            print("[SynthQueue] complete key=\(job.cacheKey.uuidString.prefix(8))")
        }
        return nil
    }

    private func compactCompleted() {
        guard let coordinator else { return }
        stack.removeAll { key in
            guard let job = jobs[key] else { return true }
            let missing = coordinator.audioCache.missingIndices(
                articleID: key,
                paragraphCount: job.paragraphs.count,
                engineID: coordinator.cacheEngineID,
                voiceID: job.voiceID
            )
            if missing.isEmpty {
                jobs[key] = nil
                finishJob(job, missing: missing)
                return true
            }
            return false
        }
    }

    /// Article done: drop its persisted pending job; if every paragraph is in the job's voice,
    /// delete any leftover units of an older voice/engine (one voice per article).
    private func finishJob(_ job: ArticleJob, missing: [Int]) {
        guard let coordinator else { return }
        if missing.isEmpty {
            let freed = coordinator.audioCache.finalizeVoiceSwitch(
                articleID: job.cacheKey, paragraphCount: job.paragraphs.count,
                engineID: coordinator.cacheEngineID, voiceID: job.voiceID)
            if freed > 0 {
                ListenDebugLog.shared.append(
                    "voice switch done \(job.cacheKey.uuidString.prefix(8)): old-voice audio removed (\(FileSizes.label(freed)))")
                coordinator.noteBakeMarksChanged()
            }
        }
        coordinator.bakeCompleted(cacheKey: job.cacheKey)
    }

    private func resumeChunkWaiters(cacheKey: UUID, index: Int, chunk: Int, url: URL) {
        let key = ChunkKey(cacheKey: cacheKey, index: index, chunk: chunk)
        let conts = chunkWaiters.removeValue(forKey: key) ?? []
        for cont in conts { cont.resume(returning: .chunk(url)) }
    }

    /// Paragraph finished: any chunk waiter of it gets a chunk file if kept, else the stitched
    /// paragraph at that chunk's offset.
    private func resumeChunkWaitersWithParagraph(cacheKey: UUID, index: Int, voiceID: String) {
        let keys = chunkWaiters.keys.filter { $0.cacheKey == cacheKey && $0.index == index }
        for key in keys {
            let conts = chunkWaiters.removeValue(forKey: key) ?? []
            guard let resolution = paragraphResolution(cacheKey: cacheKey, index: index, chunk: key.chunk, voiceID: voiceID)
            else { continue }
            for cont in conts { cont.resume(returning: resolution) }
        }
    }

    private func failWaiters(cacheKey: UUID, index: Int, error: Error) {
        let chunkKeys = chunkWaiters.keys.filter { $0.cacheKey == cacheKey && $0.index == index }
        for ck in chunkKeys {
            for cont in chunkWaiters.removeValue(forKey: ck) ?? [] { cont.resume(throwing: error) }
        }
    }

    private func failWaiters(cacheKey: UUID, error: Error) {
        let chunkKeys = chunkWaiters.keys.filter { $0.cacheKey == cacheKey }
        for ck in chunkKeys {
            for cont in chunkWaiters.removeValue(forKey: ck) ?? [] { cont.resume(throwing: error) }
        }
    }

    /// Forget "keep chunk scratch" marks for an article (after its scratch dir was removed).
    func clearLiveChunkMarks(cacheKey: UUID) {
        liveChunkParagraphs = liveChunkParagraphs.filter { $0.cacheKey != cacheKey }
    }
}
