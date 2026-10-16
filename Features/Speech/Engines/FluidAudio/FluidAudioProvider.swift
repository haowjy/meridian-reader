import Foundation

/// Engine ids owned by the FluidAudio provider. Raw values are persisted (UserDefaults +
/// `TTSCache/*/index.json`) and must never change.
extension SpeechEngineID {
    /// Kokoro 82M — the on-device engine. One id for both routes (ONNX CPU default, Core ML
    /// debug opt-in), so the article cache ("kokoro.<voice>") is shared between them.
    static let kokoro = SpeechEngineID("local.kokoro")
    /// Retired engine (Chatterbox Nano). Only the retirement cleanup uses it, to recognise its
    /// persisted selection, model files and cached audio.
    static let retiredChatterboxNano = SpeechEngineID("local.chatterbox-nano")
}

/// FluidAudio adapter (vendored `Vendor/FluidAudio`, v0.16.1): registers Kokoro.
/// PocketTTS / Supertonic (also in FluidAudio) would be one more descriptor + host each here.
///
/// Kokoro has two routes behind the one engine (`KokoroRouteSettings.route`):
/// - ONNX CPU (`KokoroCPUHost`, default): ONNX Runtime + FluidAudio's frontend without Core ML.
/// - Core ML (`KokoroSplitHost`, debug toggle "Kokoro fast GPU route (may crash on iOS 26.4+)"):
///   Core ML in front, ONNX CPU from the first background call on.
@MainActor
final class FluidAudioProvider: SpeechEngineProvider {
    let name = "FluidAudio"
    /// Route settings source (tests inject a suite).
    let routeSettings: KokoroRouteSettings
    /// Compute units of the Core ML route's host (`KokoroHost.unitsLabel`); nil: its default.
    let coreMLUnits: String?

    init(routeSettings: KokoroRouteSettings = KokoroRouteSettings(), coreMLUnits: String? = nil) {
        self.routeSettings = routeSettings
        self.coreMLUnits = coreMLUnits
    }

    /// Curated voices live in `KokoroVoiceCatalog` (one-line swaps).
    static var kokoroVoices: [EngineVoice] { KokoroVoiceCatalog.curated }

    /// Default route: ONNX Runtime CPU (no Core ML/BNNS, keeps rendering in the background).
    /// The Core ML route is a debug opt-in: on iOS 26.4+ every Core ML routing can SIGSEGV in
    /// libBNNS (FluidAudio #844).
    static let kokoroDescriptor = EngineDescriptor(
        id: .kokoro,
        displayName: "Kokoro (on-device)",
        shortName: "Kokoro",
        subtitle: "Recommended, ~175 MB download",
        isRecommended: true,
        sortOrder: 10,
        voices: kokoroVoices,
        defaultVoiceID: KokoroVoiceCatalog.defaultVoice,
        voiceDefaultsKey: "reader.tts.kokoroVoice", // pre-DI key, keep
        hardware: HardwareRequirement(minimumOSMajor: 17, minimumChip: .a15, allowsSimulator: true,
                                      summary: "iPhone 13 or newer (A15+)"),
        // Reader loads FluidAudio's `.english` variant only: Misaki US lexicon + BART G2P
        // fallback. British packs (bf_/bm_) change the timbre, not the pronunciation.
        // FluidAudio also has separate Mandarin/Japanese Kokoro variants (other model bundles,
        // not wired up here).
        supportedLanguages: ["en"],
        onDevice: OnDeviceTraits(
            cacheVoicePrefix: "kokoro", // "kokoro.af_heart" (existing caches)
            // Chunks ≤ 280 units; a call over `KokoroCPUHost.maxTokensPerCall` throws
            // inputTooLong and the renderer re-splits.
            limits: .kokoroCPU,
            crashNotice: "Kokoro stopped unexpectedly")
    )

    var descriptors: [EngineDescriptor] { [Self.kokoroDescriptor] }

    /// Retired Chatterbox Nano: move its users to Kokoro (if installed) or Apple, delete its
    /// ~750 MB of models and its cached article audio. Runs once (idempotent).
    var retiredEngines: [RetiredEngine] {
        [RetiredEngine(
            id: .retiredChatterboxNano,
            displayName: "Chatterbox Nano",
            doneKey: "reader.tts.retired.chatterboxNano.v1",
            replacement: .kokoro,
            deleteFiles: { Self.deleteRetiredNanoFiles() }
        )]
    }

    /// FluidAudio's model cache (vocab, voice packs, G2P and lexicon; the Core ML stages on the
    /// debug route) and the ONNX model's folder: all downloaded again when missing.
    var regenerableDirectories: [URL] {
        [KokoroAssets.fluidAudioDirectory, KokoroONNXModelStore.directory.deletingLastPathComponent()].compactMap { $0 }
    }

    /// Kokoro's launch steps, run by `AppComposition.prepareAudioCache`. `keepingCoreMLStages`:
    /// a Core ML stress run (`-KokoroStress coreml`) loads the stages itself.
    static func launchMigrations(keepingCoreMLStages: Bool = false) -> [LaunchMigration] {
        [KokoroAudioCachePurge(), KokoroONNXMainMigration()]
            + (keepingCoreMLStages ? [] : [KokoroCoreMLStageCleanup()])
    }

    // MARK: - Route knobs (Listen debug panel)

    /// Turns the Core ML route on or off; true when that changed the route, and the live Kokoro
    /// host must be rebuilt (`LocalTTSCoordinator.reloadEngine`).
    func setFastGPURoute(_ on: Bool) -> Bool {
        guard routeSettings.fastGPURouteEnabled != on else { return false }
        routeSettings.fastGPURouteEnabled = on
        ListenTimingLog.log("kokoro_route_change", ["route": routeSettings.route.rawValue])
        return true
    }

    /// Sets the ONNX threads in front; true when that changed them (rebuild the live host).
    func setCPUThreads(_ threads: Int) -> Bool {
        guard routeSettings.cpuThreads != threads else { return false }
        routeSettings.cpuThreads = threads
        ListenTimingLog.log("kokoro_threads_change", ["threads": routeSettings.cpuThreads])
        return true
    }

    func makeHost(for id: SpeechEngineID, voice: String?) -> LocalSynthHost? {
        guard id == .kokoro else { return nil }
        let voice = voice ?? KokoroHost.defaultVoice
        switch routeSettings.route {
        case .onnxCPU: return KokoroCPUHost(voice: voice, threads: routeSettings.cpuThreads, crashCount: routeSettings)
        case .coreMLGPU:
            return KokoroSplitHost(
                coreML: KokoroHost(voice: voice, unitsLabel: coreMLUnits),
                onnx: KokoroCPUHost(voice: voice, threads: routeSettings.cpuThreads, crashCount: routeSettings))
        }
    }

    /// Kokoro crashed last session: `KokoroCrashRecovery` (resume on the ONNX route; Apple after
    /// two ONNX crashes close together).
    func recover(from crash: EngineCrashGuard.CrashInfo, playing: ListenResumeTarget?) -> CrashRecovery? {
        guard crash.engine == .kokoro else { return nil }
        return KokoroCrashRecovery.recover(from: crash, playing: playing, settings: routeSettings)
    }

    /// Picking Kokoro again after the crash fallback starts a fresh ONNX crash count.
    func crashRetried(_ id: SpeechEngineID) {
        if id == .kokoro { routeSettings.onnxCrashCount = 0 }
    }

    func isInstalled(_ id: SpeechEngineID) -> Bool {
        guard id == .kokoro else { return false }
        switch routeSettings.route {
        case .onnxCPU: return KokoroCPUHost.filesLookInstalled
        case .coreMLGPU: return KokoroAssets.coreMLStagesLookInstalled && KokoroCPUHost.filesLookInstalled
        }
    }

    /// Both routes' files: the ONNX model and FluidAudio's Kokoro dirs (Core ML stages, vocab,
    /// voice packs, G2P, lexicon).
    func deleteModels(_ id: SpeechEngineID) throws {
        guard id == .kokoro else { return }
        KokoroAssets.clearCachedModels()
        KokoroONNXModelStore.shared.cancel()
        KokoroONNXModelStore.shared.delete()
    }

    /// Non-default Kokoro packs are fetched on first use (~0.5 MB); do it at select time so the
    /// first render doesn't wait on the network (and a failed download keeps the old voice).
    func prepareVoice(_ voice: String, for id: SpeechEngineID) async throws {
        guard id == .kokoro else { return }
        switch routeSettings.route {
        case .onnxCPU:
            // Only once the frontend files exist; otherwise `prepare()` fetches the voice.
            guard KokoroAneCPUFrontendFiles.present else { return }
            try await KokoroAssets.ensureVoicePack(voice)
        case .coreMLGPU:
            // Before the Core ML models are downloaded there's nothing to add to: `prepare()`
            // preloads the selected voice.
            guard KokoroAssets.repoDirectoryExists else { return }
            try await KokoroAssets.ensureVoicePack(voice)
        }
    }

    /// Everything Chatterbox Nano wrote outside the article cache: FluidAudio's model cache,
    /// Reader's model mirror (`TTSModels/chatterbox-nano`) and Nano probe outputs.
    /// Returns bytes freed.
    nonisolated static func deleteRetiredNanoFiles(fileManager fm: FileManager = .default) -> Int64 {
        var targets: [URL] = []
        if let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            targets.append(support.appendingPathComponent("fluidaudio/Models/chatterbox-nano", isDirectory: true))
            targets.append(support.appendingPathComponent("TTSModels/chatterbox-nano", isDirectory: true))
        }
        if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first,
           let items = try? fm.contentsOfDirectory(atPath: docs.path) {
            targets += items.filter { $0.hasPrefix("nano_") }.map { docs.appendingPathComponent($0) }
        }
        var freed: Int64 = 0
        for url in targets where fm.fileExists(atPath: url.path) {
            let bytes = FileSizes.allocatedBytes(at: url, fileManager: fm)
            if (try? fm.removeItem(at: url)) != nil { freed += bytes }
        }
        return freed
    }
}
