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

    /// The library over `context`, connected to playback: deleting the playing page stops it
    /// first, and a page merged by dedupe takes the live session's key with it.
    static func makeLibrary(context: ModelContext) -> LibraryStore {
        let speech = speechController
        let library = LibraryStore(context: context, tts: speech.localTTS)
        library.stopPlaybackIfPlaying = { key in
            if speech.activeSessionID == key { speech.stop() }
        }
        library.keyMerged = { from, to in speech.rekeyActiveSession(from: from, to: to) }
        // Before the first frame: the start page's grid queries Favorites by its id.
        library.favorites()
        library.commit("favorites")
        return library
    }

    /// Connects the speech stack to the library: Now Playing's text is the playing page's, and
    /// the recorder writes listening progress to it. Once, with the app's library.
    static func attachLibrary(_ library: LibraryStore) {
        guard progressRecorder == nil else { return }
        speechController.contentResolver = library
        progressRecorder = ListeningProgressRecorder(speech: speechController, library: library)
    }

    /// The audio cache at launch, in order. First the render queue is held: it adopts no saved
    /// bake job and renders nothing until `AppLaunch.maintainLibrary` has also run the library's
    /// layout pass, dedupe and prune (`LocalTTSCoordinator.holdRenderingForLaunch`); the engine
    /// loads meanwhile. Then the recovery barrier: audio work an earlier launch saved but didn't
    /// finish (`LibraryStore.finishAudioWork`), so that nothing reads, cleans or renders a page's
    /// audio before it is where the library says; work that still can't finish holds the audio
    /// of the pages it touches, and work that can't be read holds all of it
    /// (`ArticleAudioCache.held`), for a later launch. Then the
    /// one-time launch migrations (which can purge an engine's audio and orphan files, held audio
    /// excepted), the chunk scratch (nothing plays at launch) and the prune of unsaved audio
    /// (7 days, 500 MB; held audio excepted).
    static func prepareAudioCache(library: LibraryStore, migrations: [LaunchMigration]) {
        let tts = library.tts
        tts.holdRenderingForLaunch()
        library.finishAudioWork()
        for migration in migrations { migration.runIfNeeded(tts) }
        tts.audioCache.removeAllChunkScratch()
        let pruned = tts.audioCache.pruneEphemeral()
        if pruned.removed > 0 {
            print("[TTSCache] pruned ephemeral removed=\(pruned.removed) freed=\(pruned.freedBytes)")
        }
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

    /// Launch housekeeping, in `ReaderApp.init`, before the first frame and before anything
    /// renders or plays: the audio cache's launch steps (`prepareAudioCache`), the background-GPU
    /// probe, and pruning Core ML's compiled-model cache of bundles from previous installs (once
    /// per install, background).
    static func runLaunchMaintenance(library: LibraryStore) {
        let tts = library.tts
        prepareAudioCache(library: library, migrations: launchMigrations(for: engineRegistry))
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
