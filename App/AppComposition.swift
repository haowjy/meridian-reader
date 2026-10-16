import Foundation
import SwiftData

/// Composition root. The ONLY place that knows which voice libraries exist: build the engine
/// registry from providers, then inject it (initializer injection) into the speech stack.
/// Exactly one SpeechController / LocalTTSCoordinator / local engine per process.
@MainActor
enum AppComposition {
    static let engineRegistry = EngineRegistry(providers: makeProviders())

    static let speechController: SpeechController = {
        #if DEBUG
        return SpeechController(localTTS: makeLocalTTS(selecting: LaunchOptions.current.selectsEngine))
        #else
        return SpeechController(localTTS: makeLocalTTS(selecting: nil))
        #endif
    }()

    /// The on-device engine's coordinator over the app's files (`AppDirectories`) and settings.
    private static func makeLocalTTS(selecting engine: SpeechEngineID?) -> LocalTTSCoordinator {
        LocalTTSCoordinator(engines: engineRegistry, defaults: .standard,
                            audioCache: ArticleAudioCache(root: AppDirectories.audioCache),
                            crashGuard: .shared,
                            pendingBakes: PendingBakeJobStore(storeURL: AppDirectories.pendingBakeJobs, defaults: .standard),
                            resumePoints: ListenResumePointStore(url: AppDirectories.listenResumePoint),
                            selecting: engine)
    }

    /// What you see. It asks the playback session what you hear, so the Reader of the playing
    /// page opens as Now Playing, and reopens on the surface you left (decision D10).
    static let shell = ShellState(isHearing: { speechController.playState(of: $0).isCurrent },
                                  memory: .standard, restores: restoresSurface)

    private static var restoresSurface: Bool {
        #if DEBUG
        return LaunchOptions.current.restoresSurface
        #else
        return true
        #endif
    }

    /// The listening position recorder (lives as long as the app).
    private static var progressRecorder: ListeningProgressRecorder?

    /// The library over `context`, connected to playback: deleting the playing page stops it
    /// first, and a merged page takes the live session's key with it while the kept page holds
    /// the text it plays (otherwise the session stops).
    static func makeLibrary(context: ModelContext) -> LibraryStore {
        let speech = speechController
        let library = LibraryStore(context: context, audio: speech.localTTS)
        library.stopPlaybackIfPlaying = { key in
            if speech.activeSessionID == key { speech.stop() }
        }
        library.keyMerged = { from, to, text in speech.rekeyActiveSession(from: from, to: to, text: text) }
        return library
    }

    /// Connects the speech stack to the library: books and series carry on through their
    /// chapters, and the recorder writes listening progress to it. Once, with the app's library.
    static func attachLibrary(_ library: LibraryStore) {
        guard progressRecorder == nil else { return }
        speechController.nextChapters = library
        progressRecorder = ListeningProgressRecorder(speech: speechController, library: library)
    }

    /// The reading appearance store (Settings › Reading and the Aa panel). A UI-test launch
    /// (`-uiTesting`) first clears what an earlier run stored for both appearance stores, so each
    /// test starts at the defaults; launch arguments (`-reading.theme sepia`) still apply over that.
    static func makeReadingAppearance() -> ReadingAppearance {
        #if DEBUG
        if LaunchOptions.current.uiTesting {
            for key in [AppAppearance.modeKey, AppAppearance.accentKey, ReadingAppearance.themeKey,
                        ReadingAppearance.fontKey, ReadingAppearance.textSizeKey, ReadingAppearance.lineSpacingKey] {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        #endif
        return ReadingAppearance(defaults: .standard)
    }

    /// Downloads (decision D16) over the app's library: a link page's text is fetched out of
    /// sight (`URLPageFetcher`) and saved through the one save path, which also queues its bake.
    /// It starts once the launch's library maintenance is done (`AppLaunch`).
    static func makeDownloads(library: LibraryStore) -> DownloadCenter {
        let speech = speechController
        #if DEBUG
        let fetcher = URLPageFetcher(schemeHandlers: TestPageSchemeHandler.handlers)
        #else
        let fetcher = URLPageFetcher()
        #endif
        return DownloadCenter(library: library, tts: speech.localTTS,
                              fetch: { try await fetcher.content(of: $0) },
                              save: { try ArticleSaveCoordinator(library: library, speech: speech).save($0) },
                              isListening: { speech.activeSessionID == $0 })
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
    /// (7 days, 500 MB; held audio excepted). First of all the cache is kept out of backups: it
    /// is audio the app can render again (`BackupExclusion`).
    static func prepareAudioCache(library: LibraryStore, tts: LocalTTSCoordinator, migrations: [LaunchMigration]) {
        tts.audioCache.excludeFromBackup()
        tts.holdRenderingForLaunch()
        library.finishAudioWork()
        for migration in migrations { migration.runIfNeeded(tts) }
        tts.audioCache.removeAllChunkScratch()
        let pruned = tts.audioCache.pruneEphemeral()
        if pruned.removed > 0 {
            ListenTimingLog.log("audio_cache_prune", ["removed": pruned.removed, "bytes": pruned.freedBytes])
        }
    }

    static func makeProviders() -> [SpeechEngineProvider] {
        #if DEBUG
        let options = LaunchOptions.current
        var providers: [SpeechEngineProvider] = [
            AppleSpeechProvider(),
            FluidAudioProvider(coreMLUnits: options.kokoroUnits),
        ]
        if options.usesTestVoice { providers.append(TestVoiceProvider(delay: options.testVoiceDelay ?? 0.15)) }
        return providers
        #else
        return [AppleSpeechProvider(), FluidAudioProvider()]
        #endif
    }

    /// Launch steps, in order: retired engines' cleanup, then each voice library's own.
    static func launchMigrations(for engines: EngineRegistry) -> [LaunchMigration] {
        #if DEBUG
        let keepsCoreMLStages = LaunchOptions.current.kokoroStress?.route == .coreml
        #else
        let keepsCoreMLStages = false
        #endif
        return engines.retiredEngines.map(RetiredEngineCleanup.init)
            + FluidAudioProvider.launchMigrations(keepingCoreMLStages: keepsCoreMLStages)
    }

    /// Launch housekeeping, in `ReaderApp.init`, before the first frame and before anything
    /// renders or plays: the audio cache's launch steps (`prepareAudioCache`, the voice
    /// libraries' included), the engines' downloads and the timing log kept out of backups, the
    /// background-GPU probe, and pruning Core ML's compiled-model cache of bundles from previous
    /// installs (once per install, background).
    static func runLaunchMaintenance(library: LibraryStore) {
        let tts = speechController.localTTS
        prepareAudioCache(library: library, tts: tts, migrations: launchMigrations(for: engineRegistry))
        for directory in engineRegistry.regenerableDirectories + [AppDirectories.listenTiming] {
            BackupExclusion.exclude(directory)
        }
        ListenTimingLog.log("app_launch", ["engine": tts.selectedEngineID.rawValue, "build": LocalTTSCoordinator.buildConfiguration])
        #if DEBUG
        // Debug probe: can this device get GPU time in background continued-processing tasks?
        CPURouteProbes.logAtLaunch()
        #endif
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
