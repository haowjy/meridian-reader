import Foundation
import Observation

@MainActor
@Observable
final class LocalTTSCoordinator: SynthQueueContext {
    static let engineIDKey = "reader.tts.engineID"

    /// Every engine + its capabilities. Injected from the composition root.
    let engines: EngineRegistry
    let downloader = TTSModelDownloader()
    let audioCache: ArticleAudioCache
    /// Single global Core ML work queue — actions reshuffle; one worker drains #1.
    let synthQueue = GlobalSynthQueue()
    private let defaults: UserDefaults
    private let crashGuard: EngineCrashGuard

    private(set) var selectedEngineID: SpeechEngineID
    /// Desired engine while a local prepare / download may still be in flight.
    private(set) var pendingEngineID: SpeechEngineID?
    /// True after the selected local engine's initialize succeeded this session.
    private(set) var localHostReady = false
    /// Model download fraction (0…1) while the pending local engine fetches weights.
    private(set) var modelDownloadFraction: Double?
    /// Selected voice per multi-voice engine (e.g. Kokoro `af_heart`). Part of the cache voice key.
    private(set) var engineVoices: [SpeechEngineID: String] = [:]
    /// Set when the last process died inside a crash-guarded engine (Kokoro: auto-recovered on
    /// the ONNX route, or switched to Apple after repeated ONNX crashes). Shown as a dismissible
    /// one-line banner and in Settings.
    private(set) var engineCrashNotice: String?
    private var crashedEngineID: SpeechEngineID?
    /// Article + paragraph to resume after a Kokoro crash (consumed once by the Saved screen).
    /// Set at init from a crash marker; handed to the UI once (`takePendingResume`). Settable
    /// in-module for tests.
    var pendingResume: ListenResumeTarget?
    static let onnxMainMigrationKey = "reader.tts.kokoro.onnxMainMigration.v1"
    /// Bumped when CAF ready set changes — reading UI observes this for live bake marks.
    private(set) var bakeMarksRevision: UInt64 = 0
    /// Article the user most recently opened / listened to (stays #1 when pending jobs drain).
    private var focusCacheKey: UUID?
    private var localEngine: LocalModelSpeechEngine?
    /// Single-flight local-engine prepare shared by Settings select and Speak.
    private var localPrepareTask: Task<Void, Error>?
    /// Voice whose files are downloading after the user picked it (Settings shows a spinner).
    private(set) var voiceDownloadID: String?
    /// Last voice download failure (Settings footer); cleared on the next pick.
    private(set) var voiceDownloadError: String?
    private var voiceChoiceToken = 0
    /// Set by `SpeechController`: may the local engine speak (and bake) these listen blocks?
    /// False when the article's effective language isn't supported by the engine (it then
    /// speaks with Apple). nil = always.
    var localLanguageGate: (([String]) -> Bool)?

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
        var voices: [SpeechEngineID: String] = [:]
        for d in engines.localDescriptors where !d.voices.isEmpty {
            // Stored voice if still offered (curated list), else the engine default.
            voices[d.id] = d.resolvedVoice(defaults.string(forKey: d.resolvedVoiceDefaultsKey))
        }
        var crashedID: SpeechEngineID?
        var crashNotice: String?
        var resume: ListenResumeTarget?
        var handledKokoroCrash = false
        let routeSettings = KokoroRouteSettings(defaults: defaults)
        let raw = defaults.string(forKey: Self.engineIDKey) ?? SpeechEngineID.apple.rawValue
        var initial = SpeechEngineID(rawValue: raw)
        // Retired engine selected (e.g. Chatterbox Nano) → its replacement if installed, else Apple.
        var retiredNotes: [String] = []
        for r in engines.retiredEngines where initial == r.id {
            let to: SpeechEngineID = engines.supports(r.replacement) && engines.isInstalled(r.replacement)
                ? r.replacement : .apple
            initial = to
            defaults.set(to.rawValue, forKey: Self.engineIDKey)
            retiredNotes.append("\(r.displayName) was selected → \(engines.displayName(to))")
        }
        if !engines.contains(initial) { initial = .apple }
        // Previous process died inside a crash-guarded engine call (e.g. Kokoro libBNNS SIGSEGV)?
        // (Pre-DI markers carry no engine id; only crash-guarded engines ever wrote them.)
        let legacyGuarded = engines.localDescriptors.first { $0.crashGuarded }?.id
        let crash = crashGuard.consumeCrashInfo(legacyEngine: legacyGuarded)
        if let crash, crash.engine == .kokoro, engines.supports(.kokoro) {
            // (d) Auto-recover: never silently leave Kokoro users on Apple after a crash.
            var onnxCount = routeSettings.onnxCrashCount
            let outcome = KokoroCrashRecovery.onCrash(
                route: crash.route.flatMap(KokoroRoute.init(rawValue:)), onnxCrashCount: &onnxCount)
            routeSettings.onnxCrashCount = onnxCount
            handledKokoroCrash = true
            crashNotice = KokoroCrashRecovery.notice(for: outcome)
            switch outcome {
            case .resumeOnONNX(let disableFastRoute):
                if disableFastRoute { routeSettings.fastGPURouteEnabled = false }
                initial = .kokoro
                defaults.set(SpeechEngineID.kokoro.rawValue, forKey: Self.engineIDKey)
                resume = ListenResumeTarget.forCrash(
                    article: crash.articleKey, paragraph: crash.paragraph, crashAt: crash.at,
                    playing: ListenResumePointStore.shared.load())
            case .fallBackToApple:
                let fallback = engines.crashFallback(for: .kokoro)
                initial = fallback
                defaults.set(fallback.rawValue, forKey: Self.engineIDKey)
                crashedID = .kokoro
            }
            ListenTimingLog.log("kokoro_auto_recover", [
                "route": crash.route ?? "legacy", "outcome": String(describing: outcome),
                "onnx_crashes": onnxCount, "resume_key": resume?.articleKey.prefix(8) ?? "",
                "resume_p": resume?.paragraph ?? -1, "auto_play": resume?.autoPlay ?? false,
            ])
            print("[TTS] Kokoro crash (route \(crash.route ?? "legacy")) → \(outcome)")
        } else if let crashed = crash?.engine, crashed == initial {
            let fallback = engines.crashFallback(for: crashed)
            initial = fallback
            defaults.set(fallback.rawValue, forKey: Self.engineIDKey)
            crashedID = crashed
            let d = engines.descriptor(crashed)
            let name = d?.shortName ?? crashed.rawValue
            crashNotice = "\(name) crashed last session (\(d?.crashNoticeDetail ?? "engine crash")). "
                + "Switched to \(engines.displayName(fallback)). Tap \(name) to try again."
            print("[TTS] \(name) crash detected → \(fallback.rawValue)")
        }
        // One-time (ONNX-main release): an earlier Core ML crash left Kokoro users on Apple
        // (Jimmy's phone: guard count 2, engine Apple). Bring them back to Kokoro on the stable
        // route, at the article/paragraph of that crash (opened paused).
        if !defaults.bool(forKey: Self.onnxMainMigrationKey) {
            defaults.set(true, forKey: Self.onnxMainMigrationKey)
            if !handledKokoroCrash, initial == .apple, engines.supports(.kokoro),
               let last = crashGuard.lastCrash, last.engine == .kokoro {
                initial = .kokoro
                defaults.set(SpeechEngineID.kokoro.rawValue, forKey: Self.engineIDKey)
                routeSettings.fastGPURouteEnabled = false
                routeSettings.onnxCrashCount = 0
                crashNotice = KokoroCrashRecovery.resumedNotice
                var target = ListenResumeTarget.forCrash(
                    article: last.articleKey, paragraph: last.paragraph, crashAt: last.at,
                    playing: ListenResumePointStore.shared.load())
                target?.autoPlay = false
                resume = target
                ListenTimingLog.log("kokoro_onnx_migration", [
                    "from": "apple", "resume_key": target?.articleKey.prefix(8) ?? "", "resume_p": target?.paragraph ?? -1,
                ])
            }
        }
        // Dev/test hook: `-selectEngine <engine id>` (persisted), e.g. local.kokoro.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-selectEngine"), i + 1 < args.count,
           engines.contains(SpeechEngineID(rawValue: args[i + 1])) {
            let forced = SpeechEngineID(rawValue: args[i + 1])
            initial = forced
            defaults.set(forced.rawValue, forKey: Self.engineIDKey)
            if forced == crashedID { crashNotice = nil; crashedID = nil }
        }
        selectedEngineID = initial
        engineVoices = voices
        crashedEngineID = crashedID
        engineCrashNotice = crashNotice
        pendingResume = resume
        if initial.isLocal, !engines.supports(initial) {
            selectedEngineID = .apple
            defaults.set(SpeechEngineID.apple.rawValue, forKey: Self.engineIDKey)
        } else if initial.isLocal {
            pendingEngineID = initial
            Task { await self.selectEngine(initial) }
        }
        synthQueue.attach(coordinator: self)
        // Nothing is playing at launch: per-chunk synth scratch from last session is disposable.
        self.audioCache.removeAllChunkScratch()
        ListenTimingLog.log("app_launch", [
            "engine": selectedEngineID.rawValue,
            "build": Self.buildConfiguration,
        ])
        cleanUpRetiredEngines(notes: retiredNotes)
        purgeStaleKokoroAudioOnce()
        // Best-effort ephemeral prune on launch (age 7d / 500MB). Survives leave-Reader + restart.
        let pruned = self.audioCache.pruneEphemeral()
        if pruned.removed > 0 {
            print("[TTSCache] pruned ephemeral removed=\(pruned.removed) freed=\(pruned.freedBytes)")
        }
    }

    /// One-time (per retired engine, idempotent): delete its cached article audio + index entries
    /// (bake marks recompute), orphan CAFs, and its model files. Logged with bytes freed to the
    /// listen debug log and `retired_engine_cleanup` in the timing log. Runs before any synth.
    private func cleanUpRetiredEngines(notes: [String]) {
        for note in notes { ListenDebugLog.shared.append("retired engine: \(note)") }
        for r in engines.retiredEngines where !defaults.bool(forKey: r.doneKey) {
            let cache = audioCache.purgeEngine(r.id.rawValue)
            let modelBytes = r.deleteFiles()
            defaults.set(true, forKey: r.doneKey)
            let total = cache.bytes + cache.orphanBytes + modelBytes
            ListenDebugLog.shared.append(
                "retired \(r.displayName): freed \(FileSizes.label(total)) (models \(FileSizes.label(modelBytes)), "
                + "cached audio \(cache.paragraphs) paragraphs in \(cache.articles) articles \(FileSizes.label(cache.bytes)), "
                + "orphan CAFs \(cache.orphanFiles) \(FileSizes.label(cache.orphanBytes)))")
            ListenTimingLog.log("retired_engine_cleanup", [
                "engine": r.id.rawValue, "model_bytes": modelBytes,
                "cache_articles": cache.articles, "cache_paragraphs": cache.paragraphs, "cache_bytes": cache.bytes,
                "orphan_files": cache.orphanFiles, "orphan_bytes": cache.orphanBytes, "total_bytes": total,
                "selection": notes.joined(separator: "; "),
            ])
            if cache.paragraphs > 0 || cache.orphanFiles > 0 { bakeMarksRevision &+= 1 }
        }
    }

    /// Bump when saved Kokoro audio must be re-rendered. v2 (2026-09-25): audio from before the
    /// ONNX NaN fix can contain full-scale pops + seconds of silence, has ≈0.8 s of dead air at
    /// every chunk join, and used the old chunk plan (mid-phrase cuts).
    static let kokoroAudioCacheVersion = 2
    static let kokoroAudioCacheVersionKey = "reader.tts.kokoro.audioCacheVersion"

    /// One-time: delete baked Kokoro paragraphs older than `kokoroAudioCacheVersion` (all
    /// articles; bake marks recompute). Launch-time, before any synth.
    private func purgeStaleKokoroAudioOnce() {
        guard defaults.integer(forKey: Self.kokoroAudioCacheVersionKey) < Self.kokoroAudioCacheVersion else { return }
        let r = audioCache.purgeEngine(SpeechEngineID.kokoro.rawValue)
        defaults.set(Self.kokoroAudioCacheVersion, forKey: Self.kokoroAudioCacheVersionKey)
        ListenTimingLog.log("kokoro_audio_cache_purge", [
            "version": Self.kokoroAudioCacheVersion, "articles": r.articles, "paragraphs": r.paragraphs,
            "bytes": r.bytes, "orphan_files": r.orphanFiles, "orphan_bytes": r.orphanBytes,
        ])
        ListenDebugLog.shared.append(
            "Kokoro audio cache v\(Self.kokoroAudioCacheVersion): removed \(r.paragraphs) saved paragraphs in \(r.articles) articles "
            + "(\(FileSizes.label(r.bytes + r.orphanBytes))); they re-render with the NaN fix + new chunking")
        if r.paragraphs > 0 || r.orphanFiles > 0 { bakeMarksRevision &+= 1 }
    }

    static var buildConfiguration: String {
        #if DEBUG
        return "debug"
        #else
        return "release"
        #endif
    }

    var usesLocalEngine: Bool { selectedEngineID.isLocal && localHostReady }
    var localEngineInstance: LocalModelSpeechEngine {
        if let localEngine { return localEngine }
        let engine = LocalModelSpeechEngine(engines: engines)
        engine.onModelProgress = { [weak self] fraction in
            guard let self, self.pendingEngineID != nil else { return }
            self.modelDownloadFraction = fraction
        }
        localEngine = engine
        return engine
    }

    /// Dismiss the one-line crash banner.
    func dismissCrashNotice() {
        engineCrashNotice = nil
    }

    /// Paragraph layout migration: the crash-resume target was read at init (before the saved
    /// rows were migrated), so its paragraph is in the old numbering — move it to the new one.
    func remapPendingResume(article: UUID, _ map: (Int) -> Int) {
        guard var target = pendingResume, target.matches(article) else { return }
        target.paragraph = map(target.paragraph)
        pendingResume = target
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
        guard let tag = localEngine?.liveRenderer(for: .kokoro)?.host.routeTag else { return nil }
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
        localPrepareTask?.cancel()
        localPrepareTask = nil
        localHostReady = false
        localEngine?.unloadHost()
        synthQueue.engineDidChange()
        if selectedEngineID == .kokoro || pendingEngineID == .kokoro {
            await selectEngine(.kokoro)
        }
    }

    // MARK: - SynthQueueContext (route-aware background)

    var activeRouteRendersInBackground: Bool { localEngine?.hostRendersInBackground ?? false }

    var backgroundRenderCacheKey: UUID? { localEngine?.playingArticleID }

    /// Local engine whose cache / chunk sizing applies right now (selected, else pending).
    var activeLocalEngineID: SpeechEngineID? {
        if selectedEngineID.isLocal { return selectedEngineID }
        if let pendingEngineID, pendingEngineID.isLocal { return pendingEngineID }
        return nil
    }

    /// Descriptor for cache keys / chunking: the active local engine, else the default local one.
    var activeDescriptor: EngineDescriptor? {
        engines.descriptor(activeLocalEngineID ?? engines.defaultLocalEngineID)
    }

    /// `ArticleAudioCache` engine key for the active local engine.
    var cacheEngineID: String { (activeLocalEngineID ?? engines.defaultLocalEngineID).rawValue }

    /// Chunk sizing for the active local engine.
    var activeChunkLimits: TextChunker.Limits { engines.limits(for: activeLocalEngineID ?? engines.defaultLocalEngineID) }

    var synthRenderer: SynthChunkRendering { localEngineInstance }

    /// Voice selected for a multi-voice engine (nil for single-voice engines).
    func voice(for id: SpeechEngineID) -> String? { engineVoices[id] }

    /// `ArticleAudioCache` voice key per the active engine's `CacheVoiceKeyStyle`
    /// (Kokoro: "kokoro.<voice>" — key format unchanged since the Kokoro release).
    func cacheVoiceID(appleVoice: String?) -> String {
        guard let id = activeLocalEngineID, let d = engines.descriptor(id) else { return appleVoice ?? "system" }
        return d.cacheVoiceID(engineVoice: engineVoices[id], appleVoice: appleVoice)
    }

    /// Map any stored/passed voice key onto the active engine's key space (pending BG jobs may
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
        BackgroundAudioBakeScheduler.shared.removePending(articleID: cacheKey)
    }

    /// True when a local model for `id` has been initialized (or its files are on disk).
    func isModelInstalled(_ id: SpeechEngineID) -> Bool {
        if localHostReady, selectedEngineID == id { return true }
        return engines.isInstalled(id)
    }

    func setVoice(_ voice: String, for id: SpeechEngineID) {
        guard let d = engines.descriptor(id), voice != engineVoices[id] else { return }
        engineVoices[id] = voice
        defaults.set(voice, forKey: d.resolvedVoiceDefaultsKey)
        guard activeLocalEngineID == id else { return }
        localEngineInstance.setActiveLocalEngine(id, voice: voice)
        synthQueue.engineDidChange()
        noteBakeMarksChanged()
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
    /// local engine's models stay loaded (the other host is dropped).
    func selectEngine(_ id: SpeechEngineID) async {
        guard id.isLocal else {
            pendingEngineID = nil
            localPrepareTask?.cancel()
            localPrepareTask = nil
            localHostReady = false
            modelDownloadFraction = nil
            applyEngineSelection(.apple)
            localEngine?.unloadHost()
            return
        }
        guard engines.supports(id) else {
            pendingEngineID = nil
            localHostReady = false
            applyEngineSelection(.apple)
            downloader.markFailed(engines.blockReason(id) ?? "\(engines.displayName(id)) is not available on this device.")
            return
        }
        if id == crashedEngineID {
            // Picking the engine again after a crash fallback = a fresh try.
            engineCrashNotice = nil
            crashedEngineID = nil
            if id == .kokoro { kokoroRouteSettings.onnxCrashCount = 0 }
        }
        let engineChanged = localEngine?.engineID != id || !selectedEngineID.isLocal || selectedEngineID != id
        if engineChanged {
            // Drop the other engine's in-flight prepare + host (memory) before warming this one.
            localPrepareTask?.cancel()
            localPrepareTask = nil
            localHostReady = false
        }
        pendingEngineID = id
        localEngineInstance.setActiveLocalEngine(id, voice: engineVoices[id])
        if engineChanged { synthQueue.engineDidChange() }
        downloader.markPreparing()
        modelDownloadFraction = nil
        do {
            try await ensureLocalPrepared()
            guard pendingEngineID == id || selectedEngineID == id else { return } // superseded
            localHostReady = true
            pendingEngineID = nil
            modelDownloadFraction = nil
            applyEngineSelection(id)
            downloader.stateHintInstalled()
            noteBakeMarksChanged()
            drainPendingIntoQueue()
        } catch is CancellationError {
            guard pendingEngineID == id else { return }
            localHostReady = false
            pendingEngineID = nil
            modelDownloadFraction = nil
            if selectedEngineID == id {
                applyEngineSelection(.apple)
            }
            downloader.cancel()
        } catch {
            guard pendingEngineID == id else { return }
            localHostReady = false
            pendingEngineID = nil
            modelDownloadFraction = nil
            applyEngineSelection(.apple)
            downloader.markFailed(friendlyLocalError(error, engine: id))
        }
    }

    func noteSpeakFailed(_ error: Error) {
        let engine = selectedEngineID
        localHostReady = false
        pendingEngineID = nil
        localPrepareTask = nil
        localEngine?.resetHostPrepared()
        applyEngineSelection(.apple)
        downloader.markFailed(friendlyLocalError(error, engine: engine))
    }

    func cancelDownload() {
        localPrepareTask?.cancel()
        localPrepareTask = nil
        downloader.cancel()
        modelDownloadFraction = nil
        if pendingEngineID != nil {
            pendingEngineID = nil
            localHostReady = false
            localEngine?.resetHostPrepared()
            if selectedEngineID.isLocal, !localHostReady {
                applyEngineSelection(.apple)
            }
        }
    }

    /// Delete one local engine's downloaded models (default: the active local engine).
    func deleteModel(_ engine: SpeechEngineID? = nil) throws {
        let id = engine ?? activeLocalEngineID ?? engines.defaultLocalEngineID
        let isActive = selectedEngineID == id || pendingEngineID == id
        if isActive {
            pendingEngineID = nil
            localPrepareTask?.cancel()
            localPrepareTask = nil
            localHostReady = false
            modelDownloadFraction = nil
            localEngine?.unloadHost()
        }
        downloader.cancel()
        try engines.deleteModels(id)
        downloader.resetToIdle()
        if selectedEngineID == id {
            applyEngineSelection(.apple)
        }
        noteBakeMarksChanged()
    }

    func hasListenAudio(for articleID: UUID) -> Bool {
        audioCache.hasCache(for: articleID)
    }

    func clearListenAudio(for articleID: UUID) throws {
        synthQueue.remove(cacheKey: articleID)
        try audioCache.deleteAudio(for: articleID)
        noteBakeMarksChanged()
        BackgroundAudioBakeScheduler.shared.removePending(articleID: articleID)
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

    /// Compatibility: demote is not cancel — use focusPlayhead / openArticle to reshuffle.
    /// Kept so call sites that previously cancelled bake for play can call `prioritizeListen` instead.
    func cancelBake(for articleID: UUID) {
        // No-op cancel of worker: reshuffle via focusPlayhead. Removing jobs would drop cache work.
        _ = articleID
    }

    // MARK: - Shared warm / queue reshuffle (Browse + Saved)

    /// Open/focus an article as queue #1 and bake from resume downward.
    /// Shared by Browse Reader and Offline — not separate bake stacks.
    func warmListenAudio(
        cacheKey: UUID,
        paragraphs: [String],
        rate: Float,
        voiceID: String,
        resumeParagraph: Int = 0,
        isEphemeral: Bool
    ) {
        guard !paragraphs.isEmpty, wantsLocalBake, localLanguageAllows(paragraphs) else { return }
        let voiceID = normalizedCacheVoice(voiceID)
        focusCacheKey = cacheKey
        guard usesLocalEngine, localHostReady else {
            BackgroundAudioBakeScheduler.shared.enqueuePending(
                articleID: cacheKey,
                paragraphs: paragraphs,
                rate: rate,
                voiceID: voiceID,
                plan: resumeParagraph <= 0
                    ? .topDown(paragraphCount: paragraphs.count)
                    : .fromPlayhead(resumeParagraph, paragraphCount: paragraphs.count)
            )
            BackgroundAudioBakeScheduler.shared.scheduleProcessingTask()
            print("[SynthQueue] queued pending key=\(cacheKey.uuidString.prefix(8)) (local engine cold); warming")
            Task { await self.warmLocalThenDrainPending() }
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
            rate: rate,
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
        rate: Float,
        voiceID: String,
        isEphemeral: Bool = false
    ) {
        guard !paragraphs.isEmpty, wantsLocalBake, localLanguageAllows(paragraphs) else { return }
        let voiceID = normalizedCacheVoice(voiceID)
        focusCacheKey = cacheKey
        if isEphemeral {
            audioCache.markEphemeral(cacheKey: cacheKey, lastAccess: Date())
        }
        if usesLocalEngine, localHostReady {
            synthQueue.openArticle(
                cacheKey: cacheKey,
                paragraphs: paragraphs,
                rate: rate,
                voiceID: voiceID,
                resumeParagraph: playhead,
                isEphemeral: isEphemeral
            )
            synthQueue.focusPlayhead(cacheKey: cacheKey, paragraph: playhead)
        } else {
            warmListenAudio(
                cacheKey: cacheKey,
                paragraphs: paragraphs,
                rate: rate,
                voiceID: voiceID,
                resumeParagraph: playhead,
                isEphemeral: isEphemeral
            )
        }
    }

    /// On article save: enqueue (demoted if something else is #1) top → down.
    func startBakeIfNeeded(articleID: UUID, paragraphs: [String], rate: Float, voiceID: String) {
        guard !paragraphs.isEmpty, wantsLocalBake, localLanguageAllows(paragraphs) else { return }
        let voiceID = normalizedCacheVoice(voiceID)
        audioCache.markSaved(cacheKey: articleID)
        BackgroundAudioBakeScheduler.shared.enqueuePending(
            articleID: articleID,
            paragraphs: paragraphs,
            rate: rate,
            voiceID: voiceID,
            plan: .topDown(paragraphCount: paragraphs.count)
        )
        BackgroundAudioBakeScheduler.shared.scheduleProcessingTask()
        guard usesLocalEngine, localHostReady else {
            Task { await self.warmLocalThenDrainPending() }
            return
        }
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
                rate: rate,
                voiceID: voiceID,
                resumeParagraph: 0,
                isEphemeral: false
            )
        } else {
            synthQueue.enqueueDemoted(
                cacheKey: articleID,
                paragraphs: paragraphs,
                rate: rate,
                voiceID: voiceID,
                isEphemeral: false
            )
        }
    }

    func prioritizeBake(
        articleID: UUID,
        from playhead: Int,
        paragraphs: [String],
        rate: Float,
        voiceID: String
    ) {
        prioritizeListen(
            cacheKey: articleID,
            playhead: playhead,
            paragraphs: paragraphs,
            rate: rate,
            voiceID: voiceID,
            isEphemeral: false
        )
    }

    func resumeGapFillBake(
        articleID: UUID,
        paragraphs: [String],
        rate: Float,
        voiceID: String
    ) {
        startBakeIfNeeded(articleID: articleID, paragraphs: paragraphs, rate: rate, voiceID: voiceID)
    }

    /// Persist a live-rendered unit (fallback path); prefer GlobalSynthQueue.store via worker.
    @discardableResult
    func persistRenderedUnit(
        articleID: UUID,
        paragraphIndex: Int,
        sourceURL: URL,
        duration: TimeInterval,
        rate: Float,
        voiceID: String,
        text: String? = nil
    ) throws -> URL {
        let url = try audioCache.storeParagraph(
            articleID: articleID,
            paragraphIndex: paragraphIndex,
            sourceURL: sourceURL,
            duration: duration,
            engineID: cacheEngineID,
            voiceID: voiceID,
            rate: rate,
            text: text
        )
        noteBakeMarksChanged()
        return url
    }

    /// Await Ready CAF via the global queue (playhead path).
    func ensureUnit(
        cacheKey: UUID,
        paragraphIndex: Int,
        text: String,
        rate: Float,
        voiceID: String,
        isEphemeral: Bool
    ) async throws -> URL {
        try await synthQueue.ensureUnit(
            cacheKey: cacheKey,
            paragraphIndex: paragraphIndex,
            text: text,
            rate: rate,
            voiceID: voiceID,
            isEphemeral: isEphemeral
        )
    }

    /// After Save: move ephemeral CAFs onto the SavedArticle UUID and reshuffle the queue key.
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
            // worker re-synthesizes them (crash 2026-09-24 22:00, p2 c0 rendered twice).
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
                    audioCache.stampMissingHashes(articleID: key, paragraphs: paragraphs)
                    ListenDebugLog.shared.append("identity adopt v1 \(legacy.uuidString.prefix(8)) → \(key.uuidString.prefix(8))")
                    print("[Identity] adopted legacy cache \(legacy.uuidString.prefix(8)) → \(key.uuidString.prefix(8))")
                } catch {
                    print("[Identity] legacy adopt failed: \(error.localizedDescription)")
                }
                break
            }
        }
        if let trustedParagraphs {
            audioCache.stampMissingHashes(articleID: key, paragraphs: trustedParagraphs)
        }
        // Giant paragraphs split since this audio was rendered (layout v3): keep the pieces
        // whose chunks line up with the old render, re-render the rest.
        let split = audioCache.remapSplitParagraphs(articleID: key, paragraphs: paragraphs) { self.chunkPlan(engineID: $0, text: $1) }
        let result = audioCache.reconcile(articleID: key, paragraphs: paragraphs)
        let msg = "identity \(key.uuidString.prefix(8)) fp=\(ArticleIdentity.contentFingerprint(paragraphs: paragraphs).prefix(8)) kept=\(result.kept) moved=\(result.remapped) dropped=\(result.dropped) legacy=\(result.unverified) split=\(split.splitParagraphs) sliced=\(split.sliced)"
        ListenDebugLog.shared.append(msg)
        print("[Identity] \(msg)")
        if result.changed { noteBakeMarksChanged() }
    }

    /// The render queue's chunk plan for `text` as rendered by `engineID` (nil if unknown engine).
    func chunkPlan(engineID: String, text: String) -> [String]? {
        guard let d = engines.descriptor(SpeechEngineID(rawValue: engineID)) else { return nil }
        return TextChunker.chunks(for: text, limits: d.limits)
    }

    /// Active plan description for diagnostics.
    var bakePlans: [UUID: BakePriorityPlan] {
        // Compatibility shim for Listen debug — reconstruct from queue primary only.
        var result: [UUID: BakePriorityPlan] = [:]
        if let key = synthQueue.primaryCacheKey,
           let desc = synthQueue.planDescription(for: key) {
            // Parse is lossy; expose via pending count in debug instead.
            _ = desc
            result[key] = .topDown(paragraphCount: 0)
        }
        return result
    }

    /// Bake only for engines that declare `supportsBakeCache` (Apple: no).
    private var wantsLocalBake: Bool {
        guard let id = activeLocalEngineID else { return false }
        return engines.descriptor(id)?.supportsBakeCache == true
    }

    private func warmLocalThenDrainPending() async {
        guard wantsLocalBake, let id = activeLocalEngineID else { return }
        if localHostReady {
            drainPendingIntoQueue()
            return
        }
        do {
            localEngineInstance.setActiveLocalEngine(id, voice: engineVoices[id])
            try await ensureLocalPrepared()
            guard activeLocalEngineID == id else { return }
            localHostReady = true
            pendingEngineID = nil
            modelDownloadFraction = nil
            applyEngineSelection(id)
            downloader.stateHintInstalled()
            drainPendingIntoQueue()
        } catch is CancellationError {
            print("[SynthQueue] warm cancelled")
        } catch {
            print("[SynthQueue] warm-then-drain failed: \(error.localizedDescription)")
        }
    }

    /// Persisted BG jobs → queue. The focused (active) article stays #1; see
    /// `GlobalSynthQueue.adoptPending`.
    private func drainPendingIntoQueue() {
        guard usesLocalEngine, localHostReady else { return }
        let pending = BackgroundAudioBakeScheduler.shared.pendingJobs()
            .filter { localLanguageAllows($0.paragraphs) }
        guard !pending.isEmpty else { return }
        print("[SynthQueue] draining \(pending.count) pending job(s)")
        synthQueue.adoptPending(pending.map { job in
            GlobalSynthQueue.PendingWork(
                cacheKey: job.articleID,
                paragraphs: job.paragraphs,
                rate: job.rate,
                voiceID: normalizedCacheVoice(job.voiceID),
                priorityStart: job.priorityStart,
                isEphemeral: audioCache.loadMeta(for: job.articleID)?.kind == .ephemeral
            )
        }, focusKey: focusCacheKey)
    }

    private func ensureLocalPrepared() async throws {
        if localHostReady { return }
        if let localPrepareTask {
            try await localPrepareTask.value
            return
        }
        let task = Task { @MainActor in
            try await self.localEngineInstance.prepareIfNeeded()
        }
        localPrepareTask = task
        do {
            try await task.value
            if localPrepareTask == task { localPrepareTask = nil }
        } catch {
            if localPrepareTask == task { localPrepareTask = nil }
            throw error
        }
    }

    private func applyEngineSelection(_ id: SpeechEngineID) {
        selectedEngineID = id
        defaults.set(id.rawValue, forKey: Self.engineIDKey)
    }

    private func friendlyLocalError(_ error: Error, engine: SpeechEngineID) -> String {
        let text = error.localizedDescription
        if let reason = engines.blockReason(engine) {
            return reason
        }
        if text.isEmpty {
            return "\(engines.displayName(engine)) failed to load. Tap to retry."
        }
        return "\(engines.shortName(engine)): \(text)"
    }
}
