import Foundation
import Observation

@MainActor
@Observable
final class LocalTTSCoordinator: SynthQueueContext {
    static let engineIDKey = "reader.tts.engineID"

    /// Every engine + its capabilities. Injected from the composition root.
    let engines: EngineRegistry
    let audioCache: ArticleAudioCache
    /// Single global Core ML work queue — actions reshuffle; one worker drains #1.
    let synthQueue = GlobalSynthQueue()
    /// Engine selection, voices and launch-step flags (a suite in tests).
    let defaults: UserDefaults
    let crashGuard: EngineCrashGuard

    /// The on-device engine's model: lifecycle, host and renderer. The render queue renders through it.
    let synth: LocalSynthService
    /// Called after every engine-state change and engine-voice change. `SpeechController` uses it
    /// to decide whether the live utterance moves to another engine (views never coordinate that).
    @ObservationIgnored var onEngineChange: (() -> Void)?
    /// The listen player (set by `LocalListenEngine`): the render queue asks it which article is
    /// playing (listener priority, background bake scope).
    @ObservationIgnored weak var listenPlayer: LocalListenPlayer?
    /// Selected voice per multi-voice engine (e.g. Kokoro `af_heart`). Part of the cache voice key.
    private(set) var engineVoices: [SpeechEngineID: String] = [:]
    /// Set when the last process died inside a crash-guarded engine (`CrashRecovery`; Kokoro:
    /// resumed on the ONNX route, or switched to Apple after repeated ONNX crashes). Shown as a
    /// dismissible one-line banner and in Settings.
    private(set) var engineCrashNotice: String?
    private var crashedEngineID: SpeechEngineID?
    /// The crash marker this launch found (the previous process died inside an engine call).
    private(set) var launchCrash: EngineCrashGuard.CrashInfo?
    /// Article + paragraph to resume after a crash, handed to the UI once (`takePendingResume`).
    /// Settable in-module for tests.
    var pendingResume: ListenResumeTarget?
    /// Bumped when CAF ready set changes — reading UI observes this for live bake marks.
    private(set) var bakeMarksRevision: UInt64 = 0
    /// Article the user most recently opened / listened to (stays #1 when pending jobs drain).
    private var focusCacheKey: UUID?
    /// From the start of the launch's audio-cache steps until the library's launch maintenance has
    /// finished (`holdRenderingForLaunch`, `endLaunchHold`).
    @ObservationIgnored private(set) var isHeldForLaunch = false
    /// Voice whose files are downloading after the user picked it (Settings shows a spinner).
    private(set) var voiceDownloadID: String?
    /// Last voice download failure (Settings footer); cleared on the next pick.
    private(set) var voiceDownloadError: String?
    private var voiceChoiceToken = 0
    /// Set by `SpeechController`: may the local engine speak (and bake) these listen blocks?
    /// False when the article's effective language isn't supported by the engine (it then
    /// speaks with Apple). nil = always.
    var localLanguageGate: (([String]) -> Bool)?

    /// Picks the launch engine (the stored selection, after crash recovery) and starts loading
    /// it. One-time launch steps are `LaunchMigration`s, run by `AppComposition`.
    init(
        engines: EngineRegistry,
        defaults: UserDefaults = .standard,
        audioCache: ArticleAudioCache? = nil,
        crashGuard: EngineCrashGuard = .shared
    ) {
        self.engines = engines
        self.defaults = defaults
        self.audioCache = audioCache ?? ArticleAudioCache()
        self.crashGuard = crashGuard
        self.synth = LocalSynthService(engines: engines)
        for d in engines.localDescriptors where !d.voices.isEmpty {
            // Stored voice if still offered (curated list), else the engine default.
            engineVoices[d.id] = d.resolvedVoice(defaults.string(forKey: d.resolvedVoiceDefaultsKey))
        }
        synthQueue.attach(coordinator: self)
        synth.onStateChange = { [weak self] in self?.engineStateChanged() }
        var initial = storedSelection()
        // Pre-DI crash markers carry no engine id; only crash-guarded engines ever wrote them.
        launchCrash = crashGuard.consumeCrashInfo(legacyEngine: engines.localDescriptors.first { $0.crashGuarded }?.id)
        if let launchCrash { initial = recover(from: launchCrash, selection: initial) }
        #if DEBUG
        // Dev/test hook: `-selectEngine <engine id>` (persisted), e.g. local.kokoro.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-selectEngine"), i + 1 < args.count,
           engines.contains(SpeechEngineID(rawValue: args[i + 1])) {
            initial = SpeechEngineID(rawValue: args[i + 1])
            if initial == crashedEngineID { engineCrashNotice = nil; crashedEngineID = nil }
        }
        #endif
        start(initial)
    }

    /// The persisted engine: a retired engine becomes its replacement when that is installed
    /// (else Apple); an unknown id is Apple.
    private func storedSelection() -> SpeechEngineID {
        let stored = SpeechEngineID(rawValue: defaults.string(forKey: Self.engineIDKey) ?? SpeechEngineID.apple.rawValue)
        if let retired = engines.retiredEngines.first(where: { $0.id == stored }) {
            let to: SpeechEngineID = engines.supports(retired.replacement) && engines.isInstalled(retired.replacement)
                ? retired.replacement : .apple
            ListenDebugLog.shared.append("retired engine: \(retired.displayName) was selected → \(engines.displayName(to))")
            return to
        }
        return engines.contains(stored) ? stored : .apple
    }

    /// The previous process died inside `crash.engine`. Its provider decides (Kokoro: resume on the
    /// stable route); by default a crashed selection moves to the crash fallback.
    private func recover(from crash: EngineCrashGuard.CrashInfo, selection: SpeechEngineID) -> SpeechEngineID {
        guard let engine = crash.engine else { return selection }
        if let recovery = engines.recover(from: crash, playing: ListenResumePointStore.shared.load()) {
            return apply(recovery, crashed: engine)
        }
        guard engine == selection else { return selection }
        let fallback = engines.crashFallback(for: engine)
        let d = engines.descriptor(engine)
        let name = d?.shortName ?? engine.rawValue
        print("[TTS] \(name) crash detected → \(fallback.rawValue)")
        return apply(.switchAway(notice: "\(name) crashed last session (\(d?.crashNoticeDetail ?? "engine crash")). "
            + "Switched to \(engines.displayName(fallback)). Tap \(name) to try again."), crashed: engine)
    }

    /// Note the recovery for the UI; returns the engine to use.
    private func apply(_ recovery: CrashRecovery, crashed engine: SpeechEngineID) -> SpeechEngineID {
        engineCrashNotice = recovery.notice
        switch recovery {
        case .stay(_, let resume):
            pendingResume = resume
            return engine
        case .switchAway:
            crashedEngineID = engine
            return engines.crashFallback(for: engine)
        }
    }

    /// A launch step found an older crash to recover from (`KokoroONNXMainMigration`).
    func applyLaunchRecovery(_ recovery: CrashRecovery, crashed engine: SpeechEngineID) {
        start(apply(recovery, crashed: engine))
    }

    /// Persist `id` and load it when it's an on-device engine this device supports; else Apple.
    private func start(_ id: SpeechEngineID) {
        guard id.isLocal, engines.supports(id) else {
            synth.turnOff()
            return
        }
        defaults.set(id.rawValue, forKey: Self.engineIDKey)
        beginWarm(id)
    }

    static var buildConfiguration: String {
        #if DEBUG
        return "debug"
        #else
        return "release"
        #endif
    }

    /// The engine Settings shows as chosen (the on-device one while it loads or once loaded).
    var selectedEngineID: SpeechEngineID { synth.state.selectedEngineID }
    /// The on-device engine is loaded and serves listening and bake-ahead.
    var usesLocalEngine: Bool { synth.state.readyEngineID != nil }

    /// Dismiss the one-line crash banner.
    func dismissCrashNotice() {
        engineCrashNotice = nil
    }

    /// The library moved the page the crash-resume target names, which was read at init, before
    /// the launch maintenance: its paragraphs were rebuilt, or dedupe merged it into the page
    /// `newKey`. The target follows, onto the paragraph `map` gives.
    func remapPendingResume(article: UUID, to newKey: UUID? = nil, _ map: (Int) -> Int) {
        guard var target = pendingResume, target.matches(article) else { return }
        if let newKey { target.articleKey = newKey.uuidString }
        target.paragraph = map(target.paragraph)
        pendingResume = target
    }

    /// Launch: until `endLaunchHold`, the render queue adopts no saved bake job and renders
    /// nothing, so nothing renders on paragraphs the launch's maintenance (left audio work, the
    /// layout pass, dedupe, the prune) is about to rebuild, merge or delete, and the jobs it
    /// remaps are adopted as it leaves them. The engine still loads meanwhile.
    func holdRenderingForLaunch() {
        isHeldForLaunch = true
        synthQueue.isHeldForLaunch = true
    }

    /// The launch's maintenance has finished: adopt the saved bake jobs if the engine is loaded
    /// (else when it is), and render.
    func endLaunchHold() {
        guard isHeldForLaunch else { return }
        isHeldForLaunch = false
        drainPendingIntoQueue()
        synthQueue.isHeldForLaunch = false
    }

    /// Hand the crash-resume target to the UI once.
    func takePendingResume() -> ListenResumeTarget? {
        defer { pendingResume = nil }
        return pendingResume
    }

    // MARK: - Kokoro route (ONNX CPU default; Core ML GPU debug opt-in)

    var kokoroRouteSettings: KokoroRouteSettings { KokoroRouteSettings(defaults: defaults) }

    /// Route the live Kokoro host actually uses (nil = no Kokoro host loaded).
    var liveKokoroRoute: KokoroRoute? {
        guard let tag = synth.liveRenderer(for: .kokoro)?.host.routeTag else { return nil }
        return KokoroRoute(rawValue: tag)
    }

    /// Debug: flip the fast GPU (Core ML) route, then rebuild the Kokoro host. Cached audio stays.
    func setKokoroFastGPURoute(_ on: Bool) async {
        guard kokoroRouteSettings.fastGPURouteEnabled != on else { return }
        kokoroRouteSettings.fastGPURouteEnabled = on
        ListenTimingLog.log("kokoro_route_change", ["route": kokoroRouteSettings.route.rawValue])
        await reloadKokoroHost()
    }

    /// Debug: ONNX thread override (rebuilds the host).
    func setKokoroCPUThreads(_ threads: Int) async {
        guard kokoroRouteSettings.cpuThreads != threads else { return }
        kokoroRouteSettings.cpuThreads = threads
        ListenTimingLog.log("kokoro_threads_change", ["threads": kokoroRouteSettings.cpuThreads])
        await reloadKokoroHost()
    }

    private func reloadKokoroHost() async {
        RenderPace.shared.reset()
        guard activeLocalEngineID == .kokoro else { return }
        let load = synth.reload(.kokoro, voice: engineVoices[.kokoro])
        synthQueue.engineDidChange()
        await load.value
    }

    // MARK: - SynthQueueContext (route-aware background)

    var activeRouteRendersInBackground: Bool { synth.rendersInBackground }

    var playingCacheKey: UUID? { listenPlayer?.playingArticleID }

    /// Local engine whose cache / chunk sizing applies right now (loaded or loading).
    var activeLocalEngineID: SpeechEngineID? { synth.state.activeEngineID }

    /// `ArticleAudioCache` engine key for the active local engine.
    var cacheEngineID: String { (activeLocalEngineID ?? engines.defaultLocalEngineID).rawValue }

    /// Chunk sizing for the active local engine.
    var activeChunkLimits: TextChunker.Limits { engines.limits(for: activeLocalEngineID ?? engines.defaultLocalEngineID) }

    var synthRenderer: SynthChunkRendering { synth }

    /// Voice selected for a multi-voice engine (nil for single-voice engines).
    func voice(for id: SpeechEngineID) -> String? { engineVoices[id] }

    /// `ArticleAudioCache` voice key per the active engine's `CacheVoiceKeyStyle`
    /// (Kokoro: "kokoro.<voice>" — key format unchanged since the Kokoro release).
    func cacheVoiceID(appleVoice: String?) -> String {
        guard let id = activeLocalEngineID, let d = engines.descriptor(id) else { return appleVoice ?? "system" }
        return d.cacheVoiceID(engineVoice: engineVoices[id], appleVoice: appleVoice)
    }

    /// Map any stored/passed voice key onto the active engine's key space (pending jobs may
    /// carry an Apple voice id from an old session, or another voice's key after a voice switch).
    func normalizedCacheVoice(_ voiceID: String) -> String {
        if let id = activeLocalEngineID, let d = engines.descriptor(id), case .prefixed = d.cacheVoiceKey {
            return d.cacheVoiceID(engineVoice: engineVoices[id], appleVoice: nil)
        }
        return engines.isEngineVoiceKey(voiceID) ? "system" : voiceID
    }

    func fallbackAppleVoice(forCacheVoice voiceID: String) -> String? {
        (voiceID == "system" || engines.isEngineVoiceKey(voiceID)) ? nil : voiceID
    }

    func bakeCompleted(cacheKey: UUID) {
        PendingBakeJobStore.shared.removePending(articleID: cacheKey)
    }

    /// True when a local model for `id` has been initialized (or its files are on disk).
    func isModelInstalled(_ id: SpeechEngineID) -> Bool {
        synth.state.readyEngineID == id || engines.isInstalled(id)
    }

    func setVoice(_ voice: String, for id: SpeechEngineID) {
        guard let d = engines.descriptor(id), voice != engineVoices[id] else { return }
        engineVoices[id] = voice
        defaults.set(voice, forKey: d.resolvedVoiceDefaultsKey)
        guard activeLocalEngineID == id else { return }
        synth.setVoice(voice, for: id)
        synthQueue.engineDidChange()
        noteBakeMarksChanged()
        onEngineChange?()
    }

    /// User picked `voice` in Settings: download its files if needed (e.g. a ~0.5 MB Kokoro
    /// pack), then switch. The article cache then re-renders in the new voice (one voice per
    /// article, see `ArticleAudioCache`). Returns true if the voice changed.
    @discardableResult
    func chooseVoice(_ voice: String, for id: SpeechEngineID) async -> Bool {
        guard let d = engines.descriptor(id), voice != engineVoices[id] else { return false }
        voiceChoiceToken &+= 1
        let token = voiceChoiceToken
        voiceDownloadError = nil
        voiceDownloadID = voice
        do {
            try await engines.prepareVoice(voice, for: id)
        } catch {
            guard token == voiceChoiceToken else { return false }
            voiceDownloadID = nil
            let label = d.voices.first { $0.id == voice }?.label ?? voice
            voiceDownloadError = "Couldn't download \(label). Check your connection and try again."
            ListenDebugLog.shared.append("voice download failed \(voice): \(error.localizedDescription)")
            return false
        }
        guard token == voiceChoiceToken else { return false }
        voiceDownloadID = nil
        setVoice(voice, for: id)
        return true
    }

    private func localLanguageAllows(_ paragraphs: [String]) -> Bool {
        localLanguageGate?(paragraphs) ?? true
    }

    /// Select any registered engine. Local engines download-on-select + warm, and only one
    /// local engine's models stay loaded (the other host is dropped). Returns once the choice has
    /// settled (loaded, failed, or replaced by another pick).
    func selectEngine(_ id: SpeechEngineID) async {
        guard id.isLocal else {
            synth.turnOff()
            return
        }
        guard engines.supports(id) else {
            synth.markUnavailable(id)
            return
        }
        if id == crashedEngineID {
            // Picking the engine again after a crash fallback = a fresh try.
            engineCrashNotice = nil
            crashedEngineID = nil
            engines.crashRetried(id)
        }
        switch synth.state {
        case .ready(id):
            return
        case .warming(id, _, let task):
            await task.value
        default:
            await beginWarm(id).value
        }
    }

    /// Load `id` (see `LocalSynthService.load`); the queue drops the old engine's chunk plans
    /// and scratch.
    @discardableResult
    private func beginWarm(_ id: SpeechEngineID) -> Task<Void, Never> {
        let load = synth.load(id, voice: engineVoices[id])
        synthQueue.engineDidChange()
        return load
    }

    /// Persist the selection, let the controller move the live utterance, and once a load
    /// finishes fold the waiting bake jobs into the queue.
    private func engineStateChanged() {
        let state = synth.state
        if let persisted = state.persistedSelection {
            defaults.set(persisted.rawValue, forKey: Self.engineIDKey)
        }
        onEngineChange?()
        if case .ready = state {
            noteBakeMarksChanged()
            drainPendingIntoQueue()
        }
    }

    /// Delete one local engine's downloaded models (default: the active local engine).
    func deleteModel(_ engine: SpeechEngineID? = nil) throws {
        let id = engine ?? activeLocalEngineID ?? engines.defaultLocalEngineID
        switch synth.state {
        case .warming(id, _, _), .ready(id), .failed(id, _):
            synth.turnOff()
        default:
            break
        }
        try engines.deleteModels(id)
        noteBakeMarksChanged()
    }

    func hasListenAudio(for articleID: UUID) -> Bool {
        audioCache.hasCache(for: articleID)
    }

    func clearListenAudio(for articleID: UUID) throws {
        synthQueue.remove(cacheKey: articleID)
        try audioCache.deleteAudio(for: articleID)
        noteBakeMarksChanged()
        PendingBakeJobStore.shared.removePending(articleID: articleID)
    }

    func noteBakeMarksChanged() {
        bakeMarksRevision &+= 1
    }

    func handleArticleDeleted(_ articleID: UUID) {
        try? clearListenAudio(for: articleID)
    }

    func bakeTasksCount(for articleID: UUID) -> Int {
        synthQueue.pendingUnitCount(for: articleID)
    }

    func bakeStatus(for articleID: UUID, paragraphCount: Int) -> ArticleAudioCache.Status {
        audioCache.status(for: articleID, expectedParagraphs: paragraphCount)
    }

    // MARK: - Shared warm / queue reshuffle (Browse + Saved)

    /// Open/focus an article as queue #1 and bake from resume downward.
    /// Shared by Browse Reader and Offline — not separate bake stacks.
    func warmListenAudio(
        cacheKey: UUID,
        paragraphs: [String],
        voiceID: String,
        resumeParagraph: Int = 0,
        isEphemeral: Bool
    ) {
        guard !paragraphs.isEmpty, wantsLocalBake, localLanguageAllows(paragraphs) else { return }
        let voiceID = normalizedCacheVoice(voiceID)
        focusCacheKey = cacheKey
        guard usesLocalEngine else {
            // Still loading: the job waits on disk and joins the queue when the load finishes.
            PendingBakeJobStore.shared.enqueuePending(
                articleID: cacheKey,
                paragraphs: paragraphs,
                voiceID: voiceID,
                plan: resumeParagraph <= 0
                    ? .topDown(paragraphCount: paragraphs.count)
                    : .fromPlayhead(resumeParagraph, paragraphCount: paragraphs.count)
            )
            print("[SynthQueue] queued pending key=\(cacheKey.uuidString.prefix(8)) (local engine warming)")
            return
        }
        if isEphemeral {
            audioCache.markEphemeral(cacheKey: cacheKey, lastAccess: Date())
        } else {
            audioCache.markSaved(cacheKey: cacheKey)
        }
        synthQueue.openArticle(
            cacheKey: cacheKey,
            paragraphs: paragraphs,
            voiceID: voiceID,
            resumeParagraph: resumeParagraph,
            isEphemeral: isEphemeral
        )
    }

    /// Listen start / jump: article stays #1; cursor → paragraph…end then gap-fill.
    func prioritizeListen(
        cacheKey: UUID,
        playhead: Int,
        paragraphs: [String],
        voiceID: String,
        isEphemeral: Bool = false
    ) {
        guard !paragraphs.isEmpty, wantsLocalBake, localLanguageAllows(paragraphs) else { return }
        let voiceID = normalizedCacheVoice(voiceID)
        focusCacheKey = cacheKey
        if isEphemeral {
            audioCache.markEphemeral(cacheKey: cacheKey, lastAccess: Date())
        }
        if usesLocalEngine {
            synthQueue.openArticle(
                cacheKey: cacheKey,
                paragraphs: paragraphs,
                voiceID: voiceID,
                resumeParagraph: playhead,
                isEphemeral: isEphemeral
            )
            synthQueue.focusPlayhead(cacheKey: cacheKey, paragraph: playhead)
        } else {
            warmListenAudio(
                cacheKey: cacheKey,
                paragraphs: paragraphs,
                voiceID: voiceID,
                resumeParagraph: playhead,
                isEphemeral: isEphemeral
            )
        }
    }

    /// Paragraphs of the next chapter rendered before it plays (`stageNextChapter`).
    static let stagedChapterParagraphs = 3

    /// The next chapter of the book or series playing (`playing`) renders its opening before its
    /// turn (`GlobalSynthQueue.stageNext`), so it starts without waiting for the model. False when
    /// nothing renders ahead (Apple, a model still loading, a language the engine doesn't speak),
    /// and for audio held for unfinished library work (`ArticleAudioCache.held`), which a render
    /// would overwrite before that work reads it.
    @discardableResult
    func stageNextChapter(cacheKey: UUID, after playing: UUID, paragraphs: [String], voiceID: String) -> Bool {
        guard !paragraphs.isEmpty, wantsLocalBake, usesLocalEngine, localLanguageAllows(paragraphs),
              !audioCache.held.contains(cacheKey) else { return false }
        synthQueue.stageNext(cacheKey: cacheKey, after: playing, paragraphs: paragraphs,
                             voiceID: normalizedCacheVoice(voiceID), upTo: Self.stagedChapterParagraphs,
                             isEphemeral: audioCache.loadMeta(for: cacheKey)?.kind == .ephemeral)
        return true
    }

    /// On article save: enqueue (demoted if something else is #1) top → down.
    func startBakeIfNeeded(articleID: UUID, paragraphs: [String], voiceID: String) {
        guard !paragraphs.isEmpty, wantsLocalBake, localLanguageAllows(paragraphs) else { return }
        let voiceID = normalizedCacheVoice(voiceID)
        audioCache.markSaved(cacheKey: articleID)
        PendingBakeJobStore.shared.enqueuePending(
            articleID: articleID,
            paragraphs: paragraphs,
            voiceID: voiceID,
            plan: .topDown(paragraphCount: paragraphs.count)
        )
        // Still loading: the job joins the queue when the load finishes.
        guard usesLocalEngine else { return }
        // Already #1 (e.g. Save mid-listen): keep its playhead plan; just flip to saved.
        if synthQueue.primaryCacheKey == articleID, synthQueue.hasJob(cacheKey: articleID) {
            synthQueue.setEphemeral(cacheKey: articleID, false)
            return
        }
        // If nothing is playing, open as #1; else demote behind current listen.
        if synthQueue.primaryCacheKey == nil || synthQueue.primaryCacheKey == articleID {
            synthQueue.openArticle(
                cacheKey: articleID,
                paragraphs: paragraphs,
                voiceID: voiceID,
                resumeParagraph: 0,
                isEphemeral: false
            )
        } else {
            synthQueue.enqueueDemoted(
                cacheKey: articleID,
                paragraphs: paragraphs,
                voiceID: voiceID,
                isEphemeral: false
            )
        }
    }

    /// After Save: move ephemeral CAFs onto the saved page's key and reshuffle the queue key.
    func migrateListenCache(from ephemeralKey: UUID, to savedKey: UUID) {
        guard ephemeralKey != savedKey else {
            // Identity v2: saved id == reader key, so Save is just a kind flip (no dir move,
            // no queue rekey, no playback teardown).
            audioCache.markSaved(cacheKey: savedKey)
            synthQueue.setEphemeral(cacheKey: savedKey, false)
            return
        }
        do {
            try audioCache.rekeyCache(from: ephemeralKey, to: savedKey)
            synthQueue.rekey(from: ephemeralKey, to: savedKey)
            synthQueue.setEphemeral(cacheKey: savedKey, false)
            noteBakeMarksChanged()
            print("[TTSCache] migrated \(ephemeralKey.uuidString.prefix(8)) → \(savedKey.uuidString.prefix(8))")
        } catch {
            print("[TTSCache] migrate failed: \(error.localizedDescription)")
        }
    }

    /// Unsave from the reader: keep the audio (and playhead) but let the ephemeral TTL own it again.
    func markListenCacheEphemeral(_ key: UUID, canonicalURL: String? = nil) {
        audioCache.markEphemeral(cacheKey: key, canonicalURL: canonicalURL, lastAccess: Date())
        synthQueue.setEphemeral(cacheKey: key, true)
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
                    print("[Identity] adopted legacy cache \(legacy.uuidString.prefix(8)) → \(key.uuidString.prefix(8))")
                } catch {
                    print("[Identity] legacy adopt failed: \(error.localizedDescription)")
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
            let result = try audioCache.reconcile(articleID: key, paragraphs: paragraphs) { self.chunkPlan(engineID: $0, text: $1) }
            // The job renders what the audio now follows, or it would file renders of its old
            // text on these paragraphs (Save doesn't reopen a job that is already #1).
            synthQueue.updateParagraphs(cacheKey: key, paragraphs: paragraphs)
            let msg = "identity \(key.uuidString.prefix(8)) fp=\(ArticleIdentity.contentFingerprint(paragraphs: paragraphs).prefix(8)) kept=\(result.kept) moved=\(result.remapped) dropped=\(result.dropped) legacy=\(result.unverified) split=\(result.splitParagraphs) sliced=\(result.sliced)"
            ListenDebugLog.shared.append(msg)
            print("[Identity] \(msg)")
            if result.changed { noteBakeMarksChanged() }
        } catch {
            // The last saved index is intact (copy-on-write); the next open tries again.
            ListenDebugLog.shared.append("identity \(key.uuidString.prefix(8)) align failed: \(error.localizedDescription)")
            print("[Identity] align failed: \(error.localizedDescription)")
        }
    }

    /// The render queue's chunk plan for `text` as rendered by `engineID` (nil if unknown engine).
    func chunkPlan(engineID: String, text: String) -> [String]? {
        guard let d = engines.descriptor(SpeechEngineID(rawValue: engineID)) else { return nil }
        return TextChunker.chunks(for: text, limits: d.limits)
    }

    /// Bake only for engines that declare `supportsBakeCache` (Apple: no).
    private var wantsLocalBake: Bool {
        guard let id = activeLocalEngineID else { return false }
        return engines.descriptor(id)?.supportsBakeCache == true
    }

    /// Persisted pending jobs → queue, once the engine is loaded and the launch hold is over. The
    /// focused (active) article stays #1; see `GlobalSynthQueue.adoptPending`. A job for audio
    /// held for unfinished library work (`ArticleAudioCache.held`) waits on disk.
    private func drainPendingIntoQueue() {
        guard usesLocalEngine, !isHeldForLaunch else { return }
        let pending = PendingBakeJobStore.shared.pendingJobs()
            .filter { localLanguageAllows($0.paragraphs) && !audioCache.held.contains($0.articleID) }
        guard !pending.isEmpty else { return }
        print("[SynthQueue] draining \(pending.count) pending job(s)")
        synthQueue.adoptPending(pending.map { job in
            GlobalSynthQueue.PendingWork(
                cacheKey: job.articleID,
                paragraphs: job.paragraphs,
                voiceID: normalizedCacheVoice(job.voiceID),
                priorityStart: job.priorityStart,
                isEphemeral: audioCache.loadMeta(for: job.articleID)?.kind == .ephemeral
            )
        }, focusKey: focusCacheKey)
    }
}
