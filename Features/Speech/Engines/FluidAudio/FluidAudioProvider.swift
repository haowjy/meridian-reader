import Foundation

/// Engine ids owned by the FluidAudio provider. Raw values are persisted (UserDefaults +
/// `TTSCache/*/index.json`) and must never change.
extension SpeechEngineID {
    /// Kokoro 82M, rendered on ONNX Runtime's CPU path; its article cache is "kokoro.<voice>".
    static let kokoro = SpeechEngineID("local.kokoro")
    /// Retired engine (Chatterbox Nano). Only the retirement cleanup uses it, to recognise its
    /// persisted selection, model files and cached audio.
    static let retiredChatterboxNano = SpeechEngineID("local.chatterbox-nano")
}

extension TextChunker.Limits {
    /// Kokoro's ONNX CPU route. Whole-paragraph profile like Phonon, but capped by Kokoro itself:
    /// ≈1.0–1.3 phonemes per char, a call holds at most 510 phonemes, `KokoroCPUHost.maxTokensPerCall` is 360, and ORT activation memory
    /// grows ≈1.3 MB/token (≈+380 MB at 300 tokens on the Mac). So hardMax stays 280 units: a
    /// paragraph ≤ 280 is one call (no short first clip); longer ones pack whole sentences up to
    /// 280 and only split a sentence longer than 280 (at clauses). TTFA on long openers is later
    /// by design (≈280 units ≈ 6–8 s render on iPhone 17 Pro). Deterministic per text.
    static let kokoroCPU = TextChunker.Limits(target: 280, hardMax: 280, firstTarget: 280, minResplit: 24,
                                              alwaysSplitFirst: false, secondTarget: nil)
}

/// FluidAudio adapter (vendored `Vendor/FluidAudio`, v0.16.1): registers Kokoro, rendered by
/// `KokoroCPUHost` (ONNX Runtime on the CPU, FluidAudio's English frontend without Core ML).
/// PocketTTS / Supertonic (also in FluidAudio) would be one more descriptor + host each here.
@MainActor
final class FluidAudioProvider: SpeechEngineProvider {
    let name = "FluidAudio"
    /// Route settings source (tests inject a suite).
    let routeSettings: KokoroRouteSettings

    init(routeSettings: KokoroRouteSettings = KokoroRouteSettings()) {
        self.routeSettings = routeSettings
    }

    /// Curated voices live in `KokoroVoiceCatalog` (one-line swaps).
    static var kokoroVoices: [EngineVoice] { KokoroVoiceCatalog.curated }

    /// ONNX Runtime on the CPU: no Core ML or BNNS (on iOS 26.4+ every Core ML routing of Kokoro
    /// can SIGSEGV in libBNNS, FluidAudio #844), and it keeps rendering in the background.
    static let kokoroDescriptor = EngineDescriptor(
        id: .kokoro,
        displayName: "Kokoro",
        shortName: "Kokoro",
        isRecommended: false,
        sortOrder: 20,
        voices: kokoroVoices,
        defaultVoiceID: KokoroVoiceCatalog.defaultVoice,
        voiceDefaultsKey: "reader.tts.kokoroVoice", // pre-DI key, keep
        hardware: HardwareRequirement(minimumOSMajor: 17, minimumChip: .a15, allowsSimulator: true,
                                      summary: "an iPhone 13 or newer"),
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
            isCrashGuarded: true)
    )

    var descriptors: [EngineDescriptor] { [Self.kokoroDescriptor] }

    /// Retired Chatterbox Nano: delete its ~750 MB of models and its cached article audio. Runs
    /// once (idempotent).
    var retiredEngines: [RetiredEngine] {
        [RetiredEngine(
            id: .retiredChatterboxNano,
            displayName: "Chatterbox Nano",
            doneKey: "reader.tts.retired.chatterboxNano.v1",
            deleteFiles: { Self.deleteRetiredNanoFiles() }
        )]
    }

    /// Kokoro's route knobs and ONNX crash count.
    var storedKeys: [String] { KokoroRouteSettings.storedKeys }

    /// FluidAudio's model cache (vocab, voice packs, G2P and lexicon) and the ONNX model's folder:
    /// all downloaded again when missing.
    var regenerableDirectories: [URL] {
        [KokoroAssets.fluidAudioDirectory, KokoroONNXModelStore.directory.deletingLastPathComponent()]
    }

    /// Kokoro's audio and model housekeeping; a Debug build also runs the CPU route's probes.
    var launchMigrations: [LaunchMigration] {
        var steps: [LaunchMigration] = [KokoroHeartPackInstall(), KokoroAudioCachePurge(), KokoroCoreMLStageCleanup()]
        #if DEBUG
        steps.append(CPURouteProbes())
        #endif
        return steps
    }

    // MARK: - Route knobs (Listen debug panel)

    /// Sets the ONNX threads in front; true when that changed them, and the live Kokoro host must
    /// be rebuilt (`LocalTTSCoordinator.reloadEngine`).
    func setCPUThreads(_ threads: Int) -> Bool {
        guard routeSettings.cpuThreads != threads else { return false }
        routeSettings.cpuThreads = threads
        ListenTimingLog.log("kokoro_threads_change", ["threads": routeSettings.cpuThreads])
        return true
    }

    func makeHost(for id: SpeechEngineID, voice: String?) -> LocalSynthHost? {
        guard id == .kokoro else { return nil }
        return KokoroCPUHost(voice: voice ?? KokoroVoiceCatalog.defaultVoice, threads: routeSettings.cpuThreads,
                             crashCount: routeSettings)
    }

    /// Kokoro crashed last session: `KokoroCrashRecovery` (resume on the ONNX route; pause for
    /// Retry after two ONNX crashes close together).
    func recover(from crash: EngineCrashGuard.CrashInfo, playing: ListenResumeTarget?) -> CrashRecovery? {
        guard crash.engine == .kokoro else { return nil }
        return KokoroCrashRecovery.recover(from: crash, playing: playing, settings: routeSettings)
    }

    func isInstalled(_ id: SpeechEngineID) -> Bool {
        id == .kokoro && KokoroCPUHost.filesLookInstalled
    }

    /// The ONNX model and FluidAudio's Kokoro dirs (vocab, voice packs, G2P, lexicon).
    func deleteModels(_ id: SpeechEngineID) throws {
        guard id == .kokoro else { return }
        KokoroAssets.clearCachedModels()
        KokoroONNXModelStore.shared.cancel()
        KokoroONNXModelStore.shared.delete()
    }

    /// Non-default Kokoro packs are fetched on first use (~0.5 MB); do it at select time so the
    /// first render doesn't wait on the network (and a failed prepare keeps the old voice).
    func prepareVoice(_ voice: String, for id: SpeechEngineID) async throws {
        guard id == .kokoro else { return }
        // Heart's pack ships in the app bundle; restore it even before the ONNX frontend is ready.
        if voice == KokoroVoiceCatalog.defaultVoice {
            KokoroAssets.installBundledHeartIfNeeded()
        }
        // Only once the frontend files exist; otherwise `prepare()` fetches the voice.
        guard KokoroAneCPUFrontendFiles.present else { return }
        try await KokoroAssets.ensureVoicePack(voice)
    }

    /// Whether `<voice>.bin` is on disk for Kokoro.
    func isVoicePackInstalled(_ voice: String, for id: SpeechEngineID) -> Bool {
        id == .kokoro && KokoroAssets.voicePackInstalled(voice)
    }

    /// Heart stays while it is the only curated pack on disk (or would leave the picker empty).
    /// Any other downloaded pack can be removed.
    func canDeleteVoicePack(_ voice: String, for id: SpeechEngineID) -> Bool {
        guard id == .kokoro, KokoroAssets.voicePackInstalled(voice) else { return false }
        if voice == KokoroVoiceCatalog.defaultVoice {
            return KokoroAssets.installedCuratedVoiceIDs().contains { $0 != voice }
        }
        return true
    }

    /// Remove one Kokoro voice pack. No-op when `canDeleteVoicePack` is false.
    func deleteVoicePack(_ voice: String, for id: SpeechEngineID) throws {
        guard canDeleteVoicePack(voice, for: id) else { return }
        _ = KokoroAssets.deleteVoicePack(voice)
        // Heart is re-seeded from the bundle if somehow wiped while still required.
        if voice != KokoroVoiceCatalog.defaultVoice {
            KokoroAssets.installBundledHeartIfNeeded()
        }
    }

    /// Everything Chatterbox Nano wrote outside the article cache: FluidAudio's model cache,
    /// Reader's model mirror (`TTSModels/chatterbox-nano`) and Nano probe outputs.
    /// Returns bytes freed.
    nonisolated static func deleteRetiredNanoFiles(fileManager fm: FileManager = .default) -> Int64 {
        let support = AppDirectories.applicationSupport
        var targets = [support.appendingPathComponent("fluidaudio/Models/chatterbox-nano", isDirectory: true),
                       support.appendingPathComponent("TTSModels/chatterbox-nano", isDirectory: true)]
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
