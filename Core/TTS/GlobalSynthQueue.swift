import Foundation

/// Single global synth work queue for all Listen audio.
///
/// Actions **reorganize** this queue — they do not spawn separate bake systems.
///
/// Priority rules:
/// 1. `enqueue(at: .front)` — that article becomes #1; synthesize from its start (or resume)
///    downward, then the paragraphs above. `.back` queues it behind what is there.
/// 2. `focusPlayhead` — same article stays #1; cursor moves to paragraph→end, then gap-fill top.
/// 3. Opening a different article demotes the previous #1 (cache kept); worker switches to new #1.
/// 4. Each lane drains the next missing unit the policy gives it, then asks again.
/// 5. `stageNext` — the next chapter of the book or series playing sits right behind the playing
///    chapter's job (at the front once that job is done) and renders its first paragraphs before
///    any other work, the playing chapter's paragraphs above its playhead included.
///
/// Work granularity is a **synth chunk** (`TextChunker`, sized by the engine's limits), not a whole
/// paragraph: the worker re-evaluates priority after every chunk (so a playhead request waits
/// at most one chunk, not one 30 s paragraph), and a listening producer can play chunk 0 of the
/// playhead paragraph while chunks 1… render (`ensureChunk`). A paragraph is Ready (bake mark,
/// `p-NNNN.caf`) only once all its chunks are rendered and stitched.
///
/// Never silently skip: a chunk the engine cannot render (after recursive re-split in
/// `LocalChunkRenderer`) marks its paragraph failed (no hot retry loop) and its waiters get the
/// error; the listen player pauses there. Nothing else renders it.
///
/// Saved vs unsaved only changes the persistence key (`cacheKey`), not queue behavior.
///
/// What renders next is the render policy's (`RenderPolicy`, `SingleCallPolicy` in the app): the
/// queue offers every job's next unit per demand, in its order (`candidates()`: a listener's
/// waited unit, the playing article ahead of its playhead, the staged chapter's opening, each
/// other job's next unit; never a paragraph rendering on a lane), the policy plans an action for
/// each free lane it uses (a call on a route, with threads and QoS; a route's load), and the
/// queue checks the plan (`RenderPlan.violation`) before it starts them
/// (`GlobalSynthQueue+Render.swift`). Each lane runs one call or load at a time, and the queue asks
/// again whenever one ends. `SingleCallPolicy` uses the CPU lane alone, in front and in the
/// background (there only while audio plays); `LanePolicy` adds the Neural Engine lane in front.
///
/// What it renders an article in is the context's `renderTarget(for:)`: the article's own engine
/// and voice, whatever is loaded. Jobs carry no voice; every readiness check, chunk file and
/// publish uses the target read at that step, so a voice switch can't file one voice's audio
/// under another.
///
/// The queue is the only owner of engine loads: it loads the route the policy names (`load`), on
/// that route's lane, for the policy's unit or, with nothing to render, for the engine it was
/// asked to `preload`. Each lane has its own resident host (`RenderSituation.lanes`). Hosts are
/// dropped while their lane is free (`dropHost`), never under a call.
///
/// Depends only on `SynthQueueContext` (cache, render target, chunk limits, renderer), never on a
/// concrete engine — the app passes `LocalTTSCoordinator`, tests pass a fake.
@MainActor
final class GlobalSynthQueue {
    // Stored state is the queue's own; members without `private` are read by its render file.
    weak var coordinator: SynthQueueContext?
    var jobs: [UUID: ArticleJob] = [:]
    /// Ordered stack: `stack[0]` is current #1.
    var stack: [UUID] = []
    /// The next chapter of the book or series playing, rendering its opening ahead (`stageNext`).
    private var staged: StagedJob?
    /// What runs on each lane: one call or one load at a time (`GlobalSynthQueue+Render.swift`).
    var laneWork: [Lane: LaneWork] = [:]
    /// A plan is due (`kickWorker`); many kicks in one turn make one.
    var pumpScheduled = false
    var chunkWaiters: [ChunkKey: [CheckedContinuation<ChunkResolution, Error>]] = [:]
    /// A Play's first paragraph, a listener's from the Play until its producer asks for the chunk
    /// (`expectListener`): the worker, woken by the Play, runs before the producer's request.
    private var expectedListener: ParagraphKey?
    /// Paragraphs whose chunk files a live player may reference — keep their scratch after
    /// stitching (cleaned on next open / launch). Pure bake-ahead paragraphs drop scratch at once.
    var liveChunkParagraphs: Set<ParagraphKey> = []
    /// (key|index|textHash) that failed the engine — skipped by the worker so a
    /// bad unit cannot spin forever. A live request for the unit clears its mark (fresh try).
    var failedUnits: Set<String> = []
    /// Routes whose load failed or was cancelled (ids): they aren't offered, and a job whose
    /// engine's CPU route is among them waits rather than load again and again, until a listener
    /// asks, a voice changes or the host is dropped (fresh try).
    var failedLoads: Set<String> = []
    /// To load once nothing is left to render (`preload`); work picked first cancels it.
    var preloadEngineID: String?
    /// Per lane, the engines whose host there goes once the work in flight on it ends
    /// (`dropHost`): the host it ran on, not one a later load builds.
    var hostDrops: [Lane: Set<String>] = [:]

    /// The app's phase (the policy's threads, and calls in the background only while audio plays).
    var runState: AppRunState = .shared {
        didSet { observeRunState() }
    }
    private var runStateObserver: NSObjectProtocol?
    #if canImport(UIKit)
    /// Lets a call in flight (and its CAF write) finish when the app leaves the foreground, and
    /// covers each call made in the background.
    lazy var drainGrace = BackgroundGrace(name: "ReaderSynthDrain")
    #endif
    /// Thermal state / Low Power Mode (injectable for tests).
    var bakeConditions: () -> BakeConditions = { .current }
    let backgroundWindow = BackgroundRenderWindow()
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

    private func observeRunState() {
        if let runStateObserver { NotificationCenter.default.removeObserver(runStateObserver) }
        runStateObserver = NotificationCenter.default.addObserver(
            forName: AppRunState.didChange, object: runState, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.runStateChanged() }
        }
    }

    /// App moved between active / inactive / background: a call in flight as it leaves finishes
    /// under the drain grace, and the policy is asked again (its threads and background rule
    /// read the phase).
    func runStateChanged() {
        let phase = runState.phase
        ListenTimingLog.log("synth_queue_phase", [
            "phase": phase.rawValue, "worker_busy": isWorkerRunning,
            "lanes": laneWork.keys.map(\.rawValue).sorted().joined(separator: ","),
        ])
        backgroundWindow.phaseChanged(to: phase)
        #if canImport(UIKit)
        if isWorkerRunning, phase == .background { drainGrace.begin() }
        #endif
        if !stack.isEmpty { kickWorker() }
    }

    /// Playback started or resumed: in the background calls start again only now.
    func playbackResumed() {
        if !stack.isEmpty { kickWorker() }
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
        /// Last, or where it already is (a save, a prepare, work adopted from disk).
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
    /// may have to wait. Its opening (`Demand.staged`) renders before them and before the
    /// playing chapter's paragraphs above its playhead, at bake-ahead priority, and only its first
    /// `cap` paragraphs until it becomes #1 (it plays), when the cap lifts. At its cap it steps aside, so jobs behind it keep running. A later stage
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
    /// chapter's job is done it moves to the front.
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
        coordinator?.noteBakeMarksChanged(of: staged.cacheKey)
    }

    var stagedCacheKey: UUID? { staged?.cacheKey }

    /// Drop an article from the queue (delete / clear audio). Does not delete disk files.
    func remove(cacheKey: UUID) {
        jobs[cacheKey] = nil
        stack.removeAll { $0 == cacheKey }
        if staged?.cacheKey == cacheKey { staged = nil }
        failWaiters(cacheKey: cacheKey, error: CancellationError())
        coordinator?.noteBakeMarksChanged(of: cacheKey)
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
        if expectedListener?.cacheKey == oldKey { expectedListener?.cacheKey = newKey }
        for key in chunkWaiters.keys.filter({ $0.cacheKey == oldKey }) {
            let conts = chunkWaiters.removeValue(forKey: key) ?? []
            chunkWaiters[ChunkKey(cacheKey: newKey, index: key.index, chunk: key.chunk), default: []]
                .append(contentsOf: conts)
        }
        kickWorker()
    }

    // MARK: - Chunk-level live ensure (play-while-building)

    /// Synth chunks of a paragraph's text for `engineID`, the article's engine (`ChunkPlans`):
    /// what the listen player plays chunk by chunk.
    func chunkTexts(for text: String, engineID: String) -> [String] {
        guard let coordinator else { return [] }
        return coordinator.chunkPlans.chunks(for: text, engineID: engineID) ?? []
    }

    /// An article's render target changed (its voice, or the default an unvoiced one takes):
    /// failure marks were the old target's, and the worker renders what is queued in the new
    /// voice, loading its engine. Nothing else is retargeted: jobs carry no voice, and a job's
    /// missing paragraphs are worked out again for the new target. Paragraph CAFs are keyed by
    /// engine+voice in `index.json`: old-voice ones never count as ready. Chunk scratch is filed
    /// by voice and stays (the launch clears it).
    func renderTargetChanged() {
        failedUnits.removeAll()
        failedLoads.removeAll()
        guard !stack.isEmpty else { return }
        kickWorker()
    }

    /// A Play starts at `paragraph` of `cacheKey`, not rendered: its producer asks for the chunk
    /// once its task runs (`ensureChunk`), after the worker the Play wakes. Called before the Play
    /// queues the article, so the worker's first pick, and the load it may start, is the
    /// listener's. Gone once the producer asks, or the paragraph renders, fails or leaves.
    func expectListener(cacheKey: UUID, paragraph: Int) {
        expectedListener = ParagraphKey(cacheKey: cacheKey, index: paragraph)
    }

    /// Load `engineID` once nothing is queued to render (the launch, with no saved work: the first
    /// Play then finds its engine loaded). Work picked before it cancels it.
    func preload(engineID: String) {
        preloadEngineID = engineID
        kickWorker()
    }

    /// Let `engineID`'s hosts go, on every lane (Retry, a thread setting change, a media services
    /// reset). A model call or load in flight finishes on its lane first; free lanes drop theirs
    /// now. The next work for the engine loads fresh hosts.
    func dropHost(engineID: String) {
        guard let coordinator else { return }
        for lane in Lane.allCases {
            switch laneWork[lane]?.work {
            case nil: coordinator.dropHost(on: lane, of: engineID)
            case .call(let route, _)?, .load(let route)?:
                if route.engine.rawValue == engineID { hostDrops[lane, default: []].insert(engineID) }
            }
        }
        if !hostDrops.values.contains(where: { $0.contains(engineID) }) {
            failedLoads.subtract(coordinator.routes(for: engineID).map(\.id))
        }
        applyHostDrops()
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
        isEphemeral: Bool
    ) async throws -> ChunkResolution {
        guard let coordinator else {
            throw NSError(domain: "GlobalSynthQueue", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Coordinator not attached"])
        }
        // C138a: the article's own engine and voice. A listener's chunk is demand: the worker
        // loads that engine for it first. Its load fails: the waiter is told, and the player
        // pauses there (C129, never another voice).
        guard let target = coordinator.lockedRenderTarget(for: cacheKey) else { throw Self.noEngine }
        let cache = coordinator.audioCache
        let hash = ArticleIdentity.paragraphHash(text)
        let unit = ParagraphKey(cacheKey: cacheKey, index: paragraphIndex)
        liveChunkParagraphs.insert(unit)
        // The producer asks for itself from now on (a waiter, or the chunk at once).
        if expectedListener?.cacheKey == cacheKey { expectedListener = nil }
        // A live request is a fresh try, of the unit and of its engine's load.
        failedUnits.remove(failedID(cacheKey, paragraphIndex, hash))
        failedLoads.subtract(coordinator.routes(for: target.engineID).map(\.id))

        let chunkURL = cache.chunkURL(articleID: cacheKey, paragraphIndex: paragraphIndex, textHash: hash,
                                      voice: target.cacheVoice, chunk: chunk)
        if cache.isUsableAudioFile(chunkURL) { return .chunk(chunkURL) }
        if let resolved = paragraphResolution(cacheKey: cacheKey, index: paragraphIndex, chunk: chunk) {
            return resolved
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
        let other = rendering.first { $0 != unit }
        let busyOther = other != nil
        let otherKey = other?.cacheKey
        let otherIndex = other?.index
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
        guard let coordinator, let target = coordinator.renderTarget(for: cacheKey) else { return false }
        let cache = coordinator.audioCache
        let url = cache.chunkURL(articleID: cacheKey, paragraphIndex: paragraphIndex,
                                 textHash: ArticleIdentity.paragraphHash(text), voice: target.cacheVoice, chunk: chunk)
        if cache.isUsableAudioFile(url) { return true }
        return paragraphResolution(cacheKey: cacheKey, index: paragraphIndex, chunk: chunk) != nil
    }

    /// The stitched paragraph in the render target's voice, at chunk `chunk`'s offset.
    func paragraphResolution(cacheKey: UUID, index: Int, chunk: Int) -> ChunkResolution? {
        guard let coordinator, let target = coordinator.renderTarget(for: cacheKey),
              let url = coordinator.audioCache.audioURL(
                articleID: cacheKey, paragraphIndex: index,
                engineID: target.engineID, voiceID: target.cacheVoice)
        else { return nil }
        guard chunk > 0 else { return .paragraph(url, startTime: 0) }
        let durations = coordinator.audioCache.entry(articleID: cacheKey, paragraphIndex: index)?.chunkDurations ?? []
        let offset = durations.prefix(chunk).reduce(0, +)
        return .paragraph(url, startTime: offset)
    }

    func failedID(_ key: UUID, _ index: Int, _ hash: String) -> String {
        "\(key.uuidString)|\(index)|\(hash)"
    }

    /// The queue still has `cacheKey` with the text of hash `hash` on paragraph `index`.
    func stillWants(_ cacheKey: UUID, _ index: Int, _ hash: String) -> Bool {
        guard let hashes = jobs[cacheKey]?.paragraphHashes, hashes.indices.contains(index) else { return false }
        return hashes[index] == hash
    }

    // MARK: - Diagnostics

    /// The paragraphs the lanes work on now (a call, or its engine's load for it), in lane order.
    var rendering: [ParagraphKey] { Lane.allCases.compactMap { laneWork[$0]?.unit } }
    /// The paragraphs a model call (or its stitch) runs on now: none is offered again meanwhile.
    var paragraphsInCalls: Set<ParagraphKey> {
        Set(laneWork.values.compactMap { if case .call = $0.work { $0.unit } else { nil } })
    }
    /// One-line last bake success/fail for the listen debug overlay.
    var lastBakeEvent: String = "—"

    var primaryCacheKey: UUID? { stack.first }
    /// Articles behind #1 (demoted / FIFO).
    var demotedCount: Int { max(0, stack.count - 1) }
    var isWorkerRunning: Bool { !laneWork.isEmpty }

    func pendingUnitCount(for cacheKey: UUID) -> Int {
        guard let target = coordinator?.renderTarget(for: cacheKey) else { return 0 }
        return missingParagraphs(of: cacheKey, in: target).count
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
        let key = cacheKey ?? stack.first
        guard let key, let job = jobs[key], let target = coordinator?.renderTarget(for: key) else { return nil }
        return job.plan.orderedWork(missing: missingParagraphs(of: key, in: target)).first
    }

    // MARK: - Private

    /// Paragraphs of `cacheKey`'s job that still need audio in the target's voice: the job's kept
    /// list (`ArticleJob.missing`), worked out again (`ArticleAudioCache.missingParagraphs`) only
    /// when its text, its target or its article's audio changed since. Not per chunk.
    func missingParagraphs(of cacheKey: UUID, in target: RenderTarget) -> [Int] {
        guard let coordinator else { return [] }
        let cache = coordinator.audioCache
        return jobs[cacheKey]?.missing(in: target, changes: cache.indexChanges(of: cacheKey)) {
            cache.missingParagraphs(articleID: cacheKey, paragraphs: $0, engineID: target.engineID,
                                    voiceID: target.cacheVoice, plans: coordinator.chunkPlans)
        } ?? []
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

    /// The engine stopped repeatedly (C129): nothing renders until Retry.
    var isPausedForRetry = false {
        didSet { if !isPausedForRetry { kickWorker() } }
    }

    /// What a listener waiting on a chunk gets when no registered engine speaks the article's voice.
    static let noEngine = LocalSynthError.engineUnavailable("No on-device voice speaks this article.")

    /// A unit offered to the policy: a paragraph of a job, the target it renders in, why, and the
    /// routes it may render on (its engine's, less those whose load failed).
    struct Unit {
        var job: ArticleJob
        var index: Int
        var target: RenderTarget
        var demand: Demand
        var routes: [RenderRoute]
    }

    /// The units offered to the policy, in the queue's order, each job's next per demand: a
    /// paragraph a listener waits on, or a Play is about to (`listener`); the article playing's
    /// next paragraph from its playhead (`playing`) and its next above it (`queued`); the staged
    /// chapter's next paragraph under its cap (`staged`, none at its cap: it steps aside); every
    /// other job's next paragraph in its plan's order (`queued`). Which goes first is the
    /// policy's. Read from each job's kept missing list (`missingParagraphs`), not the cache. A
    /// paragraph rendering on a lane isn't offered, and still counts as its job's work. A job with
    /// nothing left is done and leaves; one whose engine's CPU route (every engine's fallback lane)
    /// failed to load offers nothing until a fresh try.
    func candidates() -> [Unit] {
        placeStaged()
        guard let coordinator else { return [] }
        resolveReadyWaiters()
        let playing = coordinator.playingCacheKey
        var waited: [UUID: Set<Int>] = [:]
        for key in chunkWaiters.keys { waited[key.cacheKey, default: []].insert(key.index) }
        if let expectedListener { waited[expectedListener.cacheKey, default: []].insert(expectedListener.index) }
        let inFlight = paragraphsInCalls
        var units: [Unit] = []
        var position = 0
        while position < stack.count {
            let key = stack[position]
            guard let job = jobs[key] else {
                stack.remove(at: position)
                continue
            }
            let isStaged = staged?.cacheKey == key
            // C138a: its own target, loaded or not.
            guard let target = coordinator.renderTarget(for: key) else {
                position += 1
                continue
            }
            let routes = coordinator.routes(for: target.engineID).filter { !failedLoads.contains($0.id) }
            guard routes.contains(where: { $0.lane == .cpu }) else {
                position += 1
                continue
            }
            let missing = missingParagraphs(of: key, in: target) // ascending
            // A paragraph that failed isn't work until a fresh try.
            let usable = { (idx: Int) -> Bool in
                job.paragraphHashes.indices.contains(idx)
                    && (self.failedUnits.isEmpty || !self.failedUnits.contains(self.failedID(key, idx, job.paragraphHashes[idx])))
            }
            guard missing.contains(where: usable) else {
                // Fully baked: off the queue, and on to the next.
                coordinator.bakeCompleted(cacheKey: key) // its persisted pending job goes
                jobs[key] = nil
                stack.remove(at: position)
                if isStaged { staged = nil }
                ListenDebugLog.shared.append("bake complete \(job.cacheKey.uuidString.prefix(8))")
                continue
            }
            position += 1
            func offer(_ index: Int, _ demand: Demand) {
                units.append(Unit(job: job, index: index, target: target, demand: demand, routes: routes))
            }
            let free = { (idx: Int) -> Bool in inFlight.isEmpty || !inFlight.contains(ParagraphKey(cacheKey: key, index: idx)) }
            let listened = waited[key] ?? []
            for index in listened.sorted() where usable(index) && free(index) && missing.contains(index) { offer(index, .listener) }
            // The first missing paragraph in `range` no listener waits on. `missing` is ascending,
            // so the search starts at the range's first paragraph and stops at its end: a step
            // costs each job's front, not its whole remaining list.
            func next(in range: Range<Int>) -> Int? {
                guard !range.isEmpty else { return nil }
                var low = 0, high = missing.count
                while low < high {
                    let mid = (low + high) / 2
                    if missing[mid] < range.lowerBound { low = mid + 1 } else { high = mid }
                }
                for index in missing[low...] {
                    if index >= range.upperBound { return nil }
                    if !listened.contains(index) && usable(index) && free(index) { return index }
                }
                return nil
            }
            let start = job.plan.priorityStart
            if isStaged {
                let cap = staged?.cap ?? .max
                if let index = next(in: start..<max(start, cap)) ?? next(in: 0..<min(start, cap)) { offer(index, .staged) }
                continue
            }
            let ahead = next(in: start..<Int.max)
            if key == playing {
                if let ahead { offer(ahead, .playing) }
                if let above = next(in: 0..<start) { offer(above, .queued) }
            } else if let first = ahead ?? next(in: 0..<start) {
                offer(first, .queued)
            }
        }
        return units
    }

    /// A paragraph can turn ready without this queue rendering it (a voice's audio restored, the
    /// article's audio aligned with other text): its waiters get it here, before any job is judged
    /// done. Otherwise a job could leave the queue with its waiters still suspended, and a first
    /// Play, with no starve watch armed yet, would never start.
    private func resolveReadyWaiters() {
        var waited = Set(chunkWaiters.keys.map { ParagraphKey(cacheKey: $0.cacheKey, index: $0.index) })
        if let expectedListener { waited.insert(expectedListener) }
        for key in waited where paragraphResolution(cacheKey: key.cacheKey, index: key.index, chunk: 0) != nil {
            resumeChunkWaitersWithParagraph(cacheKey: key.cacheKey, index: key.index)
        }
    }

    func resumeChunkWaiters(cacheKey: UUID, index: Int, chunk: Int, url: URL) {
        let key = ChunkKey(cacheKey: cacheKey, index: index, chunk: chunk)
        let conts = chunkWaiters.removeValue(forKey: key) ?? []
        for cont in conts { cont.resume(returning: .chunk(url)) }
    }

    /// Paragraph finished: any chunk waiter of it gets the stitched paragraph at that chunk's
    /// offset. One whose paragraph can't be found in what renders now is failed (the producer
    /// asks again), never dropped: a dropped continuation would hang its producer for good.
    func resumeChunkWaitersWithParagraph(cacheKey: UUID, index: Int) {
        if expectedListener == ParagraphKey(cacheKey: cacheKey, index: index) { expectedListener = nil }
        let keys = chunkWaiters.keys.filter { $0.cacheKey == cacheKey && $0.index == index }
        for key in keys {
            let conts = chunkWaiters.removeValue(forKey: key) ?? []
            let resolution = paragraphResolution(cacheKey: cacheKey, index: index, chunk: key.chunk)
            for cont in conts {
                if let resolution { cont.resume(returning: resolution) } else { cont.resume(throwing: CancellationError()) }
            }
        }
    }

    func failWaiters(cacheKey: UUID, index: Int, error: Error) {
        if expectedListener == ParagraphKey(cacheKey: cacheKey, index: index) { expectedListener = nil }
        let chunkKeys = chunkWaiters.keys.filter { $0.cacheKey == cacheKey && $0.index == index }
        for ck in chunkKeys {
            for cont in chunkWaiters.removeValue(forKey: ck) ?? [] { cont.resume(throwing: error) }
        }
    }

    func failWaiters(cacheKey: UUID, error: Error) {
        if expectedListener?.cacheKey == cacheKey { expectedListener = nil }
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
