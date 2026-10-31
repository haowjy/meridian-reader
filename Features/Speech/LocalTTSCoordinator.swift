import Foundation
import Observation

@MainActor
@Observable
final class LocalTTSCoordinator: SynthQueueContext {
    /// The settings it stores over `engines` (the default voice, and what the engines store), for
    /// `-resetLibrary` to clear before any coordinator is made.
    static func storedKeys(for engines: EngineRegistry) -> [String] {
        [defaultSelectionKey] + engines.storedKeys
    }

    /// Every engine + its capabilities. Injected from the composition root.
    let engines: EngineRegistry
    let audioCache: ArticleAudioCache
    /// Single global Core ML work queue — actions reshuffle; one worker drains #1.
    let synthQueue = GlobalSynthQueue()
    /// Engine selection, voices and launch-step flags (a suite in tests).
    let defaults: UserDefaults
    let crashGuard: EngineCrashGuard
    /// Saved and prepared articles' bake jobs, kept across launches until they are done.
    let pendingBakes: PendingBakeJobStore
    /// What was playing, written as it plays: launch reads it to resume after a crash.
    let resumePoints: ListenResumePointStore

    /// The on-device engine's model: lifecycle, host and renderer. The render queue renders through it.
    let synth: LocalSynthService
    /// Every chunk plan, by engine (the render queue, the player, alignment, readiness).
    let chunkPlans: ChunkPlans
    /// The listen player (set by `LocalListenEngine`): the render queue asks it which article is
    /// playing (listener priority, background bake scope).
    @ObservationIgnored weak var listenPlayer: LocalListenPlayer?
    /// Called when a bake job leaves the queue and when the render queue's state may have moved
    /// (audio rendered or deleted, the engine or voice changed). Often, and inside the queue's own
    /// work: the handler acts later, never re-entering the queue in the call. Set by the
    /// composition (Prepared audio, `AppComposition.makePrepared audio`).
    @ObservationIgnored var onRenderStateChange: (() -> Void)?
    /// Selected voice per multi-voice engine (e.g. Kokoro `af_heart`). Part of the cache voice key.
    private(set) var engineVoices: [SpeechEngineID: String] = [:]
    /// C129: the engine killed the last process inside a call (`CrashRecovery`); the render queue
    /// waits for Retry (`retryAfterEngineStop`) and playback pauses where rendered audio runs out.
    /// The engine and voice stay selected.
    private(set) var isPausedForRetry = false
    /// C138a: the stored selection of the article with `key` (or its book), in its stored form.
    @ObservationIgnored var articleSelection: (UUID) -> String? = { _ in nil }
    /// C138a: the article with `key` (or its book) takes the selection unless it has one; returns the one it has.
    @ObservationIgnored var lockArticleSelection: (UUID, String) -> String = { $1 }
    @ObservationIgnored var selectionMemo: [UUID: VoiceSelection?] = [:]
    /// The Settings default: the selection a brand-new article takes on first use. Nothing else.
    var defaultSelection: VoiceSelection
    /// C134: `key` has a prepare record (set by the composition from the prepare list).
    @ObservationIgnored var preparedKey: (UUID) -> Bool = { _ in false }
    /// C134: listening needs `key`'s audio now (set by the composition: session, staged chapter).
    @ObservationIgnored var listeningNeedsKey: (UUID) -> Bool = { _ in false }
    /// The crash this launch found (the engine killed the previous process inside a call).
    private(set) var launchCrash: EngineCrashGuard.CrashInfo?
    /// Article + paragraph to resume after a crash, handed to the UI once (`takePendingResume`);
    /// the library's moves remap it (`remapPendingResume`).
    var pendingResume: ListenResumeTarget?
    /// Bumped when CAF ready set changes — reading UI observes this for live bake marks.
    private(set) var bakeMarksRevision: UInt64 = 0
    /// Article the user most recently opened / listened to (stays #1 when pending jobs drain).
    private var focusCacheKey: UUID?
    /// From the start of the launch's audio-cache steps until the library's launch maintenance has
    /// finished (`holdRenderingForLaunch`, `endLaunchHold`).
    @ObservationIgnored private(set) var isHeldForLaunch = false
    /// Voice whose files are preparing after the user picked it (Settings shows a spinner).
    private(set) var voiceDownloadID: String?
    /// Last voice download failure (Settings footer); cleared on the next pick.
    private(set) var voiceDownloadError: String?
    /// Bumped when a Kokoro voice pack is installed or removed (Voice rows refresh swipe / ↓).
    private(set) var voicePacksRevision: UInt64 = 0
    private var voiceChoiceToken = 0

    /// Loads no engine: the render queue's worker loads the engine of the work it takes, and at the
    /// end of the launch's hold the default's (`endLaunchHold`). `selecting` is a Debug launch's
    /// `-selectEngine` (`LaunchOptions`): the default takes that engine's voice.
    /// One-time launch steps are `LaunchMigration`s, run by `AppComposition`, which builds the
    /// files and settings it works over (tests: `LibraryTestEnvironment`).
    init(
        engines: EngineRegistry,
        defaults: UserDefaults,
        audioCache: ArticleAudioCache,
        crashGuard: EngineCrashGuard,
        pendingBakes: PendingBakeJobStore,
        resumePoints: ListenResumePointStore,
        selecting launchEngine: SpeechEngineID? = nil
    ) {
        self.engines = engines
        self.defaults = defaults
        self.audioCache = audioCache
        self.crashGuard = crashGuard
        self.pendingBakes = pendingBakes
        self.resumePoints = resumePoints
        self.synth = LocalSynthService(engines: engines, crashGuard: crashGuard)
        self.chunkPlans = ChunkPlans { engines.descriptor(SpeechEngineID(rawValue: $0))?.onDevice.limits }
        self.defaultSelection = Self.builtInDefault(of: engines)
        for d in engines.descriptors where !d.voices.isEmpty {
            // Stored voice if still offered (curated list), else the engine default.
            engineVoices[d.id] = d.resolvedVoice(defaults.string(forKey: d.resolvedVoiceDefaultsKey))
        }
        synthQueue.attach(coordinator: self)
        synth.onStateChange = { [weak self] in self?.engineStateChanged() }
        loadDefaultSelection()
        if let launchEngine, engines.contains(launchEngine) {
            // A launch argument (tests, debug) sets the default to that engine's voice.
            defaultSelection = VoiceSelection(engine: launchEngine, voice: engineVoices[launchEngine] ?? "")
        }
        // What was playing, and when it was last recorded: a marker much older than that is
        // from a call the process outlived.
        let playing = resumePoints.load()
        launchCrash = crashGuard.consumeCrashInfo(lastActivity: playing?.at)
        if let launchCrash { recover(from: launchCrash, playing: playing) }
    }

    /// The previous process died inside `crash.engine`. Its provider decides (Kokoro: resume on the
    /// stable route first); by default the engine and voice stay and it pauses for Retry (C129:
    /// never another voice).
    private func recover(from crash: EngineCrashGuard.CrashInfo, playing: ListenResumeTarget?) {
        guard let engine = crash.engine else { return }
        let recovery = engines.recover(from: crash, playing: playing)
            ?? .pauseForRetry(resume: ListenResumeTarget.forCrash(article: crash.articleKey, paragraph: crash.paragraph,
                                                                  crashAt: crash.at, playing: playing))
        ListenDebugLog.shared.append("\(engines.shortName(engine)) crash detected → \(recovery)")
        pendingResume = recovery.resume
        if case .pauseForRetry = recovery {
            isPausedForRetry = true
            synthQueue.isPausedForRetry = true
        }
    }

    static var buildConfiguration: String {
        #if DEBUG
        return "debug"
        #else
        return "release"
        #endif
    }

    /// The engine loaded or loading, for logs ("—" when none).
    var engineLabel: String { activeLocalEngineID?.rawValue ?? "—" }

    /// Retry, or any play while paused for it (`SpeechController.userPerform`): the render queue
    /// drops the engine's host, and its next work loads a fresh one, same engine and voice; then
    /// rendering and prepared audio go on.
    func retryAfterEngineStop() {
        guard isPausedForRetry else { return }
        isPausedForRetry = false
        ListenTimingLog.log("engine_retry", ["engine": engineLabel])
        if let id = activeLocalEngineID { synthQueue.dropHost(engineID: id.rawValue) }
        synthQueue.isPausedForRetry = false
    }

    /// Launch: until `endLaunchHold`, the render queue adopts no saved bake job, renders nothing
    /// and loads no engine, so nothing renders on paragraphs the launch's maintenance (left audio
    /// work, the layout pass, dedupe, the prune) is about to rebuild, merge or delete, and the
    /// jobs it remaps are adopted as it leaves them.
    func holdRenderingForLaunch() {
        isHeldForLaunch = true
        synthQueue.isHeldForLaunch = true
    }

    /// The launch's maintenance has finished: adopt the saved bake jobs and render, the worker
    /// loading the first job's engine. With nothing queued, the worker preloads the Settings
    /// default's engine, so the first Play doesn't wait for its load.
    func endLaunchHold() {
        guard isHeldForLaunch else { return }
        isHeldForLaunch = false
        drainPendingIntoQueue()
        if synthQueue.primaryCacheKey == nil, engines.supports(defaultSelection.engine) {
            synthQueue.preload(engineID: defaultSelection.engine.rawValue)
        }
        synthQueue.isHeldForLaunch = false
    }

    /// Hand the crash-resume target to the UI once.
    func takePendingResume() -> ListenResumeTarget? {
        defer { pendingResume = nil }
        return pendingResume
    }

    // MARK: - Diagnostics

    /// Runs `work` with the model to itself: the render queue paused with its worker stopped (it
    /// finishes the load or chunk in flight) and the live host let go, so the models `work` loads
    /// are the only ones resident. The wait gives up after `timeout`. The queue resumes
    /// afterwards; its next work loads the engine again.
    func withRenderingQuiet<T>(timeout: Duration = .seconds(15 * 60), _ work: () async throws -> T) async rethrows -> T {
        let deadline = ContinuousClock.now + timeout
        synthQueue.isPausedForProbe = true
        defer { synthQueue.isPausedForProbe = false }
        while synthQueue.isWorkerRunning, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(200))
        }
        await synth.releaseHost()
        return try await work()
    }

    /// `id`'s provider changed how it renders (a route or thread setting): the render queue drops
    /// its host, and its next work for it loads one built the new way. Cached audio stays; the
    /// render pace starts over.
    func reloadEngine(_ id: SpeechEngineID) {
        RenderPace.shared.reset()
        synthQueue.dropHost(engineID: id.rawValue)
    }

    // MARK: - SynthQueueContext (route-aware background)

    var activeRouteRendersInBackground: Bool { synth.rendersInBackground }

    var playingCacheKey: UUID? { listenPlayer?.playingArticleID }

    func readyAheadSeconds(upTo limit: TimeInterval) -> TimeInterval {
        listenPlayer?.readyAheadSeconds(upTo: limit) ?? 0
    }

    /// Local engine whose cache / chunk sizing applies right now (loaded or loading).
    var activeLocalEngineID: SpeechEngineID? { synth.state.activeEngineID }

    /// `ArticleAudioCache` engine key for the active local engine.
    var cacheEngineID: String { (activeLocalEngineID ?? engines.defaultEngine.id).rawValue }

    var synthRenderer: SynthChunkRendering { synth }

    var residentEngineID: String? { synth.residentEngineID?.rawValue }

    func makeResident(_ engineID: String, priority: RenderPriority) async throws {
        let id = SpeechEngineID(rawValue: engineID)
        try await synth.makeResident(id, voice: engineVoices[id], priority: priority)
    }

    func dropHost(_ engineID: String) {
        guard synth.engineID.rawValue == engineID else { return }
        synth.turnOff()
    }

    /// Voice selected for a multi-voice engine (nil for single-voice engines).
    func voice(for id: SpeechEngineID) -> String? { engineVoices[id] }

    /// Persist the engine's selected voice id (also written when a voice finishes downloading).
    func setEngineVoice(_ id: SpeechEngineID, _ voice: String) {
        engineVoices[id] = voice
        if let key = engines.descriptor(id)?.resolvedVoiceDefaultsKey {
            defaults.set(voice, forKey: key)
        }
    }

    /// `ArticleAudioCache` voice key of engine `id`'s audio in its selected voice
    /// ("kokoro.af_heart"; the format is persisted); nil for an engine that renders nothing ahead.
    func cacheVoice(of id: SpeechEngineID) -> String? {
        engines.descriptor(id)?.cacheVoiceID(engineVoice: engineVoices[id])
    }

    /// Cache voice key of the active local engine (loaded or loading): what bake marks count.
    var activeCacheVoice: String? { activeLocalEngineID.flatMap(cacheVoice(of:)) }

    /// C138a: what renders for the article with `cacheKey`: its own selection, loaded or not (the
    /// render queue's worker loads it). Unlocked articles render in the default (which they then
    /// lock: `lockedRenderTarget`). nil: no registered engine speaks it, and nothing renders; no
    /// other engine or voice is ever substituted.
    func renderTarget(for cacheKey: UUID) -> RenderTarget? {
        target(for: storedSelection(of: cacheKey) ?? defaultSelection)
    }

    /// `renderTarget(for:)`, locking the default onto an article that had no voice yet.
    func lockedRenderTarget(for cacheKey: UUID) -> RenderTarget? {
        target(for: selection(for: cacheKey))
    }

    /// The render target for `selection`; nil when no registered engine speaks it.
    private func target(for selection: VoiceSelection) -> RenderTarget? {
        guard let voice = cacheVoice(of: selection) else { return nil }
        return RenderTarget(engineID: selection.engine.rawValue, cacheVoice: voice, engineVoice: selection.voice)
    }

    /// Paragraphs of `cacheKey` that still need audio in its voice
    /// (`ArticleAudioCache.missingParagraphs`); nil when no registered engine speaks it.
    func missingParagraphs(of cacheKey: UUID, paragraphs: [String]) -> [Int]? {
        guard let target = renderTarget(for: cacheKey) else { return nil }
        return audioCache.missingParagraphs(articleID: cacheKey, paragraphs: paragraphs, engineID: target.engineID,
                                            voiceID: target.cacheVoice, plans: chunkPlans)
    }

    func bakeCompleted(cacheKey: UUID) {
        pendingBakes.removePending(articleID: cacheKey)
        onRenderStateChange?()
    }

    /// True when a local model for `id` has been initialized (or its files are on disk).
    func isModelInstalled(_ id: SpeechEngineID) -> Bool {
        synth.state.readyEngineID == id || engines.isInstalled(id)
    }


    /// A voice was picked (Settings default or an article's picker): prepare its files if needed
    /// (e.g. a ~0.5 MB Kokoro pack). Selects nothing (`setDefaultSelection`, `ArticleVoiceChange`).
    /// Returns true once the files are there.
    func downloadVoice(_ voice: String, for id: SpeechEngineID) async -> Bool {
        guard let d = engines.descriptor(id) else { return false }
        voiceChoiceToken &+= 1
        let token = voiceChoiceToken
        voiceDownloadError = nil
        voiceDownloadID = voice
        do {
            try await engines.prepareVoice(voice, for: id)
        } catch {
            guard token == voiceChoiceToken else { return false }
            voiceDownloadID = nil
            let label = d.allVoices.first { $0.id == voice }?.label ?? voice
            voiceDownloadError = "Couldn't download \(label). Check your connection and try again."
            ListenDebugLog.shared.append("voice download failed \(voice): \(error.localizedDescription)")
            return false
        }
        guard token == voiceChoiceToken else { return false }
        voiceDownloadID = nil
        engineVoices[id] = voice // the host's voice when it loads; every render names its own
        voicePacksRevision &+= 1
        return true
    }

    /// What shows the engine's state (Settings' progress, the debug panel, Prepared Audio) looks
    /// again. Loads are the render queue's worker's (`makeResident`); nothing here starts one.
    private func engineStateChanged() {
        onRenderStateChange?()
    }

    /// Delete one local engine's downloaded models (default: the active local engine).
    /// Kept for Listen debug / CPU-route bench; Voice settings removes packs per voice instead.
    func deleteModel(_ engine: SpeechEngineID? = nil) throws {
        let id = engine ?? activeLocalEngineID ?? engines.defaultEngine.id
        switch synth.state {
        case .warming(id, _, _), .ready(id), .failed(id, _):
            synth.turnOff()
        default:
            break
        }
        try engines.deleteModels(id)
        voicePacksRevision &+= 1
        noteBakeMarksChanged()
    }

    func isVoicePackInstalled(_ voice: String, for id: SpeechEngineID) -> Bool {
        engines.isVoicePackInstalled(voice, for: id)
    }

    func canDeleteVoicePack(_ voice: String, for id: SpeechEngineID) -> Bool {
        engines.canDeleteVoicePack(voice, for: id)
    }

    /// Remove one on-device voice pack (swipe *Remove Download* on that voice). Heart stays when
    /// it is the only curated pack; deleting the selected pack falls back to Heart (or another
    /// installed pack if Heart itself was removed).
    func deleteVoicePack(_ voice: String, for id: SpeechEngineID) throws {
        guard engines.canDeleteVoicePack(voice, for: id) else { return }
        try engines.deleteVoicePack(voice, for: id)
        let fallback = fallbackVoiceAfterDeleting(voice, for: id)
        if engineVoices[id] == voice {
            setEngineVoice(id, fallback)
            // Its host goes after the call in flight; the next work for it loads a fresh one.
            synthQueue.dropHost(engineID: id.rawValue)
        }
        if defaultSelection.engine == id, defaultSelection.voice == voice {
            defaultSelection = VoiceSelection(engine: id, voice: fallback)
            defaults.set(defaultSelection.stored, forKey: Self.defaultSelectionKey)
        }
        voicePacksRevision &+= 1
        noteBakeMarksChanged()
    }

    /// After removing `voice`, prefer Heart (re-seeded from the bundle), else any other installed
    /// curated pack, else the engine's catalog default.
    private func fallbackVoiceAfterDeleting(_ voice: String, for id: SpeechEngineID) -> String {
        let heart = engines.descriptor(id)?.defaultVoiceID ?? KokoroVoiceCatalog.defaultVoice
        if voice != heart, engines.isVoicePackInstalled(heart, for: id) { return heart }
        if let other = engines.descriptor(id)?.allVoices.map(\.id).first(where: {
            $0 != voice && engines.isVoicePackInstalled($0, for: id)
        }) {
            return other
        }
        return heart
    }

    func noteBakeMarksChanged() {
        bakeMarksRevision &+= 1
        onRenderStateChange?()
    }

    func bakeTasksCount(for articleID: UUID) -> Int {
        synthQueue.pendingUnitCount(for: articleID)
    }

    // MARK: - Queue reshuffle (Reader, listening, Save)

    /// The Reader opened `cacheKey`, or listening starts or jumps there: its job becomes #1 and
    /// renders from paragraph `start` to the end, then the paragraphs above, the worker loading
    /// its engine. An ephemeral page's audio starts its TTL again; Save is what marks audio saved.
    func openArticle(cacheKey: UUID, paragraphs: [String], from start: Int, isEphemeral: Bool) {
        guard !paragraphs.isEmpty, rendersAhead(cacheKey, paragraphs: paragraphs) else { return }
        focusCacheKey = cacheKey
        if isEphemeral { audioCache.markEphemeral(cacheKey: cacheKey, lastAccess: Date()) }
        synthQueue.enqueue(cacheKey: cacheKey, paragraphs: paragraphs, from: start, isEphemeral: isEphemeral,
                           at: .front)
    }

    /// Paragraphs of the next chapter rendered before it plays (`stageNextChapter`).
    static let stagedChapterParagraphs = 3

    /// The next chapter of the book or series playing (`playing`) renders its opening before its
    /// turn (`GlobalSynthQueue.stageNext`), so it starts without waiting for the model. False when
    /// nothing renders ahead (a voice that can't run here, a language the engine doesn't speak),
    /// and for audio held for unfinished library work (`ArticleAudioCache.held`), which a render
    /// would overwrite before that work reads it.
    @discardableResult
    func stageNextChapter(cacheKey: UUID, after playing: UUID, paragraphs: [String]) -> Bool {
        guard !paragraphs.isEmpty, rendersAhead(cacheKey, paragraphs: paragraphs),
              !audioCache.held.contains(cacheKey) else { return false }
        synthQueue.stageNext(cacheKey: cacheKey, after: playing, paragraphs: paragraphs,
                             upTo: Self.stagedChapterParagraphs,
                             isEphemeral: audioCache.isEphemeral(cacheKey))
        return true
    }

    /// On article save (or a prepare, a finished listen's gap fill): render it in full, top
    /// down, behind what is queued (#1 when nothing is). A job already queued, the one playing
    /// included, keeps its place and plan and just turns saved.
    func startBakeIfNeeded(articleID: UUID, paragraphs: [String]) {
        guard !paragraphs.isEmpty, rendersAhead(articleID, paragraphs: paragraphs) else { return }
        audioCache.markSaved(cacheKey: articleID)
        pendingBakes.enqueuePending(articleID: articleID, paragraphs: paragraphs, priorityStart: 0)
        synthQueue.enqueue(cacheKey: articleID, paragraphs: paragraphs, isEphemeral: false, at: .back)
    }

    /// After Save: move ephemeral CAFs onto the saved page's key and reshuffle the queue key.
    func migrateListenCache(from ephemeralKey: UUID, to savedKey: UUID) {
        guard ephemeralKey != savedKey else {
            // Identity v2: saved id == reader key, so Save is just a kind flip (no dir move,
            // no queue rekey, no playback teardown).
            markListenCacheSaved(savedKey)
            return
        }
        do {
            try audioCache.rekeyCache(from: ephemeralKey, to: savedKey)
            synthQueue.rekey(from: ephemeralKey, to: savedKey)
            synthQueue.setEphemeral(cacheKey: savedKey, false)
            noteBakeMarksChanged()
            ListenDebugLog.shared.append("cache migrated \(ephemeralKey.uuidString.prefix(8)) → \(savedKey.uuidString.prefix(8))")
        } catch {
            ListenDebugLog.shared.append("cache migrate failed: \(error.localizedDescription)")
        }
    }

    /// Identity v2 open-time alignment of the TTS cache with the current listen blocks.
    /// - Adopts an old v1 (URL+content) ephemeral dir into `key` when `key` has no cache yet.
    /// - Stamps unhashed legacy entries with `trustedParagraphs` (text known to match the cache).
    /// - Reconciles per-paragraph hashes so only changed paragraphs re-bake.
    /// - Gives a queued job for `key` the same paragraphs (`GlobalSynthQueue.updateParagraphs`).
    /// Skip while `key` is the live playback session (never move files under the player).
    func prepareListenIdentity(
        key: UUID,
        paragraphs: [String],
        trustedParagraphs: [String]? = nil,
        legacyKeys: [UUID] = [],
        isLivePlayback: Bool = false
    ) {
        guard !paragraphs.isEmpty, !isLivePlayback else { return }
        if synthQueue.hasJob(cacheKey: key) {
            // Its bake is queued / in progress (e.g. Browse → Save → open in Reader while
            // another article plays): keep finished chunks whose text still matches, or the
            // worker renders them a second time.
            audioCache.removeChunkScratch(for: key, keepingCurrent: paragraphs)
        } else {
            audioCache.removeChunkScratch(for: key)
            synthQueue.clearLiveChunkMarks(cacheKey: key)
        }
        if !audioCache.hasCache(for: key) {
            for legacy in legacyKeys where legacy != key && audioCache.hasCache(for: legacy) {
                do {
                    try audioCache.rekeyCache(from: legacy, to: key)
                    // v1 key embedded the content hash, so its units match `paragraphs`.
                    try audioCache.stampMissingHashes(articleID: key, paragraphs: paragraphs)
                    ListenDebugLog.shared.append("identity adopt v1 \(legacy.uuidString.prefix(8)) → \(key.uuidString.prefix(8))")
                } catch {
                    ListenDebugLog.shared.append("identity adopt v1 failed: \(error.localizedDescription)")
                }
                break
            }
        }
        do {
            if let trustedParagraphs {
                try audioCache.stampMissingHashes(articleID: key, paragraphs: trustedParagraphs)
            }
            // Giant paragraphs split since this audio was rendered (layout v3) keep the pieces
            // whose chunks line up with the old render; the rest re-render.
            let result = try audioCache.reconcile(articleID: key, paragraphs: paragraphs) {
                self.chunkPlans.chunks(for: $1, engineID: $0)
            }
            // The job renders what the audio now follows, or it would file renders of its old
            // text on these paragraphs (Save doesn't reopen a job that is already #1).
            synthQueue.updateParagraphs(cacheKey: key, paragraphs: paragraphs)
            let msg = "identity \(key.uuidString.prefix(8)) fp=\(ArticleIdentity.contentFingerprint(paragraphs: paragraphs).prefix(8)) kept=\(result.kept) moved=\(result.remapped) dropped=\(result.dropped) legacy=\(result.unverified) split=\(result.splitParagraphs) sliced=\(result.sliced)"
            ListenDebugLog.shared.append(msg)
            if result.changed { noteBakeMarksChanged() }
        } catch {
            // The last saved index is intact (copy-on-write); the next open tries again.
            ListenDebugLog.shared.append("identity \(key.uuidString.prefix(8)) align failed: \(error.localizedDescription)")
        }
    }

    /// This device can run one of the engines, so prepared audio renders (an article whose engine
    /// can't run here renders nothing: `rendersAhead`).
    var wantsLocalBake: Bool { engines.descriptors.contains { engines.supports($0.id) } }

    /// Persisted pending jobs → queue, once the launch hold is over (no engine needs to be
    /// loaded: the worker loads the first job's). The focused (active) article stays #1; see
    /// `GlobalSynthQueue.adoptPending`. A job for audio held for unfinished library work
    /// (`ArticleAudioCache.held`) waits on disk until that work lets it go (`heldAudioChanged`).
    func drainPendingIntoQueue() {
        guard !isHeldForLaunch else { return }
        let pending = pendingBakes.pendingJobs()
            .filter { rendersAhead($0.articleID, paragraphs: $0.paragraphs) && !audioCache.held.contains($0.articleID) }
        guard !pending.isEmpty else { return }
        ListenDebugLog.shared.append("adopting \(pending.count) saved bake job(s)")
        synthQueue.adoptPending(pending.map { job in
            GlobalSynthQueue.PendingWork(
                cacheKey: job.articleID,
                paragraphs: job.paragraphs,
                priorityStart: job.priorityStart,
                isEphemeral: audioCache.isEphemeral(job.articleID)
            )
        }, focusKey: focusCacheKey)
    }
}
