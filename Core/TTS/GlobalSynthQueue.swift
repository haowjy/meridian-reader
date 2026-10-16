import Foundation

/// Single global Core ML synth work queue for all Listen audio.
///
/// Actions **reorganize** this queue — they do not spawn separate bake systems.
///
/// Priority rules:
/// 1. `enqueue(at: .front)` — that article becomes #1; synthesize from its start (or resume)
///    downward, then the paragraphs above. `.back` queues it behind what is there.
/// 2. `focusPlayhead` — same article stays #1; cursor moves to paragraph→end, then gap-fill top.
/// 3. Opening a different article demotes the previous #1 (cache kept); worker switches to new #1.
/// 4. One worker drains #1’s next missing unit, then continues.
/// 5. `stageNext` — the next chapter of the book or series playing sits right behind the playing
///    chapter's job (at the front once that job is done) and renders its first paragraphs before
///    any other work, the playing chapter's paragraphs above its playhead included
///    (`playingCacheKeys` admits it in the background like the playing article).
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
/// route nothing renders while the app is backgrounded: a live chunk request for audio that isn't
/// rendered yet throws `LocalSynthError.deferredInBackground` at once (the producer speaks that
/// paragraph with Apple TTS, never silent or skipped, and the Apple audio is not written into the
/// engine's cache); bake-ahead waits until the app is active; while `inactive` only chunks a
/// listener waits for render. A route that renders in the background (Kokoro's ONNX CPU route,
/// `SynthQueueContext.activeRouteRendersInBackground`) treats `inactive` like `active`; in the
/// background it renders live requests and bakes the playing article ahead, from its playhead
/// on, in bursts (`BackgroundRenderBursts`), idle in between until playback wakes it
/// (`playbackAdvanced`).
///
/// Priority: renders for an article someone is listening to (a chunk waiter, or its audio playing)
/// run at `.listener` priority; everything else is bake-ahead — a cooler QoS, and held while the
/// device is hot or in Low Power Mode (`BakeConditions`).
///
/// What it renders for is the context's `renderTarget`: the loaded engine and its voice. Jobs carry
/// no voice; every readiness check, chunk file and publish uses the target read at that step, so
/// a voice switch can't file one voice's audio under another. While there is no target (Apple
/// selected, a model loading, failed or deleted) the worker parks (`RenderAdmission`) and never
/// loads a model itself; the coordinator restarts it once an engine is ready
/// (`renderTargetChanged`).
///
/// Depends only on `SynthQueueContext` (cache, render target, chunk limits, renderer), never on a
/// concrete engine — the app passes `LocalTTSCoordinator`, tests pass a fake.
@MainActor
final class GlobalSynthQueue {
    private weak var coordinator: SynthQueueContext?
    private var jobs: [UUID: ArticleJob] = [:]
    /// Ordered stack: `stack[0]` is current #1.
    private var stack: [UUID] = []
    /// The next chapter of the book or series playing, rendering its opening ahead (`stageNext`).
    private var staged: StagedJob?
    private var worker: Task<Void, Never>?
    private var chunkWaiters: [ChunkKey: [CheckedContinuation<ChunkResolution, Error>]] = [:]
    /// Paragraphs whose chunk files a live player may reference — keep their scratch after
    /// stitching (cleaned on next open / launch). Pure bake-ahead paragraphs drop scratch at once.
    private var liveChunkParagraphs: Set<ParagraphKey> = []
    /// (key|index|textHash) that failed the engine *and* Apple fallback — skipped by the worker so a
    /// bad unit cannot spin forever. A live request for the unit clears its mark (fresh try).
    private var failedUnits: Set<String> = []

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
    /// Bake-ahead of the playing article in the background, on a route that renders there.
    private let backgroundBursts = BackgroundRenderBursts()
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
        if phase != .background { backgroundBursts.end(reason: "foreground", readyAhead: readyAhead) }
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
        } else {
            playbackAdvanced()
        }
    }

    /// Playback moved on (a unit started, or playback resumed). In the background the worker idles
    /// between bursts and starts again here once less than the low-water mark of listening is
    /// ready ahead (`BackgroundRenderWatermarks`); units start often enough that no timer is needed.
    func playbackAdvanced() {
        guard worker == nil, runState.phase == .background, rendersInBackground,
              stack.contains(where: playingCacheKeys.contains),
              readyAhead() < BackgroundRenderWatermarks.lowWater else { return }
        kickWorker()
    }

    /// Listening time ready ahead of the playhead, counted up to the high-water mark.
    private func readyAhead() -> TimeInterval {
        coordinator?.readyAheadSeconds(upTo: BackgroundRenderWatermarks.highWater) ?? 0
    }

    private var hasLiveWaiters: Bool { !chunkWaiters.isEmpty }

    /// The active host renders without Core ML/GPU and may run while backgrounded.
    private var rendersInBackground: Bool { coordinator?.activeRouteRendersInBackground ?? false }

    /// The audio that renders in the background on a route that may (`RenderAdmission`): the
    /// article playing and the chapter staged to play after it.
    var playingCacheKeys: Set<UUID> {
        Set([coordinator?.playingCacheKey, staged?.cacheKey].compactMap { $0 })
    }

    /// `RenderAdmission` for audio of `cacheKey` now.
    private func admission(isLiveRequest: Bool, cacheKey: UUID?) -> RenderAdmission {
        RenderAdmission.decide(engineReady: coordinator?.renderTarget != nil,
                               phase: runState.phase, rendersInBackground: rendersInBackground,
                               isLiveRequest: isLiveRequest,
                               isPlayingArticle: cacheKey.map(playingCacheKeys.contains) ?? false,
                               inBackgroundBurst: backgroundBursts.isBursting)
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

    /// Where `enqueue` puts a job.
    enum Placement: Equatable {
        /// #1: it renders next (an article opened, played, a jump). A staged chapter put here is
        /// playing: its cap lifts.
        case front
        /// Last, or where it already is (a save, a download, work adopted from disk).
        case back
        /// Right behind this job, or at the front when it isn't queued (the staged next chapter).
        case behind(UUID?)
    }

    /// Queue `cacheKey` to render `paragraphs`, or refresh its queued job, and place it. A job
    /// put at the front renders from paragraph `start` to the end, then the paragraphs above it; a
    /// queued job placed anywhere else keeps its start, and a new one starts at `start`. A queued
    /// job keeps its paragraph hashes when the text is unchanged (every play and seek opens the
    /// article again).
    func enqueue(cacheKey: UUID, paragraphs: [String], from start: Int = 0, isEphemeral: Bool, at placement: Placement) {
        guard !paragraphs.isEmpty else { return }
        if var job = jobs[cacheKey] {
            let resume = placement == .front ? start : job.plan.priorityStart
            job.paragraphs = paragraphs
            job.plan = BakePriorityPlan(resume: resume, count: paragraphs.count)
            job.isEphemeral = isEphemeral
            jobs[cacheKey] = job
        } else {
            jobs[cacheKey] = ArticleJob(cacheKey: cacheKey, paragraphs: paragraphs,
                                        plan: BakePriorityPlan(resume: start, count: paragraphs.count),
                                        isEphemeral: isEphemeral)
        }
        place(cacheKey, placement)
        kickWorker()
    }

    /// Same article stays #1; move priority cursor to `paragraph` → end, then gap-fill top.
    func focusPlayhead(cacheKey: UUID, paragraph: Int) {
        guard var job = jobs[cacheKey] else { return }
        job.plan = BakePriorityPlan(resume: paragraph, count: job.paragraphs.count)
        jobs[cacheKey] = job
        place(cacheKey, .front)
        kickWorker()
    }

    /// The next chapter of the book or series playing, staged directly behind the job of
    /// `playing` (the chapter playing), or at the front when that job has left the queue (its
    /// audio is all rendered): either way ahead of any save or bake job, which in the background
    /// may have to wait for the foreground. So its opening renders first, in the background too
    /// on a route that may render there (`playingCacheKeys`). It renders at bake-ahead priority,
    /// never `.listener`, and only its first `cap` paragraphs until it becomes #1 (it plays), when
    /// the cap lifts. At its cap it steps aside, so jobs behind it keep running. A later stage
    /// replaces it.
    func stageNext(cacheKey: UUID, after playing: UUID?, paragraphs: [String], upTo cap: Int, isEphemeral: Bool) {
        guard !paragraphs.isEmpty, stack.first != cacheKey else { return }
        if let staged, staged.cacheKey != cacheKey { unstage() }
        let wasQueued = staged?.wasQueued ?? (jobs[cacheKey] != nil)
        enqueue(cacheKey: cacheKey, paragraphs: paragraphs, isEphemeral: isEphemeral, at: .behind(playing))
        staged = StagedJob(cacheKey: cacheKey, behind: playing, cap: cap, wasQueued: wasQueued)
        let position = stack.firstIndex(of: cacheKey) ?? 0
        ListenTimingLog.log("chapter_staged", ["key": ListenTimingLog.shortKey(cacheKey), "cap": cap,
                                               "behind": ListenTimingLog.shortKey(position > 0 ? stack[position - 1] : nil)])
    }

    /// The staged job's place: right behind the playing chapter's job while that is queued, else
    /// at the front. Set again before each pick of work, as the queue changes: the playing
    /// chapter promoted back to #1 (after another page opened) takes it along, and once that
    /// chapter's job is done it moves to the front rather than wait behind a job that may not
    /// render in the background.
    private func placeStaged() {
        guard let staged, jobs[staged.cacheKey] != nil else { return }
        place(staged.cacheKey, .behind(staged.behind))
    }

    private func place(_ cacheKey: UUID, _ placement: Placement) {
        switch placement {
        case .front:
            stack.removeAll { $0 == cacheKey }
            stack.insert(cacheKey, at: 0)
            if staged?.cacheKey == cacheKey { staged = nil }
        case .back:
            if !stack.contains(cacheKey) { stack.append(cacheKey) }
        case .behind(let job):
            stack.removeAll { $0 == cacheKey }
            let position = job.flatMap { stack.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
            stack.insert(cacheKey, at: position)
        }
    }

    /// The staged chapter won't play next (another page plays, the book ended): a job staging
    /// made leaves the queue (its audio stays); one queued before stays where staging put it.
    func unstage() {
        guard let staged else { return }
        self.staged = nil
        guard !staged.wasQueued else { return }
        jobs[staged.cacheKey] = nil
        stack.removeAll { $0 == staged.cacheKey }
    }

    var stagedCacheKey: UUID? { staged?.cacheKey }

    /// Drop an article from the queue (delete / clear audio). Does not delete disk files.
    func remove(cacheKey: UUID) {
        jobs[cacheKey] = nil
        stack.removeAll { $0 == cacheKey }
        if staged?.cacheKey == cacheKey { staged = nil }
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
    /// them (`stillWants`). Its place in the queue and plan stay; the plan's start moves to the
    /// same place in the new text.
    func updateParagraphs(cacheKey: UUID, paragraphs: [String]) {
        guard !paragraphs.isEmpty, var job = jobs[cacheKey], job.paragraphs != paragraphs else { return }
        let start = ParagraphPositionMap.mapParagraphStart(job.plan.priorityStart, from: ParagraphDocument(parts: job.paragraphs),
                                                           to: ParagraphDocument(parts: paragraphs))
        job.plan = BakePriorityPlan(resume: start, count: paragraphs.count)
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
        if staged?.cacheKey == oldKey { staged?.cacheKey = newKey }
        if staged?.behind == oldKey { staged?.behind = newKey }
        for key in chunkWaiters.keys.filter({ $0.cacheKey == oldKey }) {
            let conts = chunkWaiters.removeValue(forKey: key) ?? []
            chunkWaiters[ChunkKey(cacheKey: newKey, index: key.index, chunk: key.chunk), default: []]
                .append(contentsOf: conts)
        }
        kickWorker()
    }

    // MARK: - Chunk-level live ensure (play-while-building)

    /// Synth chunks of a paragraph's text for the active engine (`ChunkPlans`): what the listen
    /// player plays chunk by chunk.
    func chunkTexts(for text: String) -> [String] {
        guard let coordinator else { return [] }
        return coordinator.chunkPlans.chunks(for: text, engineID: coordinator.cacheEngineID) ?? []
    }

    /// The render target changed (an engine loaded or went away, another voice): failure marks
    /// were the old target's, and once an engine is ready the worker renders what is queued, in
    /// the new voice. Nothing else is retargeted: jobs carry no voice. Paragraph CAFs are keyed
    /// by engine+voice in `index.json`: old-voice ones stay playable until each paragraph is
    /// replaced (`playableAudioURL`) but never count as ready. Chunk scratch is filed by voice
    /// and stays (the launch clears it).
    func renderTargetChanged() {
        failedUnits.removeAll()
        guard coordinator?.renderTarget != nil, !stack.isEmpty else { return }
        kickWorker()
    }

    /// Await a playable URL for chunk `chunk` of `paragraphIndex`. Moves the playhead cursor
    /// to this paragraph so the worker renders its next missing chunk before any bake-ahead.
    func ensureChunk(
        cacheKey: UUID,
        paragraphIndex: Int,
        chunk: Int,
        text: String,
        paragraphs: [String],
        isEphemeral: Bool
    ) async throws -> ChunkResolution {
        guard let coordinator else {
            throw NSError(domain: "GlobalSynthQueue", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Coordinator not attached"])
        }
        // No engine loaded: nothing will render it (the controller moves listening to Apple).
        guard let target = coordinator.renderTarget else { throw Self.noEngine }
        let cache = coordinator.audioCache
        let hash = ArticleIdentity.paragraphHash(text)
        let unit = ParagraphKey(cacheKey: cacheKey, index: paragraphIndex)
        liveChunkParagraphs.insert(unit)
        failedUnits.remove(failedID(cacheKey, paragraphIndex, hash)) // live request = fresh try

        let chunkURL = cache.chunkURL(articleID: cacheKey, paragraphIndex: paragraphIndex, textHash: hash,
                                      voice: target.cacheVoice, chunk: chunk)
        if cache.isUsableAudioFile(chunkURL) { return .chunk(chunkURL) }
        if let resolved = paragraphResolution(cacheKey: cacheKey, index: paragraphIndex, chunk: chunk) {
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
            enqueue(cacheKey: cacheKey, paragraphs: paragraphs, from: paragraphIndex, isEphemeral: isEphemeral, at: .front)
        } else {
            focusPlayhead(cacheKey: cacheKey, paragraph: paragraphIndex)
        }
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
    func isChunkReady(cacheKey: UUID, paragraphIndex: Int, chunk: Int, text: String) -> Bool {
        guard let coordinator, let target = coordinator.renderTarget else { return false }
        let cache = coordinator.audioCache
        let url = cache.chunkURL(articleID: cacheKey, paragraphIndex: paragraphIndex,
                                 textHash: ArticleIdentity.paragraphHash(text), voice: target.cacheVoice, chunk: chunk)
        if cache.isUsableAudioFile(url) { return true }
        return paragraphResolution(cacheKey: cacheKey, index: paragraphIndex, chunk: chunk) != nil
    }

    /// The stitched paragraph in the render target's voice, at chunk `chunk`'s offset.
    private func paragraphResolution(cacheKey: UUID, index: Int, chunk: Int) -> ChunkResolution? {
        guard let coordinator, let target = coordinator.renderTarget,
              let url = coordinator.audioCache.audioURL(
                articleID: cacheKey, paragraphIndex: index,
                engineID: target.engineID, voiceID: target.cacheVoice)
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
        guard let job = jobs[cacheKey], let target = coordinator?.renderTarget else { return 0 }
        return missingParagraphs(of: job, in: target).count
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
        guard let target = coordinator?.renderTarget else { return nil }
        let key = cacheKey ?? stack.first
        guard let key, let job = jobs[key] else { return nil }
        return job.plan.orderedWork(missing: missingParagraphs(of: job, in: target)).first
    }

    // MARK: - Private

    /// Paragraphs of `job` that still need audio in the target's voice
    /// (`ArticleAudioCache.missingParagraphs`).
    private func missingParagraphs(of job: ArticleJob, in target: RenderTarget) -> [Int] {
        guard let coordinator else { return [] }
        return coordinator.audioCache.missingParagraphs(articleID: job.cacheKey, paragraphs: job.paragraphs,
                                                        engineID: target.engineID, voiceID: target.cacheVoice,
                                                        plans: coordinator.chunkPlans)
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
        var stopReason = "queue_empty"
        defer {
            worker = nil
            activeBakeCacheKey = nil
            activeBakeIndex = nil
            backgroundBursts.end(reason: stopReason, readyAhead: readyAhead)
            #if canImport(UIKit)
            drainGrace.end()
            #endif
        }
        while !isPausedForProbe, !isHeldForLaunch, let coordinator {
            guard let target = coordinator.renderTarget else {
                // No engine loaded (`RenderAdmission`): `renderTargetChanged` restarts the worker
                // once one is. Nothing here may load a model.
                failAllLiveWaiters(Self.noEngine)
                lastBakeEvent = "no on-device voice loaded: rendering waits"
                ListenTimingLog.log("synth_queue_parked", ["phase": runState.phase.rawValue, "reason": "no_engine"])
                stopReason = "no_engine"
                return
            }
            guard let next = nextWorkUnit(in: target) else { break }
            #if canImport(UIKit)
            drainGrace.end() // the chunk in flight at backgrounding is done; playing audio keeps the app alive
            #endif
            // Check the app state before every chunk (see `RenderAdmission`).
            let phase = runState.phase
            let playing = playingCacheKeys.contains(next.0.cacheKey)
            if phase == .background, rendersInBackground, playing, !hasLiveWaiters {
                backgroundBursts.update(readyAhead: readyAhead())
            }
            guard admission(isLiveRequest: hasLiveWaiters, cacheKey: next.0.cacheKey) == .render else {
                // Restarted by `runStateChanged`, `playbackAdvanced` (or a listener's request).
                failAllLiveWaiters(LocalSynthError.deferredInBackground)
                stopReason = noteParked(phase: phase, engine: coordinator.synthRenderer.engineShortName,
                                        playing: playing)
                return
            }
            let (job, index) = next
            let priority = renderPriority(for: job.cacheKey)
            if priority == .bakeAhead, let hold = bakeConditions().bakeAheadHold {
                lastBakeEvent = "bake-ahead held: \(hold.label) (resumes when it clears)"
                ListenTimingLog.log("synth_queue_parked", ["phase": runState.phase.rawValue, "reason": hold.label])
                stopReason = "bake_held"
                return // `bakeConditionsChanged` (or a listener's request) restarts the worker
            }
            let cache = coordinator.audioCache
            // Already ready?
            if cache.audioURL(articleID: job.cacheKey, paragraphIndex: index,
                              engineID: target.engineID, voiceID: target.cacheVoice) != nil {
                resumeChunkWaitersWithParagraph(cacheKey: job.cacheKey, index: index)
                continue
            }
            guard job.paragraphs.indices.contains(index) else { continue }
            let text = job.paragraphs[index]
            let hash = job.paragraphHashes[index]
            // Never empty: a paragraph with nothing to speak is never missing.
            let chunks = coordinator.chunkPlans.chunks(for: text, engineID: target.engineID) ?? []
            activeBakeCacheKey = job.cacheKey
            activeBakeIndex = index
            let chunkURLs = chunks.indices.map {
                cache.chunkURL(articleID: job.cacheKey, paragraphIndex: index, textHash: hash,
                               voice: target.cacheVoice, chunk: $0)
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
                                          to: chunkURLs[k], for: target, priority: priority)
                    guard coordinator.renderTarget == target else {
                        // The engine or voice changed during the call: the chunk is filed under
                        // its own voice, and its waiters wait for the new voice's render.
                        activeBakeCacheKey = nil
                        activeBakeIndex = nil
                        continue
                    }
                    backgroundBursts.noteChunkRendered()
                    resumeChunkWaiters(cacheKey: job.cacheKey, index: index, chunk: k, url: chunkURLs[k])
                    if chunkURLs.allSatisfy(cache.isUsableAudioFile) == false {
                        activeBakeCacheKey = nil
                        activeBakeIndex = nil
                        continue
                    }
                }
                // All chunks present → stitch them off the main actor (a read / convert / write
                // of the whole paragraph) into a file of their own, then publish it here only if
                // the queue still wants this text on this paragraph, in this voice. Meanwhile the
                // article's audio may have been aligned with other paragraphs (opening it with
                // newer text, a merge) and its job given them, the article left the queue (audio
                // cleared, deleted, rekeyed), or the voice changed: a render of the old paragraph
                // or voice isn't filed on the new one.
                let staged = cache.stitchingURL(articleID: job.cacheKey, paragraphIndex: index, textHash: hash,
                                                voice: target.cacheVoice)
                let stitched: ChunkAudioStitcher.Result
                do {
                    stitched = try await Task.detached(priority: priority.taskPriority) {
                        try ArticleAudioCache.stitchParagraph(chunkURLs, to: staged)
                    }.value
                } catch where !chunkURLs.allSatisfy(cache.isUsableAudioFile) {
                    // The chunk scratch went away meanwhile (identity prep): not this paragraph's
                    // failure — look again.
                    try? FileManager.default.removeItem(at: staged)
                    activeBakeCacheKey = nil
                    activeBakeIndex = nil
                    continue
                }
                #if DEBUG
                beforePublishing?(job.cacheKey, index)
                #endif
                guard stillWants(job.cacheKey, index, hash), coordinator.renderTarget == target,
                      cache.isUsableAudioFile(staged) else {
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
                    engineID: target.engineID,
                    voiceID: target.cacheVoice,
                    textHash: hash,
                    chunkDurations: chunks.count > 1 ? stitched.chunkDurations : nil
                )
                coordinator.noteBakeMarksChanged()
                if job.isEphemeral {
                    cache.markEphemeral(cacheKey: job.cacheKey, lastAccess: Date())
                }
                if !liveChunkParagraphs.contains(ParagraphKey(cacheKey: job.cacheKey, index: index)) {
                    try? FileManager.default.removeItem(
                        at: cache.chunkDirectory(articleID: job.cacheKey, paragraphIndex: index, textHash: hash,
                                                 voice: target.cacheVoice))
                }
                resumeChunkWaitersWithParagraph(cacheKey: job.cacheKey, index: index)
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
                stopReason = "cancelled"
                return
            } catch LocalSynthError.deferredInBackground {
                // Went to background mid-paragraph: finished chunks stay on disk; not a failure.
                failAllLiveWaiters(LocalSynthError.deferredInBackground)
                lastBakeEvent = "background: \(coordinator.synthRenderer.engineShortName) paused at "
                    + "\(job.cacheKey.uuidString.prefix(8)) p\(index)"
                ListenTimingLog.log("synth_queue_parked", ["phase": runState.phase.rawValue, "p": index])
                stopReason = "deferred"
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
    }

    /// What a listener waiting on a chunk gets while no engine is loaded: the player speaks it
    /// with Apple.
    private static let noEngine = LocalSynthError.engineUnavailable("No on-device voice is loaded.")

    /// The worker stopped before a chunk (`RenderAdmission` said not now). Returns the reason
    /// (a background burst's stop line).
    private func noteParked(phase: AppRunState.Phase, engine: String, playing: Bool) -> String {
        switch phase {
        case .background where rendersInBackground && playing:
            // CPU route, between bursts: enough of the playing article is ready ahead.
            let ahead = readyAhead()
            lastBakeEvent = "background: \(Int(ahead / 60)) min ready ahead (renders again below the low-water mark)"
            ListenTimingLog.log("synth_queue_parked", ["phase": phase.rawValue, "reason": "ready_ahead",
                                                       "ready_ahead_s": Int(ahead)])
            return "ready_ahead"
        case .background where rendersInBackground:
            // CPU route: the listener's chunks and the playing article render; other articles
            // wait for the foreground (battery).
            lastBakeEvent = "background: holding bake of other articles"
            ListenTimingLog.log("synth_queue_parked", ["phase": phase.rawValue, "reason": "not_playing_article"])
            return "not_playing_article"
        case .background:
            lastBakeEvent = "background: \(engine) paused (bake resumes in foreground)"
            ListenTimingLog.log("synth_queue_parked", ["phase": phase.rawValue])
            return "background"
        case .inactive, .active:
            // Inactive: bake-ahead resumes on becoming active (or when a listener waits).
            ListenTimingLog.log("synth_queue_parked", ["phase": phase.rawValue])
            return phase.rawValue
        }
    }

    /// Engine first (recursive re-split inside the renderer); Apple TTS for this chunk if the engine
    /// still fails, in the voice the listen player falls back to for this article. Throws only
    /// when both fail. Writes nothing when the engine fails because `target` went away or changed
    /// during the call (the next step renders it for what renders now, or parks).
    private func renderChunk(
        job: ArticleJob, index: Int, chunk: Int, of count: Int, text: String, next: String? = nil,
        to url: URL, for target: RenderTarget, priority: RenderPriority
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
            guard coordinator.renderTarget == target else { return }
            if admission(isLiveRequest: hasLiveWaiters, cacheKey: job.cacheKey) != .render {
                throw LocalSynthError.deferredInBackground
            }
            let localError = error.localizedDescription
            let msg = "\(engine.engineShortName) FAIL p\(index) c\(chunk) → Apple TTS: \(localError)"
            ListenDebugLog.shared.append(msg)
            lastBakeEvent = msg
            let voice = coordinator.appleFallbackVoice(for: job.paragraphs)
            let duration = try await engine.renderAppleFallback(text: text, destination: url, voiceID: voice)
            ListenTimingLog.log("fallback_apple", ctx.merging([
                "chars": text.count, "ms": ListenTimingLog.ms(since: t0),
                "audio_s": (duration * 100).rounded() / 100, "engine": engine.engineShortName, "local_err": localError,
            ]) { a, _ in a })
        }
    }

    /// Next missing unit: from the front job's plan; a front job with nothing left is done and
    /// leaves. A staged chapter at its cap steps aside for the job behind it; one whose playing
    /// chapter's job left first is moved to the front (`placeStaged`). The playing chapter's
    /// paragraphs above its playhead (the plan's fill from the top) come after the staged
    /// chapter's opening: listening reaches the next chapter before it comes back to them. In the
    /// background on a route that renders there, a job steps aside once only those are left:
    /// listening doesn't need them, and a burst rendering them would never reach the high-water
    /// mark. They render in front.
    private func nextWorkUnit(in target: RenderTarget) -> (ArticleJob, Int)? {
        placeStaged()
        let aheadOnly = runState.phase == .background && rendersInBackground
        var position = 0
        while position < stack.count {
            let key = stack[position]
            guard let job = jobs[key] else {
                stack.remove(at: position)
                continue
            }
            let missing = missingParagraphs(of: job, in: target)
            let work = remainingWork(of: job, missing: missing)
            let cap = staged?.cacheKey == key ? staged?.cap : nil
            if let index = job.renderable(work, cap: cap, aheadOnly: aheadOnly).first {
                if index < job.plan.priorityStart, staged?.behind == key, let opening = stagedOpening(in: target) {
                    return opening
                }
                return (job, index)
            }
            if !work.isEmpty {
                position += 1
                continue
            }
            // Fully baked: off the queue, and try the next.
            finishJob(job, in: target)
            jobs[key] = nil
            stack.remove(at: position)
            if staged?.cacheKey == key { staged = nil }
            print("[SynthQueue] complete key=\(job.cacheKey.uuidString.prefix(8))")
        }
        return nil
    }

    /// `job`'s missing paragraphs in its plan's order, without those that failed.
    private func remainingWork(of job: ArticleJob, missing: [Int]) -> [Int] {
        job.plan.orderedWork(missing: missing).filter { idx in
            guard job.paragraphHashes.indices.contains(idx) else { return false }
            return !failedUnits.contains(failedID(job.cacheKey, idx, job.paragraphHashes[idx]))
        }
    }

    /// The staged chapter's next paragraph under its cap (nil: its opening is rendered).
    private func stagedOpening(in target: RenderTarget) -> (ArticleJob, Int)? {
        guard let staged, let job = jobs[staged.cacheKey] else { return nil }
        let work = remainingWork(of: job, missing: missingParagraphs(of: job, in: target))
        return job.renderable(work, cap: staged.cap, aheadOnly: false).first.map { (job, $0) }
    }

    /// Article done: drop its persisted pending job; if no paragraph needs audio in the target's
    /// voice any more, delete any leftover units of an older voice/engine (one voice per article).
    private func finishJob(_ job: ArticleJob, in target: RenderTarget) {
        guard let coordinator else { return }
        let freed = coordinator.audioCache.finalizeVoiceSwitch(
            articleID: job.cacheKey, paragraphs: job.paragraphs,
            engineID: target.engineID, voiceID: target.cacheVoice, plans: coordinator.chunkPlans)
        if freed > 0 {
            ListenDebugLog.shared.append(
                "voice switch done \(job.cacheKey.uuidString.prefix(8)): old-voice audio removed (\(FileSizes.label(freed)))")
            coordinator.noteBakeMarksChanged()
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
    private func resumeChunkWaitersWithParagraph(cacheKey: UUID, index: Int) {
        let keys = chunkWaiters.keys.filter { $0.cacheKey == cacheKey && $0.index == index }
        for key in keys {
            let conts = chunkWaiters.removeValue(forKey: key) ?? []
            guard let resolution = paragraphResolution(cacheKey: cacheKey, index: index, chunk: key.chunk)
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
