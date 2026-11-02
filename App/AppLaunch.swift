import Foundation

/// Launch work, run once by `ReaderApp` when the first window appears: the library's launch
/// maintenance, the remembered surface (its folders checked, its page reloaded), the probe and diagnostics hooks from `LaunchOptions` (Debug builds), then crash
/// resume, then (Debug) a demo that plays at launch.
/// Views only render; nothing here waits on a view appearing in a particular order.
@MainActor
enum AppLaunch {
    private static var didRun = false

    static func run(library: LibraryStore, speech: SpeechController, shell: ShellState,
                    preparedAudio: PrepareCenter? = nil, follow: FollowCenter? = nil) async {
        guard !didRun else { return }
        didRun = true
        await launch(library: library, speech: speech, shell: shell, preparedAudio: preparedAudio, follow: follow)
    }

    /// The launch sequence `run` does once. `importFiles`: where book imports keep their files.
    /// Prepared audio and Follow's fetching carry on once the library's maintenance is done.
    static func launch(library: LibraryStore, speech: SpeechController, shell: ShellState,
                       preparedAudio: PrepareCenter? = nil, follow: FollowCenter? = nil,
                       importFiles: BookImportFiles = .standard) async {
        // No import is running yet: a book file a killed import left goes.
        importFiles.clearLeftovers()
        // The network monitor starts now, so its path is known before a model download asks.
        _ = NetworkPathStatus.shared
        #if DEBUG
        LaunchHooks.runBeforeMigrations(.current, library: library, tts: speech.localTTS)
        #endif

        maintainLibrary(library, tts: speech.localTTS)
        preparedAudio?.start()
        follow?.start()
        shell.restoreAtLaunch { library.folder(id: $0) != nil }

        #if DEBUG
        LaunchHooks.runAfterMigrations(.current, library: library, speech: speech, shell: shell)
        #endif

        resumeAfterCrash(library: library, speech: speech, shell: shell)
        if let preparedAudio { addWelcomeOnFreshInstall(library: library, speech: speech, shell: shell, preparedAudio: preparedAudio) }

        #if DEBUG
        await LaunchHooks.runAfterLaunch(.current, library: library, speech: speech, shell: shell, follow: follow,
                                           preparedAudio: preparedAudio)
        #endif
    }

    /// A fresh install gets the welcome article, with Listen open on it paused (`WelcomeArticle`).
    /// After crash resume, which has nothing to resume then: an install that has played before has
    /// pages, so it adds nothing. `-recordWelcome` adds it without its audio instead, to record it.
    private static func addWelcomeOnFreshInstall(library: LibraryStore, speech: SpeechController, shell: ShellState,
                                                 preparedAudio: PrepareCenter) {
        let welcome = WelcomeArticle(library: library, speech: speech, preparedAudio: preparedAudio, shell: shell)
        #if DEBUG
        if LaunchOptions.current.recordsWelcome { return welcome.record() }
        #endif
        welcome.addOnFreshInstall()
    }

    /// The library's launch maintenance, then the end of the render queue's launch hold: it
    /// adopts the saved bake jobs as this left them, and renders. Audio work an earlier launch
    /// left was finished before the first frame (`AppComposition.prepareAudioCache`), which
    /// started the hold.
    static func maintainLibrary(_ library: LibraryStore, tts: LocalTTSCoordinator) {
        // Copy saved articles and bookmarks without a receipt (layout pass and dedupe included).
        library.migrateLegacy()
        // Books stored without a record of their chapters get one, before anything can move
        // pages in or out of them (decision D19).
        library.recordBookChapters()
        #if DEBUG
        // After the copy, so no legacy row arrives after a seed; before the layout pass, so a
        // seeded page goes through it like a real one.
        LaunchHooks.runSeeds(.current, library: library)
        #endif
        // Listen blocks on an older layout: rebuilt, keeping position and usable audio. Then
        // duplicates merge, compared on the same paragraphs (so not if the layout pass couldn't
        // save: both run again next launch).
        if !library.migrateParagraphLayout().rolledBack { library.dedupe() }
        library.pruneUnsaved()
        library.retainRecent()
        tts.endLaunchHold()
    }

    /// An engine crashed last session: reopen the page in Listen at the paragraph that was
    /// playing, playing again if the crash just happened and the engine's recovery resumes
    /// (Kokoro, once on the ONNX route), else paused there; a pause for Retry says so. Runs after
    /// the layout migration, so the stored paragraph uses the current numbering.
    ///
    /// The paragraph counts only on a page holding the text it was played in (`LibraryStore.holds`):
    /// a key can hold other text by the time of the crash (the page was refreshed on open while an
    /// older session played on, a *Replace* brought another chapter back under it), and a
    /// paragraph of one text means nothing in another. A target that names no text (a crash
    /// marker's, or a resume file an older build wrote) counts only when it is the page's own
    /// stored paragraph. Otherwise the page opens paused at its own stored spot and keeps its own
    /// position. The position is the recorder's to store, from the session this binds.
    private static func resumeAfterCrash(library: LibraryStore, speech: SpeechController, shell: ShellState) {
        let tts = speech.localTTS
        if tts.isPausedForRetry, let engine = tts.launchCrash?.engine { speech.tellStopped(engine) }
        guard let target = tts.takePendingResume() else { return }
        guard let article = library.article(matching: target), article.hasText else {
            ListenTimingLog.log("kokoro_resume", ["ok": false, "why": "article not found", "key": String(target.articleKey.prefix(8))])
            return
        }
        let session = SpeechSession.article(article)
        let inText = target.text.map { library.holds(article, text: $0) } ?? (target.paragraph == article.positionParagraph)
        let p = inText ? min(max(0, target.paragraph), max(0, session.document.count - 1)) : article.positionParagraph
        let autoPlay = inText && target.autoPlay && !tts.isPausedForRetry
        if autoPlay {
            speech.start(session, at: ListenSpot(paragraph: p))
        } else {
            speech.prepare(session, at: ListenSpot(paragraph: p, utf16Offset: article.positionUTF16))
        }
        shell.showNowPlaying()
        ListenTimingLog.log("kokoro_resume", [
            "ok": true, "key": ListenTimingLog.shortKey(article.listenKey), "p": p, "auto_play": autoPlay,
            "text": inText ? "same" : target.text == nil ? "unknown" : "other",
        ])
    }
}
