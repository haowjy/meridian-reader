import AVFoundation
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
/// Background (`AppRunState`): no Core ML call starts while the app is backgrounded. Live
/// chunk/unit requests for audio that isn't rendered yet throw `LocalSynthError.deferredInBackground`
/// at once (the producer speaks that paragraph with Apple TTS — never silent, never skipped, and
/// the Apple audio is NOT written into the engine's cache); bake-ahead waits and the worker is
/// restarted when the app becomes active. While `inactive` only chunks a listener waits for render.
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
        var paragraphs: [String]
        var rate: Float
        var voiceID: String
        var plan: BakePriorityPlan
        /// FIFO demotion order among non-#1 articles (lower = older / demoted earlier).
        var demoteOrder: Int
        var isEphemeral: Bool
    }

    private weak var coordinator: SynthQueueContext?
    private var jobs: [UUID: ArticleJob] = [:]
    /// Ordered stack: `stack[0]` is current #1.
    private var stack: [UUID] = []
    private var demoteCounter = 0
    private var worker: Task<Void, Never>?
    private var waiters: [WaitKey: [CheckedContinuation<URL, Error>]] = [:]
    private var chunkWaiters: [ChunkKey: [CheckedContinuation<ChunkResolution, Error>]] = [:]
    /// Paragraphs whose chunk files a live player may reference — keep their scratch after
    /// stitching (cleaned on next open / launch). Pure bake-ahead paragraphs drop scratch at once.
    private var liveChunkParagraphs: Set<WaitKey> = []
    /// (key|index|textHash) that failed the engine *and* Apple fallback — skipped by the worker so a
    /// bad unit cannot spin forever (the old loop retried the same failing paragraph endlessly).
    private var failedUnits: Set<String> = []
    private var chunkPlanCache: [String: [String]] = [:]

    private struct WaitKey: Hashable {
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

    init() {
        observeRunState()
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
        if rendersInBackground {
            // CPU route: nothing to park. Keep the in-flight call alive through suspension races.
            #if canImport(UIKit)
            if phase == .background, worker != nil, usesBackgroundGrace { drainGrace.begin() }
            #endif
            if phase != .background, !stack.isEmpty { kickWorker() }
            if phase == .background, hasLiveWaiters { kickWorker() }
            return
        }
        switch phase {
        case .background:
            if worker != nil {
                // The in-flight chunk finishes (its waiter gets it); the worker then parks and
                // fails the remaining live waiters as deferred.
                #if canImport(UIKit)
                if usesBackgroundGrace { drainGrace.begin() }
                #endif
            } else {
                failAllLiveWaiters(LocalSynthError.deferredInBackground)
            }
        case .inactive:
            if hasLiveWaiters { kickWorker() }
        case .active:
            if !stack.isEmpty { kickWorker() }
        }
    }

    private var hasLiveWaiters: Bool { !waiters.isEmpty || !chunkWaiters.isEmpty }

    /// The active host renders without Core ML/GPU and may run while backgrounded.
    private var rendersInBackground: Bool { coordinator?.activeRouteRendersInBackground ?? false }
    /// May a model call start now (foreground, or a background-capable route)?
    private var canRenderNow: Bool { runState.allowsLocalModelCalls || rendersInBackground }

    private func failAllLiveWaiters(_ error: Error) {
        for key in Array(waiters.keys) {
            for cont in waiters.removeValue(forKey: key) ?? [] { cont.resume(throwing: error) }
        }
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
        rate: Float,
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
            rate: rate,
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
        rate: Float? = nil,
        voiceID: String? = nil
    ) {
        guard var job = jobs[cacheKey] else {
            if let paragraphs, let rate, let voiceID {
                openArticle(
                    cacheKey: cacheKey,
                    paragraphs: paragraphs,
                    rate: rate,
                    voiceID: voiceID,
                    resumeParagraph: paragraph,
                    isEphemeral: false
                )
            }
            return
        }
        if let paragraphs { job.paragraphs = paragraphs }
        if let rate { job.rate = rate }
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
        rate: Float,
        voiceID: String,
        resumeParagraph: Int = 0,
        isEphemeral: Bool
    ) {
        guard !paragraphs.isEmpty else { return }
        if jobs[cacheKey] != nil {
            // Refresh payload but keep stack position.
            var job = jobs[cacheKey]!
            job.paragraphs = paragraphs
            job.rate = rate
            job.voiceID = voiceID
            job.isEphemeral = isEphemeral
            jobs[cacheKey] = job
        } else {
            demoteCounter += 1
            jobs[cacheKey] = ArticleJob(
                cacheKey: cacheKey,
                paragraphs: paragraphs,
                rate: rate,
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

    /// Pending background-bake job (persisted by `BackgroundAudioBakeScheduler`).
    struct PendingWork: Equatable {
        var cacheKey: UUID
        var paragraphs: [String]
        var rate: Float
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
    /// (Before: `priorityStart > 0` jobs went through `openArticle` and stole #1 from the
    /// article being listened to.)
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
                openArticle(cacheKey: job.cacheKey, paragraphs: job.paragraphs, rate: job.rate,
                            voiceID: job.voiceID, resumeParagraph: job.priorityStart, isEphemeral: job.isEphemeral)
            } else {
                enqueueDemoted(cacheKey: job.cacheKey, paragraphs: job.paragraphs, rate: job.rate,
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
        // Move waiters
        let oldKeys = waiters.keys.filter { $0.cacheKey == oldKey }
        for key in oldKeys {
            let conts = waiters.removeValue(forKey: key) ?? []
            let newWait = WaitKey(cacheKey: newKey, index: key.index)
            waiters[newWait, default: []].append(contentsOf: conts)
        }
        for key in chunkWaiters.keys.filter({ $0.cacheKey == oldKey }) {
            let conts = chunkWaiters.removeValue(forKey: key) ?? []
            chunkWaiters[ChunkKey(cacheKey: newKey, index: key.index, chunk: key.chunk), default: []]
                .append(contentsOf: conts)
        }
        kickWorker()
    }

    // MARK: - Live ensure (playhead)

    /// Prefer disk cache; otherwise bump this unit to the front of #1’s plan and await Ready URL.
    func ensureUnit(
        cacheKey: UUID,
        paragraphIndex: Int,
        text: String,
        rate: Float,
        voiceID: String,
        isEphemeral: Bool
    ) async throws -> URL {
        guard let coordinator else {
            throw NSError(
                domain: "GlobalSynthQueue",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Coordinator not attached"]
            )
        }
        let engineID = coordinator.cacheEngineID
        if let url = coordinator.audioCache.audioURL(
            articleID: cacheKey,
            paragraphIndex: paragraphIndex,
            engineID: engineID,
            voiceID: voiceID
        ) {
            return url
        }

        guard canRenderNow else {
            noteBackgroundDeferral(cacheKey, paragraphIndex, chunk: nil)
            throw LocalSynthError.deferredInBackground
        }
        // Make sure this article is #1 and playhead-focused so the worker hits this unit next.
        if jobs[cacheKey] == nil {
            openArticle(
                cacheKey: cacheKey,
                paragraphs: [text], // replaced below if we only have one — caller should openArticle first
                rate: rate,
                voiceID: voiceID,
                resumeParagraph: paragraphIndex,
                isEphemeral: isEphemeral
            )
            // Expand paragraphs if we only seeded one line — prefer full list from caller via openArticle.
            if var job = jobs[cacheKey], job.paragraphs.count == 1, paragraphIndex == 0 {
                job.paragraphs = [text]
                jobs[cacheKey] = job
            }
        } else {
            focusPlayhead(cacheKey: cacheKey, paragraph: paragraphIndex, rate: rate, voiceID: voiceID)
            if var job = jobs[cacheKey], job.paragraphs.indices.contains(paragraphIndex) == false
                || job.paragraphs[paragraphIndex] != text {
                // Keep text in sync for this index when possible.
                if job.paragraphs.indices.contains(paragraphIndex) {
                    job.paragraphs[paragraphIndex] = text
                    jobs[cacheKey] = job
                }
            }
        }

        // If still only a stub job with wrong length, patch this index's text into a minimal list.
        if var job = jobs[cacheKey] {
            if !job.paragraphs.indices.contains(paragraphIndex) {
                while job.paragraphs.count <= paragraphIndex {
                    job.paragraphs.append("")
                }
                job.paragraphs[paragraphIndex] = text
                job.plan = .fromPlayhead(paragraphIndex, paragraphCount: job.paragraphs.count)
                jobs[cacheKey] = job
            }
        }

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            let key = WaitKey(cacheKey: cacheKey, index: paragraphIndex)
            waiters[key, default: []].append(cont)
            kickWorker()
        }
    }

    // MARK: - Chunk-level live ensure (play-while-building)

    /// Synth chunks for a paragraph's text (deterministic; cached by text hash).
    func chunkTexts(for text: String) -> [String] {
        let engine = coordinator?.cacheEngineID ?? "?"
        let hash = engine + "|" + ArticleIdentity.paragraphHash(text)
        if let cached = chunkPlanCache[hash] { return cached }
        let chunks = TextChunker.chunks(for: text, limits: coordinator?.activeChunkLimits ?? .kokoro)
        chunkPlanCache[hash] = chunks
        return chunks
    }

    /// Local engine or engine voice switched: chunk plans, chunk scratch and failure marks
    /// belong to the old engine. Paragraph CAFs are keyed by engine+voice in `index.json`,
    /// so stale ones are simply not matched (and get replaced as the new engine bakes).
    /// Voice or engine changed: drop chunk plans/scratch (rendered in the old voice) and retarget
    /// every queued article to the new cache voice so the worker re-renders in it. Old-voice
    /// paragraph CAFs stay playable until each paragraph is replaced (`playableAudioURL`).
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
        rate: Float,
        voiceID: String,
        isEphemeral: Bool
    ) async throws -> ChunkResolution {
        guard let coordinator else {
            throw NSError(domain: "GlobalSynthQueue", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Coordinator not attached"])
        }
        let cache = coordinator.audioCache
        let hash = ArticleIdentity.paragraphHash(text)
        let unit = WaitKey(cacheKey: cacheKey, index: paragraphIndex)
        liveChunkParagraphs.insert(unit)
        failedUnits.remove(failedID(cacheKey, paragraphIndex, hash)) // live request = fresh try

        let chunkURL = cache.chunkURL(articleID: cacheKey, paragraphIndex: paragraphIndex, textHash: hash, chunk: chunk)
        if cache.isUsableChunk(chunkURL) { return .chunk(chunkURL) }
        if let resolved = paragraphResolution(cacheKey: cacheKey, index: paragraphIndex, chunk: chunk, voiceID: voiceID) {
            return resolved
        }

        // Background: don't wait for a render that can't happen — the producer speaks it with
        // Apple. Don't move the cursor either (the producer pre-renders Apple units far ahead);
        // on return the listen engine refocuses at the paragraph it restarts from.
        guard canRenderNow else {
            noteBackgroundDeferral(cacheKey, paragraphIndex, chunk: chunk)
            throw LocalSynthError.deferredInBackground
        }
        // Make this article #1 with the cursor on this paragraph.
        if jobs[cacheKey] == nil || jobs[cacheKey]?.paragraphs.count != paragraphs.count {
            openArticle(cacheKey: cacheKey, paragraphs: paragraphs, rate: rate, voiceID: voiceID,
                        resumeParagraph: paragraphIndex, isEphemeral: isEphemeral)
        }
        focusPlayhead(cacheKey: cacheKey, paragraph: paragraphIndex, rate: rate, voiceID: voiceID)
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
        if cache.isUsableChunk(url) { return true }
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

    // MARK: - Diagnostics

    /// Currently rendering unit (nil when idle between units / empty queue).
    private(set) var activeBakeCacheKey: UUID?
    private(set) var activeBakeIndex: Int?
    /// One-line last bake success/fail for the listen debug overlay.
    private(set) var lastBakeEvent: String = "—"

    var primaryCacheKey: UUID? { stack.first }
    var queuedArticleCount: Int { stack.count }
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

    /// Compact live snapshot for the bake debug overlay.
    func bakeDebugDescription() -> String {
        guard let primary = stack.first, let job = jobs[primary] else {
            return "queue empty · worker \(isWorkerRunning ? "busy" : "idle")"
        }
        let kind = job.isEphemeral ? "eph" : "svd"
        let short = "\(kind):\(primary.uuidString.prefix(8))"
        let active: String
        if let ak = activeBakeCacheKey, let ai = activeBakeIndex {
            let aKind = (jobs[ak]?.isEphemeral == true) ? "eph" : "svd"
            active = "\(aKind):\(ak.uuidString.prefix(8)) p\(ai)"
        } else {
            active = "—"
        }
        let next = nextMissingIndex(for: primary).map { "p\($0)" } ?? "—"
        return "#1 \(short) demoted=\(demotedCount) active=\(active) next=\(next)"
    }

    // MARK: - Private

    private func upsert(
        cacheKey: UUID,
        paragraphs: [String],
        rate: Float,
        voiceID: String,
        plan: BakePriorityPlan,
        isEphemeral: Bool,
        makePrimary: Bool
    ) {
        demoteCounter += 1
        let existingOrder = jobs[cacheKey]?.demoteOrder ?? demoteCounter
        jobs[cacheKey] = ArticleJob(
            cacheKey: cacheKey,
            paragraphs: paragraphs,
            rate: rate,
            voiceID: voiceID,
            plan: plan,
            demoteOrder: makePrimary ? existingOrder : demoteCounter,
            isEphemeral: isEphemeral
        )
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

    private func kickWorker() {
        guard worker == nil, !isPausedForProbe else { return }
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
        while !isPausedForProbe, let next = nextWorkUnit() {
            guard let coordinator else { break }
            // Check the app state before every chunk (never a Core ML call in the background).
            if !canRenderNow {
                failAllLiveWaiters(LocalSynthError.deferredInBackground)
                lastBakeEvent = "background: Kokoro paused (bake resumes in foreground)"
                ListenTimingLog.log("synth_queue_parked", ["phase": runState.phase.rawValue])
                return
            }
            if runState.phase == .background, rendersInBackground {
                // CPU route in the background: the listener's chunks + bake-ahead of the article
                // that is playing. Other articles wait for the foreground (battery).
                if !hasLiveWaiters, next.0.cacheKey != coordinator.backgroundRenderCacheKey {
                    lastBakeEvent = "background: holding bake of other articles"
                    ListenTimingLog.log("synth_queue_parked", ["phase": "background", "reason": "not_playing_article"])
                    return
                }
                #if canImport(UIKit)
                if usesBackgroundGrace { drainGrace.begin() }
                #endif
            } else if !runState.allowsBakeAhead, !rendersInBackground, !hasLiveWaiters {
                ListenTimingLog.log("synth_queue_parked", ["phase": runState.phase.rawValue])
                return // inactive: resume on becoming active (or when a listener waits)
            }
            let (job, index) = next
            let engineID = coordinator.cacheEngineID
            let cache = coordinator.audioCache
            // Already ready?
            if let url = cache.audioURL(articleID: job.cacheKey, paragraphIndex: index,
                                        engineID: engineID, voiceID: job.voiceID) {
                resumeWaiters(cacheKey: job.cacheKey, index: index, url: url)
                resumeChunkWaitersWithParagraph(cacheKey: job.cacheKey, index: index, voiceID: job.voiceID)
                continue
            }
            guard job.paragraphs.indices.contains(index) else { continue }
            let text = job.paragraphs[index]
            let hash = ArticleIdentity.paragraphHash(text)
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
                // A listener waiting on a later chunk (scrubbed to a sentence mid-paragraph, Nav I)
                // gets that chunk first; otherwise chunks render in order.
                let waited = chunkWaiters.keys
                    .filter { $0.cacheKey == job.cacheKey && $0.index == index }
                    .map(\.chunk).sorted()
                    .first { chunkURLs.indices.contains($0) && !cache.isUsableChunk(chunkURLs[$0]) }
                if let k = waited ?? chunkURLs.firstIndex(where: { !cache.isUsableChunk($0) }) {
                    // Render ONE chunk, then loop (re-evaluates priority between chunks).
                    try await renderChunk(job: job, index: index, chunk: k, of: chunks.count,
                                          text: chunks[k], next: k + 1 < chunks.count ? chunks[k + 1] : nil,
                                          to: chunkURLs[k], hash: hash)
                    resumeChunkWaiters(cacheKey: job.cacheKey, index: index, chunk: k, url: chunkURLs[k])
                    if chunkURLs.allSatisfy(cache.isUsableChunk) == false {
                        activeBakeCacheKey = nil
                        activeBakeIndex = nil
                        continue
                    }
                }
                // All chunks present → stitch into the paragraph CAF.
                let dir = cache.directory(for: job.cacheKey)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                // Stitch beside the final file, then store (replaces p-NNNN.caf with a new file):
                // the old-voice CAF at that path may be playing right now — never write into it.
                let staging = dir.appendingPathComponent(String(format: ".stitch-p-%04d.caf", index))
                defer { try? FileManager.default.removeItem(at: staging) }
                let stitched = try ChunkAudioStitcher.stitch(chunkURLs, to: staging)
                let stored = try cache.storeParagraph(
                    articleID: job.cacheKey,
                    paragraphIndex: index,
                    sourceURL: staging,
                    duration: stitched.duration,
                    engineID: engineID,
                    voiceID: job.voiceID,
                    rate: job.rate,
                    text: text,
                    chunkDurations: chunks.count > 1 ? stitched.chunkDurations : nil
                )
                coordinator.noteBakeMarksChanged()
                if job.isEphemeral {
                    cache.markEphemeral(cacheKey: job.cacheKey, lastAccess: Date())
                }
                if !liveChunkParagraphs.contains(WaitKey(cacheKey: job.cacheKey, index: index)) {
                    try? FileManager.default.removeItem(
                        at: cache.chunkDirectory(articleID: job.cacheKey, paragraphIndex: index, textHash: hash))
                }
                resumeWaiters(cacheKey: job.cacheKey, index: index, url: stored)
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
                lastBakeEvent = "background: Kokoro paused at \(job.cacheKey.uuidString.prefix(8)) p\(index)"
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

    private struct NothingSpeakable: LocalizedError {
        var errorDescription: String? { "Nothing speakable in paragraph" }
    }

    /// Engine first (recursive re-split inside the renderer); Apple TTS for this chunk if the engine
    /// still fails. Throws only when both fail.
    private func renderChunk(
        job: ArticleJob, index: Int, chunk: Int, of count: Int, text: String, next: String? = nil,
        to url: URL, hash: String
    ) async throws {
        guard let coordinator else { throw CancellationError() }
        let engine = coordinator.synthRenderer
        let t0 = ListenTimingLog.now()
        let ctx: [String: Any] = [
            "key": ListenTimingLog.shortKey(job.cacheKey), "p": index, "c": chunk,
            "primary": stack.first == job.cacheKey,
        ]
        // Full key rides along for the crash marker only (auto-resume); not logged per chunk.
        var callCtx = ctx
        callCtx["article"] = job.cacheKey.uuidString
        callCtx["last"] = chunk == count - 1
        // Join pause: a cut before "and/but/which…" is a clause join (ChunkEdgeTrim).
        if let word = next?.split(separator: " ").first { callCtx["nextWord"] = String(word) }
        do {
            let duration = try await engine.renderChunkToFile(
                text: text, destination: url, seed: Self.stableSeed(text, chunk: chunk), context: callCtx)
            ListenTimingLog.log("chunk_ready", ctx.merging([
                "n": count, "chars": text.count, "ms": ListenTimingLog.ms(since: t0),
                "audio_s": (duration * 100).rounded() / 100, "engine": engine.engineShortName,
            ]) { a, _ in a })
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Backgrounded (or the call was refused because of it): don't write Apple audio into
            // the engine's cache — the chunk renders with the engine once back in the foreground.
            if case LocalSynthError.deferredInBackground = error { throw error }
            if !canRenderNow { throw LocalSynthError.deferredInBackground }
            let localError = error.localizedDescription
            let msg = "\(engine.engineShortName) FAIL p\(index) c\(chunk) → Apple TTS: \(localError)"
            ListenDebugLog.shared.append(msg)
            lastBakeEvent = msg
            // Rendered at 1×: the listen speed is applied by the player (time stretch, Nav I).
            let appleRate = AVSpeechUtteranceDefaultSpeechRate
            // Engine cache voice keys ("kokoro.af_heart") are not Apple voice ids.
            let voice = coordinator.fallbackAppleVoice(forCacheVoice: job.voiceID)
            let duration = try await engine.renderAppleFallback(text: text, destination: url, rate: appleRate, voiceID: voice)
            ListenTimingLog.log("fallback_apple", ctx.merging([
                "chars": text.count, "ms": ListenTimingLog.ms(since: t0),
                "audio_s": (duration * 100).rounded() / 100, "engine": engine.engineShortName, "local_err": localError,
            ]) { a, _ in a })
        }
    }

    /// Process-stable seed (Swift `Hasher` is randomized per launch).
    static func stableSeed(_ text: String, chunk: Int) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in text.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return h &+ UInt64(chunk)
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
                guard job.paragraphs.indices.contains(idx) else { return false }
                return !failedUnits.contains(failedID(job.cacheKey, idx, ArticleIdentity.paragraphHash(job.paragraphs[idx])))
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

    private func resumeWaiters(cacheKey: UUID, index: Int, url: URL) {
        let key = WaitKey(cacheKey: cacheKey, index: index)
        let conts = waiters.removeValue(forKey: key) ?? []
        for cont in conts { cont.resume(returning: url) }
    }

    private func failWaiters(cacheKey: UUID, index: Int, error: Error) {
        let key = WaitKey(cacheKey: cacheKey, index: index)
        let conts = waiters.removeValue(forKey: key) ?? []
        for cont in conts { cont.resume(throwing: error) }
        let chunkKeys = chunkWaiters.keys.filter { $0.cacheKey == cacheKey && $0.index == index }
        for ck in chunkKeys {
            for cont in chunkWaiters.removeValue(forKey: ck) ?? [] { cont.resume(throwing: error) }
        }
    }

    private func failWaiters(cacheKey: UUID, error: Error) {
        let keys = waiters.keys.filter { $0.cacheKey == cacheKey }
        for key in keys {
            let conts = waiters.removeValue(forKey: key) ?? []
            for cont in conts { cont.resume(throwing: error) }
        }
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

/// What `GlobalSynthQueue` needs from its owner. `LocalTTSCoordinator` in the app; a fake in tests.
@MainActor
protocol SynthQueueContext: AnyObject {
    var audioCache: ArticleAudioCache { get }
    /// `ArticleAudioCache` engine key of the active local engine.
    var cacheEngineID: String { get }
    /// Chunk sizing of the active local engine (from its `EngineDescriptor`).
    var activeChunkLimits: TextChunker.Limits { get }
    var synthRenderer: SynthChunkRendering { get }
    /// Apple voice for the never-skip fallback given a cache voice key (nil = system default).
    func fallbackAppleVoice(forCacheVoice voiceID: String) -> String?
    /// Map a (possibly stale) cache voice key onto the active engine/voice key space.
    func normalizedCacheVoice(_ voiceID: String) -> String
    func noteBakeMarksChanged()
    /// An article is fully baked (drop its persisted pending job).
    func bakeCompleted(cacheKey: UUID)
    /// The active local host may render while the app is backgrounded (Kokoro ONNX CPU route).
    var activeRouteRendersInBackground: Bool { get }
    /// Article playing right now (background bake-ahead is limited to it); nil = not playing.
    var backgroundRenderCacheKey: UUID? { get }
}

extension SynthQueueContext {
    var activeRouteRendersInBackground: Bool { false }
    var backgroundRenderCacheKey: UUID? { nil }
}

/// Renders one synth chunk with the active local engine, or with Apple as the fallback.
@MainActor
protocol SynthChunkRendering: AnyObject {
    var engineShortName: String { get }
    func renderChunkToFile(text: String, destination: URL, seed: UInt64, context: [String: Any]) async throws -> TimeInterval
    func renderAppleFallback(text: String, destination: URL, rate: Float, voiceID: String?) async throws -> TimeInterval
}
