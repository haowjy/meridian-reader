import Foundation
import SwiftData

/// Composition root. The ONLY place that knows which voice libraries exist: build the engine
/// registry from providers, then inject it (initializer injection) into the speech stack.
/// Exactly one SpeechController / LocalTTSCoordinator / local engine per process.
@MainActor
enum AppComposition {
    static let engineRegistry = EngineRegistry(providers: makeProviders())

    static let speechController = SpeechController(engines: engineRegistry)

    /// What you see. It asks the playback session what you hear, so the Reader of the playing
    /// page opens as Now Playing.
    static let shell = ShellState(isHearing: { speechController.playState(of: $0).isCurrent })

    /// The listening position recorder (lives as long as the app).
    private static var progressRecorder: ListeningProgressRecorder?

    /// Connects the speech stack to the saved-article store: where Now Playing's text comes from,
    /// and where listening positions are written. Once, with the app's main context.
    static func attachLibrary(_ context: ModelContext) {
        guard progressRecorder == nil else { return }
        speechController.contentResolver = SavedArticleContentResolver(context: context)
        progressRecorder = ListeningProgressRecorder(speech: speechController,
                                                     store: SavedArticleProgressStore(context: context))
    }

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

    /// One-time launch steps, in order: retired engines' cleanup, then each voice library's own.
    static func launchMigrations(for engines: EngineRegistry) -> [LaunchMigration] {
        engines.retiredEngines.map(RetiredEngineCleanup.init) + FluidAudioProvider.launchMigrations
    }

    /// Launch housekeeping, before anything renders or plays: the one-time launch migrations, the
    /// audio cache's per-launch cleanup, the background-GPU probe, and pruning Core ML's
    /// compiled-model cache of bundles from previous installs (once per install, background).
    static func runLaunchMaintenance() {
        let tts = speechController.localTTS
        for migration in launchMigrations(for: engineRegistry) { migration.runIfNeeded(tts) }
        // Nothing is playing at launch: per-chunk synth scratch from last session is disposable.
        tts.audioCache.removeAllChunkScratch()
        // Unsaved reader audio: prune by age (7 days) / size (500 MB).
        let pruned = tts.audioCache.pruneEphemeral()
        if pruned.removed > 0 {
            print("[TTSCache] pruned ephemeral removed=\(pruned.removed) freed=\(pruned.freedBytes)")
        }
        ListenTimingLog.log("app_launch", ["engine": tts.selectedEngineID.rawValue, "build": LocalTTSCoordinator.buildConfiguration])
        #if DEBUG
        // Debug probe: can this device get GPU time in background continued-processing tasks?
        CPURouteProbes.logAtLaunch()
        #endif
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
