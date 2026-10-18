import Foundation
import SwiftData
import WebKit

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

    /// Follow over the app's library: every page fetched out of sight goes through one
    /// `FetchQueue` (a Debug build also serves the offline `reader-test://` pages there); a
    /// chapter ▶ waited for plays from its spot once its text is in. It starts once the launch's
    /// library maintenance is done (`AppLaunch`).
    static func makeFollow(library: LibraryStore) -> FollowCenter {
        let speech = speechController
        #if DEBUG
        let queue = FetchQueue(schemeHandlers: TestPageSchemeHandler.handlers)
        #else
        let queue = FetchQueue()
        #endif
        return FollowCenter(library: library, queue: queue, playingKey: { speech.activeSessionID },
                            startPlayback: { speech.start(.page($0), at: $0.listenStart) })
    }

    /// Block Ads over the bundled list (`BundledRuleList`), in WebKit's default rule-list store: every
    /// web view the app makes from here on gets it (`WKWebViewConfiguration.appWebView`). Once, at
    /// launch, before the first web view: the browser's restored page loads with the list when its
    /// lookup has finished by then.
    static func makeContentBlocker() -> ContentBlocker {
        let blocker = ContentBlocker(provider: BundledRuleList(store: .default()), defaults: .standard)
        WKWebViewConfiguration.appContentBlocker = blocker
        return blocker
    }

    /// Downloads (decision D16) over the app's library: a link page's text comes through Follow
    /// (`FollowCenter.fill`), so it is fetched once and in the one queue. It starts once the
    /// launch's library maintenance is done (`AppLaunch`).
    static func makeDownloads(library: LibraryStore, follow: FollowCenter) -> DownloadCenter {
        let speech = speechController
        return DownloadCenter(library: library, tts: speech.localTTS,
                              fill: { await follow.fill($0, priority: .background) },
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
    /// launch steps (`EngineRegistry.launchMigrations`, which can purge an engine's audio and
    /// orphan files, held audio excepted), the chunk scratch (nothing plays at launch) and the
    /// prune of unsaved audio (7 days, 500 MB; held audio excepted). First of all the cache is kept
    /// out of backups: it is audio the app can render again (`BackupExclusion`).
    static func prepareAudioCache(library: LibraryStore, tts: LocalTTSCoordinator) {
        tts.audioCache.excludeFromBackup()
        tts.holdRenderingForLaunch()
        library.finishAudioWork()
        for migration in tts.engines.launchMigrations { migration.runIfNeeded(tts) }
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
            FluidAudioProvider(coreMLUnits: options.kokoroUnits,
                               keepsCoreMLStages: options.kokoroStress?.route == .coreml),
        ]
        if options.usesTestVoice { providers.append(TestVoiceProvider()) }
        return providers
        #else
        return [AppleSpeechProvider(), FluidAudioProvider()]
        #endif
    }

    /// Launch housekeeping, in `ReaderApp.init`, before the first frame and before anything
    /// renders or plays: the audio cache's launch steps (`prepareAudioCache`, the voice
    /// libraries' included), then the engines' downloads and the timing log kept out of backups.
    static func runLaunchMaintenance(library: LibraryStore) {
        let tts = speechController.localTTS
        prepareAudioCache(library: library, tts: tts)
        for directory in engineRegistry.regenerableDirectories + [AppDirectories.listenTiming] {
            BackupExclusion.exclude(directory)
        }
        ListenTimingLog.log("app_launch", ["engine": tts.selectedEngineID.rawValue, "build": LocalTTSCoordinator.buildConfiguration])
    }
}
