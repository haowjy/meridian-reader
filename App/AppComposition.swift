import Foundation

/// Composition root. The ONLY place that knows which voice libraries exist: build the engine
/// registry from providers, then inject it (initializer injection) into the speech stack.
/// Exactly one SpeechController / LocalTTSCoordinator / local engine per process.
@MainActor
enum AppComposition {
    static let engineRegistry = EngineRegistry(providers: makeProviders())

    static let speechController = SpeechController(engines: engineRegistry)

    static func makeProviders() -> [SpeechEngineProvider] {
        var providers: [SpeechEngineProvider] = [
            AppleSpeechProvider(),
            FluidAudioProvider(),
        ]
        #if canImport(Qwen3TTSCoreML)
        providers.append(SpeechSwiftProvider()) // speech-swift (Qwen3-TTS)
        #endif
        return providers
    }

    /// Launch housekeeping that isn't engine-specific: log the background-GPU probe, and prune Core
    /// ML's compiled-model cache of bundles from previous installs (once per install, background).
    static func runLaunchMaintenance() {
        // Debug probe: can this device get GPU time in background continued-processing tasks?
        CPURouteProbes.logAtLaunch()
        // Kokoro runs on the ONNX CPU route: drop the unused Core ML stages (≈82 MB) unless the
        // debug fast GPU route is on. Vocab, voice packs, G2P and lexicon stay.
        DispatchQueue.global(qos: .utility).async {
            let freed = FluidAudioProvider.cleanUpUnusedCoreMLStages()
            guard freed > 0 else { return }
            ListenTimingLog.log("kokoro_coreml_cleanup", ["bytes": freed])
            DispatchQueue.main.async {
                ListenDebugLog.shared.append("Kokoro Core ML stages removed (ONNX route): freed \(FileSizes.label(freed))")
            }
        }
        CoreMLCompileCacheJanitor.runOncePerInstall { report in
            guard let r = report else { return }
            ListenTimingLog.log("coreml_cache_prune", [
                "removed": r.bundlesRemoved, "kept": r.bundlesKept, "bytes": r.bytesFreed,
            ])
            DispatchQueue.main.async {
                ListenDebugLog.shared.append(
                    "Core ML compile cache: removed \(r.bundlesRemoved) stale bundles, freed \(FileSizes.label(r.bytesFreed)) (kept \(r.bundlesKept))")
            }
        }
    }
}
