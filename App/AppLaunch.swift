import Foundation

/// Launch work, run once by `ReaderApp` when the first window appears: the library's launch
/// maintenance, the UI-test / diagnostics hooks from `LaunchOptions` (Debug builds), then crash
/// resume.
/// Views only render; nothing here waits on a view appearing in a particular order.
@MainActor
enum AppLaunch {
    private static var didRun = false

    static func run(library: LibraryStore, speech: SpeechController, shell: ShellState) async {
        guard !didRun else { return }
        didRun = true
        #if DEBUG
        LaunchHooks.runBeforeMigrations(.current, library: library, tts: speech.localTTS)
        #endif

        maintainLibrary(library)

        #if DEBUG
        LaunchHooks.runAfterMigrations(.current, library: library, speech: speech, shell: shell)
        #endif

        await resumeAfterCrash(library: library, speech: speech, shell: shell)
    }

    /// The library's launch maintenance, then the end of the render queue's launch hold: it
    /// adopts the saved bake jobs as this left them, and renders. Audio work an earlier launch
    /// left was finished before the first frame (`AppComposition.prepareAudioCache`), which
    /// started the hold.
    static func maintainLibrary(_ library: LibraryStore) {
        // Copy saved articles and bookmarks without a receipt (layout pass and dedupe included).
        library.migrateLegacy()
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
        library.tts.endLaunchHold()
    }

    /// Kokoro crashed last session: reopen the page in Now Playing at the paragraph that was
    /// playing — playing again (on the ONNX route, once it's loaded) if the crash just happened,
    /// else paused there. Runs after the layout migration, so the stored paragraph uses the
    /// current numbering.
    private static func resumeAfterCrash(library: LibraryStore, speech: SpeechController, shell: ShellState) async {
        let tts = speech.localTTS
        guard let target = tts.takePendingResume() else { return }
        guard let page = library.page(matching: target), page.hasText else {
            ListenTimingLog.log("kokoro_resume", ["ok": false, "why": "article not found", "key": String(target.articleKey.prefix(8))])
            return
        }
        let session = SpeechSession.page(page)
        let p = min(max(0, target.paragraph), max(0, session.document.count - 1))
        page.positionParagraph = p
        if target.autoPlay {
            // Wait (≤20 s) for the Kokoro host so the resume doesn't start on Apple.
            var waited = 0
            while tts.synth.state.warmingEngineID != nil, waited < 100 {
                try? await Task.sleep(for: .milliseconds(200))
                waited += 1
            }
            speech.start(session, fromParagraph: p)
        } else {
            speech.prepare(session, startingParagraph: p)
        }
        shell.showNowPlaying()
        ListenTimingLog.log("kokoro_resume", [
            "ok": true, "key": ListenTimingLog.shortKey(page.listenKey), "p": p, "auto_play": target.autoPlay,
            "local": tts.usesLocalEngine,
        ])
    }
}
