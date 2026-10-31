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
/// 4. One worker drains #1’s next missing unit, then continues.
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
/// other job's next unit), the policy plans one action (a call on a route, with threads and QoS;
/// a route's load; a hold; nothing), and the queue checks it (`RenderPlan.violation`) before it
/// acts. The same in front and in the background: every route runs on the CPU, one call at a
/// time; in the background only while audio plays.
///
/// What it renders an article in is the context's `renderTarget(for:)`: the article's own engine
/// and voice, whatever is loaded. Jobs carry no voice; every readiness check, chunk file and
/// publish uses the target read at that step, so a voice switch can't file one voice's audio
/// under another.
///
/// The worker is the only owner of engine loads: it loads the route the policy names (`load`),
/// for the policy's unit or, with nothing to render, for the engine it was asked to `preload`.
/// The resident route is the lane's (`RenderSituation.lanes`). Hosts are dropped between calls
/// (`dropHost`), never under one.
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
    /// A Play's first paragraph, a listener's from the Play until its producer asks for the chunk
    /// (`expectListener`): the worker, woken by the Play, runs before the producer's request.
    private var expectedListener: ParagraphKey?
    /// Paragraphs whose chunk files a live player may reference — keep their scratch after
    /// stitching (cleaned on next open / launch). Pure bake-ahead paragraphs drop scratch at once.
    private var liveChunkParagraphs: Set<ParagraphKey> = []
    /// (key|index|textHash) that failed the engine — skipped by the worker so a
    /// bad unit cannot spin forever. A live request for the unit clears its mark (fresh try).
    private var failedUnits: Set<String> = []
    /// Engines whose load failed or was cancelled: their jobs wait rather than load again and
    /// again, until a listener asks, a voice changes or the host is dropped (fresh try).
    private var loadFailures: Set<String> = []
    /// To load once nothing is left to render (`preload`); work picked first cancels it.
    private var preloadEngineID: String?
    /// Engines whose host goes before the worker's next call (`dropHost`).
    private var hostDrops: Set<String> = []

    /// The app's phase (the policy's threads, and calls in the background only while audio plays).
    var runState: AppRunState = .shared {
        didSet { observeRunState() }
    }
    private var runStateObserver: NSObjectProtocol?
    #if canImport(UIKit)
    /// Lets a call in flight (and its CAF write) finish when the app leaves the foreground, and
    /// covers each call made in the background.
    private lazy var drainGrace = BackgroundGrace(name: "ReaderSynthDrain")
    #endif
    /// Thermal state / Low Power Mode (injectable for tests).
    var bakeConditions: () -> BakeConditions = { .current }
    /// Model calls in flight, per lane (`RenderSituation.lanes`).
    private var callsInFlight: [Lane: Int] = [:]
    /// The most calls in flight across lanes: one while `SingleCallPolicy` is the only policy.
    static let maxCallsInFlight = 1
    private let backgroundWindow = BackgroundRenderWindow()
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
            "phase": phase.rawValue, "worker_busy": worker != nil,
            "active_key": ListenTimingLog.shortKey(activeBakeCacheKey), "active_p": activeBakeIndex ?? -1,
        ])
        backgroundWindow.phaseChanged(to: phase)
        #if canImport(UIKit)
        if worker != nil, phase == .background { drainGrace.begin() }
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
        loadFailures.removeAll()
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

    /// Let `engineID`'s host go (Retry, a thread setting change, a media services reset). A model
    /// call in flight finishes on it first: the worker drops it between calls, or now when idle.
    /// The next work for the engine loads a fresh host.
    func dropHost(engineID: String) {
        hostDrops.insert(engineID)
        if worker == nil { applyHostDrops() }
        if !stack.isEmpty { kickWorker() }
    }

    /// Clears each engine's failed-load mark here, not when the drop is asked for: a load in
    /// flight then may still fail and mark it, and the rebuild must still get its fresh try.
    private func applyHostDrops() {
        guard let coordinator, !hostDrops.isEmpty else { return }
        for engineID in hostDrops { coordinator.dropHost(engineID) }
        loadFailures.subtract(hostDrops)
        hostDrops.removeAll()
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
        loadFailures.remove(target.engineID)

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
        guard let coordinator, let target = coordinator.renderTarget(for: cacheKey) else { return false }
        let cache = coordinator.audioCache
        let url = cache.chunkURL(articleID: cacheKey, paragraphIndex: paragraphIndex,
                                 textHash: ArticleIdentity.paragraphHash(text), voice: target.cacheVoice, chunk: chunk)
        if cache.isUsableAudioFile(url) { return true }
        return paragraphResolution(cacheKey: cacheKey, index: paragraphIndex, chunk: chunk) != nil
    }

    /// The stitched paragraph in the render target's voice, at chunk `chunk`'s offset.
    private func paragraphResolution(cacheKey: UUID, index: Int, chunk: Int) -> ChunkResolution? {
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
    private func missingParagraphs(of cacheKey: UUID, in target: RenderTarget) -> [Int] {
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

    private func kickWorker() {
        guard worker == nil, !isPausedForProbe, !isHeldForLaunch, !isPausedForRetry else { return }
        worker = Task { [weak self] in
            await self?.drain()
        }
    }

    private func drain() async {
        defer {
            worker = nil
            #if canImport(UIKit)
            drainGrace.end()
            #endif
        }
        while !isPausedForProbe, !isHeldForLaunch, !isPausedForRetry {
            guard await renderStep() else { return }
        }
    }

    /// One step of the worker: drop the hosts asked for, offer the candidates to the policy,
    /// check its plan, then load the route it names or run its call (`renderOrStitch`). Returns
    /// false when the plan has nothing to do: the worker stops until an event kicks it.
    private func renderStep() async -> Bool {
        guard let coordinator else { return false }
        applyHostDrops()
        let (offered, situation) = self.situation(coordinator)
        if !offered.isEmpty { preloadEngineID = nil }
        let plan = coordinator.renderPolicy.plan(situation)
        if let violation = plan.violation(of: situation) {
            assertionFailure("Render policy \(coordinator.renderPolicy.name): \(violation)")
            ListenTimingLog.log("render_plan_refused", ["policy": coordinator.renderPolicy.name, "why": violation])
            return false
        }
        switch plan {
        case .load(let load):
            let unit = load.candidate.map { offered[$0] }
            if unit == nil { preloadEngineID = nil }
            // Working on this unit (the player's starve watch reads it) from its engine's load on.
            activeBakeCacheKey = unit?.job.cacheKey
            activeBakeIndex = unit?.index
            defer {
                activeBakeCacheKey = nil
                activeBakeIndex = nil
            }
            let reason = unit == nil ? "preload" : load.priority == .listener ? "listener" : "work"
            await self.load(load.route, reason: reason, priority: load.priority)
            return true // the queue may have moved during the load: pick again
        case .start(let start):
            return await run(start, of: offered[start.candidate], coordinator)
        case .held(let hold):
            lastBakeEvent = "held: \(hold.label) (resumes when it clears)"
            ListenTimingLog.log("synth_queue_parked", ["phase": runState.phase.rawValue, "reason": hold.label])
            return false
        case .idle:
            if !offered.isEmpty {
                let reason = situation.phase == .background && !situation.audioPlaying ? "no_audio_playing" : "idle"
                ListenTimingLog.log("synth_queue_parked", ["phase": runState.phase.rawValue, "reason": reason])
            }
            return false
        }
    }

    /// Runs the policy's call on `unit`; false when the worker stops (cancelled, or the unit has
    /// no voice any more).
    private func run(_ start: RenderPlan.Start, of unit: Unit, _ coordinator: SynthQueueContext) async -> Bool {
        let (job, index) = (unit.job, unit.index)
        // C138a: the article's own selection, locked by its first render. Never another voice.
        guard let target = coordinator.lockedRenderTarget(for: job.cacheKey) else { return false }
        guard target == unit.target else { return true } // its voice changed since the pick: pick again
        if coordinator.audioCache.audioURL(articleID: job.cacheKey, paragraphIndex: index,
                                           engineID: target.engineID, voiceID: target.cacheVoice) != nil {
            jobs[job.cacheKey]?.missing?.paragraphs.removeAll { $0 == index }
            resumeChunkWaitersWithParagraph(cacheKey: job.cacheKey, index: index)
            return true
        }
        guard job.paragraphs.indices.contains(index) else { return true }
        activeBakeCacheKey = job.cacheKey
        activeBakeIndex = index
        defer {
            activeBakeCacheKey = nil
            activeBakeIndex = nil
        }
        #if canImport(UIKit)
        // The call in flight at backgrounding is done; in the background each call runs under the
        // grace, so iOS suspending the app doesn't cut one short.
        if runState.phase == .background { drainGrace.begin() } else { drainGrace.end() }
        #endif
        do {
            try Task.checkCancellation()
            try await renderOrStitch(job, paragraph: index, in: target, start: start)
        } catch is CancellationError {
            failWaiters(cacheKey: job.cacheKey, index: index, error: CancellationError())
            return false
        } catch {
            // The engine failed (or stitch/store failed). Don't hot-loop.
            failedUnits.insert(failedID(job.cacheKey, index, job.paragraphHashes[index]))
            let failMsg = "bake FAIL \(job.cacheKey.uuidString.prefix(8)) p\(index): \(error.localizedDescription)"
            lastBakeEvent = failMsg
            ListenDebugLog.shared.append(failMsg)
            ListenTimingLog.log("paragraph_failed", [
                "key": ListenTimingLog.shortKey(job.cacheKey), "p": index, "err": error.localizedDescription,
            ])
            failWaiters(cacheKey: job.cacheKey, index: index, error: error)
        }
        return true
    }

    /// What the policy decides from: the candidates (with the queue's units behind them, same
    /// indices), the phase, the hold, the lanes and the route resident on each.
    private func situation(_ coordinator: SynthQueueContext) -> ([Unit], RenderSituation) {
        let offered = candidates()
        let resident = coordinator.residentRoute
        var lanes: [Lane: LaneSnapshot] = [:]
        for lane in Lane.allCases {
            lanes[lane] = LaneSnapshot(callsInFlight: callsInFlight[lane, default: 0],
                                       resident: resident?.lane == lane ? resident : nil)
        }
        let situation = RenderSituation(
            phase: runState.phase, audioPlaying: coordinator.playingCacheKey != nil,
            hold: bakeConditions().bakeAheadHold, preload: preloadEngineID.map(coordinator.routes(for:)) ?? [],
            candidates: offered.map {
                RenderCandidate(item: $0.job.cacheKey, paragraph: $0.index, demand: $0.demand,
                                engine: SpeechEngineID(rawValue: $0.target.engineID),
                                routes: coordinator.routes(for: $0.target.engineID))
            },
            lanes: lanes, maxCallsInFlight: Self.maxCallsInFlight, cores: ProcessInfo.processInfo.activeProcessorCount)
        return (offered, situation)
    }

    /// Renders one chunk of the paragraph (one a listener waits for first, else the next in
    /// order), or, once every chunk is on disk, stitches them and publishes the paragraph. At most
    /// one model call, so the worker weighs priority again between chunks.
    private func renderOrStitch(_ job: ArticleJob, paragraph index: Int, in target: RenderTarget,
                                start: RenderPlan.Start) async throws {
        let priority = start.priority
        guard let coordinator else { throw CancellationError() }
        let cache = coordinator.audioCache
        let text = job.paragraphs[index]
        let hash = job.paragraphHashes[index]
        // Never empty: a paragraph with nothing to speak is never missing.
        let chunks = coordinator.chunkPlans.chunks(for: text, engineID: target.engineID) ?? []
        let chunkURLs = chunks.indices.map {
            cache.chunkURL(articleID: job.cacheKey, paragraphIndex: index, textHash: hash,
                           voice: target.cacheVoice, chunk: $0)
        }
        // A listener waiting on a later chunk (scrubbed to a sentence mid-paragraph) gets that
        // chunk first; otherwise chunks render in order.
        let waited = chunkWaiters.keys
            .filter { $0.cacheKey == job.cacheKey && $0.index == index }
            .map(\.chunk).sorted()
            .first { chunkURLs.indices.contains($0) && !cache.isUsableAudioFile(chunkURLs[$0]) }
        if let k = waited ?? chunkURLs.firstIndex(where: { !cache.isUsableAudioFile($0) }) {
            callsInFlight[start.route.lane, default: 0] += 1
            defer { callsInFlight[start.route.lane, default: 1] -= 1 }
            let audio = try await renderChunk(job: job, index: index, chunk: k, of: chunks.count,
                                              text: chunks[k], next: k + 1 < chunks.count ? chunks[k + 1] : nil,
                                              to: chunkURLs[k], for: target, start: start)
            backgroundWindow.noteChunk(route: start.route.id, audioSeconds: audio ?? 0)
            // The engine or voice changed during the call: the chunk is filed under its own
            // voice, and its waiters wait for the new voice's render.
            guard audio != nil, coordinator.renderTarget(for: job.cacheKey) == target else { return }
            resumeChunkWaiters(cacheKey: job.cacheKey, index: index, chunk: k, url: chunkURLs[k])
            guard chunkURLs.allSatisfy(cache.isUsableAudioFile) else { return }
        }
        // All chunks present → stitch them off the main actor (a read / convert / write of the
        // whole paragraph) into a file of their own, then publish it here only if the queue still
        // wants this text on this paragraph, in this voice. Meanwhile the article's audio may have
        // been aligned with other paragraphs (opening it with newer text, a merge) and its job
        // given them, the article left the queue (audio cleared, deleted, rekeyed), or the voice
        // changed: a render of the old paragraph or voice isn't filed on the new one.
        let stitching = cache.stitchingURL(articleID: job.cacheKey, paragraphIndex: index, textHash: hash,
                                           voice: target.cacheVoice)
        let stitched: ChunkAudioStitcher.Result
        do {
            stitched = try await Task.detached(priority: priority.taskPriority) {
                try ArticleAudioCache.stitchParagraph(chunkURLs, to: stitching)
            }.value
        } catch where !chunkURLs.allSatisfy(cache.isUsableAudioFile) {
            // The chunk scratch went away meanwhile (identity prep): not this paragraph's failure —
            // look again.
            try? FileManager.default.removeItem(at: stitching)
            return
        }
        guard stillWants(job.cacheKey, index, hash), coordinator.renderTarget(for: job.cacheKey) == target,
              cache.isUsableAudioFile(stitching) else {
            try? FileManager.default.removeItem(at: stitching)
            ListenTimingLog.log("paragraph_discarded", ["key": ListenTimingLog.shortKey(job.cacheKey), "p": index])
            return
        }
        let changesBefore = cache.indexChanges(of: job.cacheKey)
        try cache.publishParagraph(
            staged: stitching,
            articleID: job.cacheKey,
            paragraphIndex: index,
            duration: stitched.duration,
            engineID: target.engineID,
            voiceID: target.cacheVoice,
            textHash: hash,
            chunkDurations: chunks.count > 1 ? stitched.chunkDurations : nil
        )
        jobs[job.cacheKey]?.noteRendered(index, in: target, changes: changesBefore,
                                         after: cache.indexChanges(of: job.cacheKey))
        coordinator.noteBakeMarksChanged(of: job.cacheKey)
        if job.isEphemeral {
            do { try cache.markEphemeral(cacheKey: job.cacheKey, lastAccess: Date()) } catch {
                ListenDebugLog.shared.append("ephemeral mark failed \(job.cacheKey.uuidString.prefix(8)): \(error.localizedDescription)")
            }
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
    }

    /// What a listener waiting on a chunk gets when no registered engine speaks the article's voice.
    private static let noEngine = LocalSynthError.engineUnavailable("No on-device voice speaks this article.")

    /// Load a host for `route` (the worker's alone; see the type's notes). A load that fails or is
    /// cancelled fails the chunks listeners wait for in its engine, and its jobs wait (`loadFailures`).
    private func load(_ route: RenderRoute, reason: String, priority: RenderPriority) async {
        guard let coordinator else { return }
        let engineID = route.engine.rawValue
        let t0 = ListenTimingLog.now()
        ListenTimingLog.log("engine_load", ["engine": engineID, "route": route.id, "reason": reason, "op": "start",
                                            "qos": priority == .listener ? "userInitiated" : "utility",
                                            "replaces": coordinator.residentRoute?.id ?? "-"])
        do {
            try await coordinator.makeResident(route, priority: priority)
            ListenTimingLog.log("engine_load", ["engine": engineID, "reason": reason, "op": "ready",
                                                "ms": ListenTimingLog.ms(since: t0)])
        } catch {
            loadFailures.insert(engineID)
            lastBakeEvent = "\(engineID) didn’t load: \(error.localizedDescription)"
            ListenDebugLog.shared.append(lastBakeEvent)
            ListenTimingLog.log("engine_load", ["engine": engineID, "reason": reason, "op": "failed",
                                                "ms": ListenTimingLog.ms(since: t0), "err": error.localizedDescription])
            for key in Set(chunkWaiters.keys.map(\.cacheKey))
            where coordinator.renderTarget(for: key)?.engineID == engineID {
                failWaiters(cacheKey: key, error: error)
            }
        }
    }

    /// The engine renders the chunk (recursive re-split inside the renderer) on the start's route,
    /// at its threads and QoS; returns its audio's seconds, or throws when it fails. Returns nil,
    /// writing nothing, when the engine fails because `target` went away or changed during the
    /// call (the next step renders what renders now).
    private func renderChunk(
        job: ArticleJob, index: Int, chunk: Int, of count: Int, text: String, next: String? = nil,
        to url: URL, for target: RenderTarget, start: RenderPlan.Start
    ) async throws -> TimeInterval? {
        guard let coordinator else { throw CancellationError() }
        let engine = coordinator.synthRenderer
        let t0 = ListenTimingLog.now()
        let request = ChunkRenderRequest(
            article: job.cacheKey, paragraph: index, chunk: chunk, isLastInParagraph: chunk == count - 1,
            nextWord: next?.split(separator: " ").first.map(String.init), priority: start.priority,
            threads: start.threads, isPrimary: stack.first == job.cacheKey, voice: target.engineVoice)
        let ctx = request.logFields
        do {
            let duration = try await engine.renderChunkToFile(text: text, destination: url, engineID: target.engineID,
                                                              request: request)
            ListenTimingLog.log("chunk_ready", ctx.merging([
                "n": count, "chars": text.count, "ms": ListenTimingLog.ms(since: t0),
                "audio_s": (duration * 100).rounded() / 100, "engine": engine.engineShortName,
            ]) { a, _ in a })
            return duration
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard coordinator.renderTarget(for: job.cacheKey) == target else { return nil }
            // The unit fails; the player pauses there (C129: never another voice).
            let msg = "\(engine.engineShortName) FAIL p\(index) c\(chunk): \(error.localizedDescription)"
            ListenDebugLog.shared.append(msg)
            lastBakeEvent = msg
            throw error
        }
    }

    /// A unit offered to the policy: a paragraph of a job, the target it renders in, and why.
    private struct Unit {
        var job: ArticleJob
        var index: Int
        var target: RenderTarget
        var demand: Demand
    }

    /// The units offered to the policy, in the queue's order, each job's next per demand: a
    /// paragraph a listener waits on, or a Play is about to (`listener`); the article playing's
    /// next paragraph from its playhead (`playing`) and its next above it (`queued`); the staged
    /// chapter's next paragraph under its cap (`staged`, none at its cap: it steps aside); every
    /// other job's next paragraph in its plan's order (`queued`). Which goes first is the
    /// policy's. Read from each job's kept missing list (`missingParagraphs`), not the cache. A
    /// job with nothing left is done and leaves; one whose engine failed to load offers nothing
    /// until a fresh try.
    private func candidates() -> [Unit] {
        placeStaged()
        guard let coordinator else { return [] }
        let playing = coordinator.playingCacheKey
        var waited: [UUID: Set<Int>] = [:]
        for key in chunkWaiters.keys { waited[key.cacheKey, default: []].insert(key.index) }
        if let expectedListener { waited[expectedListener.cacheKey, default: []].insert(expectedListener.index) }
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
            guard let target = coordinator.renderTarget(for: key), !loadFailures.contains(target.engineID) else {
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
                units.append(Unit(job: job, index: index, target: target, demand: demand))
            }
            let listened = waited[key] ?? []
            for index in listened.sorted() where usable(index) && missing.contains(index) { offer(index, .listener) }
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
                    if !listened.contains(index) && usable(index) { return index }
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

    private func resumeChunkWaiters(cacheKey: UUID, index: Int, chunk: Int, url: URL) {
        let key = ChunkKey(cacheKey: cacheKey, index: index, chunk: chunk)
        let conts = chunkWaiters.removeValue(forKey: key) ?? []
        for cont in conts { cont.resume(returning: .chunk(url)) }
    }

    /// Paragraph finished: any chunk waiter of it gets the stitched paragraph at that chunk's
    /// offset. One whose paragraph can't be found in what renders now is failed (the producer
    /// asks again), never dropped: a dropped continuation would hang its producer for good.
    private func resumeChunkWaitersWithParagraph(cacheKey: UUID, index: Int) {
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

    private func failWaiters(cacheKey: UUID, index: Int, error: Error) {
        if expectedListener == ParagraphKey(cacheKey: cacheKey, index: index) { expectedListener = nil }
        let chunkKeys = chunkWaiters.keys.filter { $0.cacheKey == cacheKey && $0.index == index }
        for ck in chunkKeys {
            for cont in chunkWaiters.removeValue(forKey: ck) ?? [] { cont.resume(throwing: error) }
        }
    }

    private func failWaiters(cacheKey: UUID, error: Error) {
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
