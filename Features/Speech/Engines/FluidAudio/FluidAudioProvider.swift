import Foundation

/// Engine ids owned by the FluidAudio provider. Raw values are persisted (UserDefaults +
/// `TTSCache/*/index.json`) and must never change.
extension SpeechEngineID {
    /// Kokoro 82M — the on-device engine. One id for both routes (ONNX CPU default, Core ML
    /// debug opt-in), so the article cache ("kokoro.<voice>") is shared between them.
    static let kokoro = SpeechEngineID("local.kokoro")
    /// Chatterbox Nano — removed from Reader (2026-09-24). Kept only so the retirement cleanup can
    /// recognise its persisted selection, model files and cached audio.
    static let retiredChatterboxNano = SpeechEngineID("local.chatterbox-nano")
}

/// FluidAudio adapter (vendored `Vendor/FluidAudio`, v0.16.1): registers Kokoro.
/// PocketTTS / Supertonic (also in FluidAudio) would be one more descriptor + host each here.
///
/// Kokoro has two routes behind the one engine (`KokoroRouteSettings.route`):
/// - ONNX CPU (`KokoroCPUHost`, default): ONNX Runtime + FluidAudio's frontend without Core ML.
/// - Core ML GPU (`KokoroHost`, debug toggle "Kokoro fast GPU route (may crash on iOS 26.4+)").
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

    static let kokoroDescriptor = EngineDescriptor(
        id: .kokoro,
        providerName: "FluidAudio",
        kind: .onDevice,
        displayName: "Kokoro (on-device)",
        shortName: "Kokoro",
        subtitle: "Recommended · ~175 MB download",
        isRecommended: true,
        sortOrder: 10,
        voices: kokoroVoices,
        defaultVoiceID: KokoroVoiceCatalog.defaultVoice,
        voiceDefaultsKey: "reader.tts.kokoroVoice", // pre-DI key, keep
        cacheVoiceKey: .prefixed("kokoro"),          // "kokoro.af_heart" (existing caches)
        streaming: .wholeCall,
        limits: .kokoroCPU,
        limitNotes: "Model cap ≤510 IPA phonemes per call; the ONNX CPU route sizes chunks to ≈200 tokens "
            + "(hardMax 200 at ≈1.0 phoneme/char) to bound ORT memory, with a short first chunk (≤80) for fast "
            + "first audio. >240 tokens → inputTooLong → re-split.",
        assets: [
            .init(name: "Kokoro-82M ONNX fp16 (onnx-community/Kokoro-82M-v1.0-ONNX)", approxBytes: 163_234_740,
                  source: "hf:onnx-community/Kokoro-82M-v1.0-ONNX"),
            .init(name: "G2P encoder/decoder weights (read by Swift, not Core ML)", approxBytes: 1_600_000,
                  source: "hf:FluidInference/kokoro-82m-coreml"),
            .init(name: "us_lexicon_cache.json", approxBytes: 10_400_000, source: "hf:FluidInference/kokoro-82m-coreml"),
            .init(name: "vocab.json + voice packs (0.5 MB each)", approxBytes: 600_000, source: "hf:FluidInference/kokoro-82m-coreml"),
        ],
        approxDownloadBytes: 176_000_000,
        hardware: HardwareRequirement(minimumOSMajor: 17, minimumChip: .a15, allowsSimulator: true,
                                      summary: "iPhone 13 / recent iPad (A15+)"),
        computeRouting: "onnxCPU (debug: Core ML \(KokoroHost.defaultUnitsLabel))",
        quirks: [
            "Default route: ONNX Runtime CPU — no Core ML/BNNS, renders in the background.",
            "iOS 26.4+: every Core ML routing can SIGSEGV in libBNNS (#844); the Core ML route is a debug opt-in.",
            "Output is deterministic; seed ignored.",
        ],
        supportsBakeCache: true,
        crashGuarded: true,
        crashNoticeDetail: "Kokoro stopped unexpectedly",
        // Reader loads FluidAudio's `.english` variant only: Misaki US lexicon + BART G2P
        // fallback. British packs (bf_/bm_) change the timbre, not the pronunciation.
        // FluidAudio also has separate Mandarin/Japanese Kokoro variants (other model bundles,
        // not wired up here).
        supportedLanguages: ["en"]
    )

    var descriptors: [EngineDescriptor] { [Self.kokoroDescriptor] }

    /// Chatterbox Nano was removed: move its users to Kokoro (if installed) or Apple, delete its
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

    func makeHost(for id: SpeechEngineID, voice: String?) -> LocalSynthHost? {
        guard id == .kokoro else { return nil }
        let voice = voice ?? KokoroHost.defaultVoice
        switch routeSettings.route {
        case .onnxCPU: return KokoroCPUHost(voice: voice, threads: routeSettings.cpuThreads)
        case .coreMLGPU: return KokoroHost(voice: voice)
        }
    }

    func isInstalled(_ id: SpeechEngineID) -> Bool {
        guard id == .kokoro else { return false }
        switch routeSettings.route {
        case .onnxCPU: return KokoroCPUHost.filesLookInstalled
        case .coreMLGPU: return KokoroHost.modelsLookInstalled
        }
    }

    /// Both routes' files: the ONNX model and FluidAudio's Kokoro dirs (Core ML stages, vocab,
    /// voice packs, G2P, lexicon).
    func deleteModels(_ id: SpeechEngineID) throws {
        guard id == .kokoro else { return }
        KokoroHost.clearCachedModels()
        CPURouteModelStore.shared.cancel()
        CPURouteModelStore.shared.delete()
    }

    /// Non-default Kokoro packs are fetched on first use (~0.5 MB); do it at select time so the
    /// first render doesn't wait on the network (and a failed download keeps the old voice).
    func prepareVoice(_ voice: String, for id: SpeechEngineID) async throws {
        guard id == .kokoro else { return }
        switch routeSettings.route {
        case .onnxCPU:
            // Only once the frontend files exist; otherwise `prepare()` fetches the voice.
            guard KokoroAneCPUFrontendFiles.present else { return }
            try await KokoroCPUHost.ensureVoicePackFile(voice)
        case .coreMLGPU:
            try await KokoroHost.ensureVoicePack(voice)
        }
    }

    /// One-time-per-state cleanup: with the fast GPU route off, the 7 Kokoro Core ML stages
    /// (≈82 MB) are dead weight — the ONNX route needs only vocab, voice packs and the G2P /
    /// lexicon files next to them. Re-downloaded automatically if the debug route is turned on.
    /// Returns bytes freed (0 if nothing to do).
    @discardableResult
    nonisolated static func cleanUpUnusedCoreMLStages(settings: KokoroRouteSettings = KokoroRouteSettings()) -> Int64 {
        guard !settings.fastGPURouteEnabled else { return 0 }
        return KokoroHost.deleteCoreMLStages()
    }

    /// Everything Chatterbox Nano ever wrote outside the article cache: FluidAudio's model cache,
    /// the Phase-0 Reader mirror (`TTSModels/chatterbox-nano`) and old Nano probe outputs.
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
