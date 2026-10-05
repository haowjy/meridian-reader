import XCTest
@testable import Reader

/// Playback through a book or series (`SpeechController+Advance`): when a chapter ends the next
/// one is bound and spoken in place, without deactivating the audio session, unbinding the page or
/// clearing the lock screen; at the end of the book it stops like any page.
@MainActor
final class PlaybackAdvanceTests: XCTestCase {
    private var fixture: TestSpeech!
    private var speech: SpeechController { fixture.speech }
    private var apple: FakeListenEngine { fixture.apple }
    private var cleanups: [() -> Void] = []

    override func setUp() async throws { fixture = TestSpeech() }

    override func tearDown() async throws {
        fixture.tearDown()
        cleanups.reversed().forEach { $0() }
        cleanups = []
    }

    /// Plays chapter `index` of `book` from its start, with `book` as the library.
    private func play(_ book: FakeChapterLibrary, chapter index: Int, on speech: SpeechController? = nil) {
        let speech = speech ?? self.speech
        speech.nextChapters = book
        speech.start(book.sessions[index], fromParagraph: 0)
    }

    /// Apple reaches the last paragraph and finishes it.
    private func finishChapter(_ engine: FakeListenEngine? = nil, on speech: SpeechController? = nil) {
        let speech = speech ?? self.speech
        let engine = engine ?? apple
        let last = speech.document.count - 1
        engine.emit(.position(paragraph: last, utf16: speech.document.startUTF16Offset(forParagraph: last)))
        engine.emit(.finished)
    }

    private func waitUntil(_ condition: () -> Bool, _ message: String, timeout: TimeInterval = 5) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { try? await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(condition(), message)
    }

    // MARK: - Carrying on

    func testAFinishedChapterBindsTheNextOneAndSpeaksIt() {
        let book = FakeChapterLibrary(chapters: 3)
        play(book, chapter: 0)
        apple.emit(.becameAudible)
        finishChapter()

        XCTAssertEqual(speech.activeSessionID, book.key(1), "chapter 2 is what you hear")
        XCTAssertEqual(speech.playbackPhase, .playing)
        XCTAssertEqual(speech.currentParagraphIndex, 0)
        XCTAssertEqual(apple.plays.last?.articleID, book.key(1), "and it is spoken")
        XCTAssertEqual(apple.plays.last?.utf16Offset, 0, "from its start")
        XCTAssertEqual(speech.nowPlaying?.title, "Chapter 2")
        XCTAssertEqual(speech.nowPlaying?.source, "The Book", "the bar names the book")
        XCTAssertEqual(book.finished, [book.key(0)], "chapter 1 is finished in the library")
        XCTAssertEqual(speech.activeFolderID, book.folder.id)
    }

    func testNoDeactivateUnbindOrLockScreenClearBetweenChapters() {
        let book = FakeChapterLibrary(chapters: 3)
        var phases: [PlaybackPhase] = []
        speech.onProgress = { phases.append($0.phase) }
        play(book, chapter: 0)
        apple.emit(.becameAudible)
        XCTAssertTrue(speech.audioSession.isActive)
        let clears = speech.lockScreen.clearCount

        finishChapter()
        apple.emit(.becameAudible)
        finishChapter()
        apple.emit(.becameAudible)

        XCTAssertEqual(speech.activeSessionID, book.key(2))
        XCTAssertTrue(speech.audioSession.isActive, "the audio session stays active")
        XCTAssertEqual(speech.audioSession.deactivationCount, 0, "never deactivated between chapters")
        XCTAssertEqual(speech.lockScreen.clearCount, clears, "the lock screen is never cleared")
        XCTAssertEqual(speech.lockScreen.lastInfo?.title, "Chapter 3", "it shows the chapter now playing")
        XCTAssertFalse(phases.contains(.finished) || phases.contains(.idle),
                       "the session never finishes or unbinds in between: \(phases)")
    }

    func testSkippedChaptersArePassedOver() {
        let book = FakeChapterLibrary([.init(title: "One"), .init(title: "Interlude", skips: true), .init(title: "Three")])
        play(book, chapter: 0)
        finishChapter()
        XCTAssertEqual(speech.activeSessionID, book.key(2))
        XCTAssertEqual(apple.plays.last?.articleID, book.key(2))
    }

    /// The end: `finishSession` (deactivate, lock screen cleared), the last chapter staying bound
    /// in `.finished`, so the bar keeps it with ▶.
    func testTheEndOfTheBookFinishesWithThePageBound() {
        let book = FakeChapterLibrary(chapters: 2)
        play(book, chapter: 1)
        finishChapter()
        XCTAssertEqual(speech.playbackPhase, .finished)
        XCTAssertEqual(speech.nowPlaying?.pageKey, book.key(1), "the last chapter stays bound")
        XCTAssertEqual(speech.audioSession.deactivationCount, 1, "the audio session lets other audio resume")
        XCTAssertNil(speech.lockScreen.lastInfo, "the lock screen is cleared")
        XCTAssertTrue(book.finished.isEmpty, "the recorder marks the end, as for any page")
    }

    func testAPageInNoFolderPlaysToItsEndAndStops() {
        let book = FakeChapterLibrary(chapters: 2)
        speech.nextChapters = book
        let page = TestSpeech.article("https://example.com/a")
        speech.listen(to: page)
        XCTAssertNil(speech.activeFolderID, "not a chapter")
        finishChapter()
        XCTAssertEqual(speech.playbackPhase, .finished)
        XCTAssertEqual(speech.nowPlaying?.pageKey, page.id)
        XCTAssertTrue(book.finished.isEmpty)
    }

    /// The Reader's Listen on a chapter (an article, not a library session) still carries on: the
    /// controller asks the library which book it is in.
    func testListeningToAChapterFromItsReaderCarriesOn() {
        let book = FakeChapterLibrary(chapters: 2)
        speech.nextChapters = book
        let chapter = book.sessions[0]
        var article = TestSpeech.article("https://example.com/ch1", id: chapter.id, title: "Chapter 1")
        article.document = chapter.document
        speech.listen(to: article)
        XCTAssertEqual(speech.activeFolderID, book.folder.id)
        finishChapter()
        XCTAssertEqual(speech.activeSessionID, book.key(1))
    }

    func testContentsPlaysAChapterFromItsStartAndCarriesOnFromIt() {
        let book = FakeChapterLibrary(chapters: 4)
        play(book, chapter: 0)
        speech.playPage(book.key(2))
        XCTAssertEqual(speech.activeSessionID, book.key(2))
        XCTAssertEqual(apple.plays.last?.articleID, book.key(2))
        XCTAssertEqual(apple.plays.last?.utf16Offset, 0)
        finishChapter()
        XCTAssertEqual(speech.activeSessionID, book.key(3), "carries on from the chapter picked")
    }

    // MARK: - The library

    /// The recorder, over the real library: a chapter that starts becomes the book's place, a
    /// chapter carried past is finished, and the last chapter's end finishes the book.
    func testTheBooksPlaceFollowsPlaybackAndTheLastChapterFinishesIt() throws {
        let env = try LibraryTestEnvironment()
        cleanups.append { env.cleanUp() }
        let library: LibraryStore = env.library
        let (book, pages) = ChapterAdvanceTests.seedBook(in: library, titles: ["Title Page", "One", "Two"], skipFirst: true)
        let recorder = ListeningProgressRecorder(speech: speech, library: library, notificationCenter: NotificationCenter())
        cleanups.append { _ = recorder }
        speech.nextChapters = library

        let start = try XCTUnwrap(library.continueStart(of: book))
        speech.toggle(.page(start.page), resumeParagraph: start.paragraph)
        XCTAssertEqual(speech.activeFolderID, book.id)
        XCTAssertEqual(speech.lockScreen.lastInfo?.albumTitle, "The Book")
        XCTAssertEqual(book.currentPageKey, pages[1].key, "the chapter playing is the book's place")
        XCTAssertNotNil(book.lastPlayedAt)

        finishChapter()
        XCTAssertEqual(speech.activeSessionID, pages[2].key)
        XCTAssertNotNil(pages[1].finishedAt, "chapter one is finished")
        XCTAssertEqual(book.currentPageKey, pages[2].key, "the place moved on")
        XCTAssertNil(book.finishedAt)

        finishChapter()
        XCTAssertEqual(speech.playbackPhase, .finished)
        XCTAssertNotNil(pages[2].finishedAt)
        XCTAssertNotNil(book.finishedAt, "its last chapter finished the book")
        XCTAssertEqual(book.currentPageKey, pages[2].key)
    }

    /// D7: once the place moves on, finished chapters more than 2 behind it lose their audio; the
    /// text stays.
    func testFinishedChaptersMoreThanTwoBehindLoseTheirAudio() throws {
        let env = try LibraryTestEnvironment()
        cleanups.append { env.cleanUp() }
        let library: LibraryStore = env.library
        let (book, pages) = ChapterAdvanceTests.seedBook(in: library, titles: ["One", "Two", "Three", "Four", "Five"])
        for page in pages.prefix(3) {
            try env.storeAudio(page.listenKey, paragraphs: page.cachedListenParagraphs ?? [])
            page.finishedAt = env.now
        }
        let recorder = ListeningProgressRecorder(speech: speech, library: library, notificationCenter: NotificationCenter())
        cleanups.append { _ = recorder }
        speech.nextChapters = library
        speech.toggle(.page(pages[3]), resumeParagraph: 0)
        finishChapter()
        XCTAssertEqual(book.currentPageKey, pages[4].key)
        XCTAssertFalse(env.cache.hasCache(for: pages[0].listenKey), "three behind: audio deleted")
        XCTAssertFalse(env.cache.hasCache(for: pages[1].listenKey))
        XCTAssertTrue(env.cache.hasCache(for: pages[2].listenKey), "two behind: kept")
        XCTAssertTrue(pages[0].hasText, "the text stays")
    }

    // MARK: - Link chapters

    func testALinkChapterIsFetchedThenSpoken() async {
        let book = FakeChapterLibrary([.init(title: "One"), .init(title: "Two", isLink: true)])
        book.fetchDelay = 0.2
        play(book, chapter: 0)
        let plays = apple.plays.count
        finishChapter()

        XCTAssertEqual(speech.activeSessionID, book.key(0), "waiting: chapter 1 is still bound")
        XCTAssertEqual(speech.playbackPhase, .playing, "still playing")
        XCTAssertTrue(speech.isBufferingNext, "Preparing next…")
        XCTAssertEqual(speech.playState(of: .folder(book.folder.id)), .playing)
        XCTAssertEqual(speech.audioSession.deactivationCount, 0)
        XCTAssertEqual(apple.plays.count, plays, "nothing spoken while it fetches")

        await waitUntil({ speech.activeSessionID == book.key(1) }, "chapter 2 bound once fetched")
        XCTAssertEqual(book.fetched, [book.key(1)])
        XCTAssertEqual(apple.plays.last?.articleID, book.key(1), "then spoken")
        XCTAssertFalse(speech.isBufferingNext)
        XCTAssertEqual(speech.audioSession.deactivationCount, 0)
    }

    func testAFailedFetchEndsWithTheChapterBound() async {
        let book = FakeChapterLibrary([.init(title: "One"), .init(title: "Two", isLink: true)])
        book.fetchResult = false
        play(book, chapter: 0)
        finishChapter()
        await waitUntil({ speech.playbackPhase == .finished }, "Couldn't get the next chapter: the end")
        XCTAssertEqual(speech.nowPlaying?.pageKey, book.key(0), "chapter 1 stays bound")
        XCTAssertEqual(speech.audioSession.deactivationCount, 1)
    }

    func testPausedWhileWaitingTheChapterArrivesPaused() async {
        let book = FakeChapterLibrary([.init(title: "One"), .init(title: "Two", isLink: true)])
        book.fetchDelay = 0.2
        play(book, chapter: 0)
        finishChapter()
        speech.pause()
        XCTAssertEqual(speech.playbackPhase, .paused)
        let plays = apple.plays.count
        await waitUntil({ speech.activeSessionID == book.key(1) }, "chapter 2 bound once fetched")
        XCTAssertEqual(speech.playbackPhase, .paused, "at its start, paused")
        XCTAssertEqual(apple.plays.count, plays, "not spoken")
        speech.press(.page(book.key(1))) { XCTFail("▶ plays what you hear") }
        XCTAssertEqual(apple.plays.last?.articleID, book.key(1), "▶ plays it")
    }

    /// In the background the silent wait is short: iOS may suspend an app holding a silent
    /// audio session.
    func testTheWaitInTheBackgroundIsCapped() async {
        let state = AppRunState(phase: .background)
        let (speech, apple) = makeSpeech(runState: state, provider: nil)
        speech.chapterFlow.waitLimits = .init(foreground: 30, background: 0.3)
        let book = FakeChapterLibrary([.init(title: "One"), .init(title: "Two", isLink: true)])
        book.fetchDelay = 10
        play(book, chapter: 0, on: speech)
        finishChapter(apple, on: speech)
        XCTAssertTrue(speech.isBufferingNext)
        await waitUntil({ speech.playbackPhase == .finished }, "ends after the background cap, not the foreground one",
                        timeout: 3)
        XCTAssertEqual(speech.nowPlaying?.pageKey, book.key(0))
    }

    // MARK: - Rendering (D7, D9)

    /// The catch-up bake that fills a finished page's gaps runs for pages outside books and
    /// series only: a book bakes only the chapter playing and the next one.
    func testTheCatchUpBakeIsOnlyForPagesOutsideBooksAndSeries() async {
        let (speech, apple) = makeSpeech(runState: AppRunState(phase: .active), provider: FakeEngineProvider())
        let page = SpeechSession(id: UUID(), document: ParagraphDocument(parts: ["A page outside any book.", "Its end."]),
                                 detectedLanguage: "en", title: "Page")
        let book = FakeChapterLibrary(chapters: 1)
        cleanups.append {
            for key in [page.id, book.key(0)] { PendingBakeJobStore.shared.removePending(articleID: key) }
        }
        speech.nextChapters = book
        // Apple speaks while the on-device engine loads, and finishes before it hands over.
        speech.start(page, fromParagraph: 0)
        await speech.localTTS.selectEngine(FakeEngineProvider.fakeID)
        XCTAssertTrue(speech.localTTS.usesLocalEngine)
        apple.emit(.finished)
        XCTAssertEqual(speech.playbackPhase, .finished)
        XCTAssertTrue(PendingBakeJobStore.shared.pendingJobs().contains { $0.articleID == page.id },
                      "a page outside books bakes its gaps")

        speech.stop()
        await speech.localTTS.selectEngine(.apple)
        speech.start(book.sessions[0], fromParagraph: 0)
        await speech.localTTS.selectEngine(FakeEngineProvider.fakeID)
        apple.emit(.finished)
        XCTAssertEqual(speech.playbackPhase, .finished, "the book's end")
        XCTAssertFalse(PendingBakeJobStore.shared.pendingJobs().contains { $0.articleID == book.key(0) },
                       "a chapter doesn't")
    }

    /// D9: on a route that can't render in the background (Core ML), the next chapter starts in
    /// Apple's voice with no model call, and goes back to the on-device engine once the app is in
    /// front again.
    func testInTheBackgroundOnCoreMLTheNextChapterPlaysInApplesVoice() async {
        let state = AppRunState(phase: .active)
        let provider = FakeEngineProvider()
        let (speech, apple) = makeSpeech(runState: state, provider: provider)
        let book = FakeChapterLibrary(chapters: 2)
        play(book, chapter: 0, on: speech)
        await speech.localTTS.selectEngine(FakeEngineProvider.fakeID)
        XCTAssertTrue(speech.localTTS.usesLocalEngine)
        state.set(.background)
        try? await Task.sleep(nanoseconds: 100_000_000)
        await waitUntil({ !speech.localTTS.synthQueue.isWorkerRunning }, "nothing renders in the background")
        let calls = provider.lastHost?.calls.count ?? 0

        // Apple speaks chapter 1 (it was playing before the engine loaded) and finishes it.
        apple.emit(.finished)
        XCTAssertEqual(speech.activeSessionID, book.key(1))
        XCTAssertEqual(apple.plays.last?.articleID, book.key(1), "Apple speaks chapter 2")
        XCTAssertEqual(speech.diagnostics.snapshot().engine, "Apple")
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(provider.lastHost?.calls.count ?? 0, calls, "no model call in the background")

        state.set(.active)
        try? await Task.sleep(nanoseconds: 100_000_000)
        apple.emit(.position(paragraph: 1, utf16: speech.document.startUTF16Offset(forParagraph: 1)))
        XCTAssertEqual(speech.diagnostics.snapshot().engine, "Fake", "the on-device engine takes the next paragraph")
        XCTAssertEqual(speech.activeSessionID, book.key(1))
    }

    /// The ONNX route renders in the background: the next chapter keeps the on-device voice.
    func testInTheBackgroundOnTheONNXRouteTheNextChapterKeepsItsVoice() async {
        let state = AppRunState(phase: .active)
        let provider = FakeEngineProvider(config: .init(rendersInBackground: true))
        let (speech, apple) = makeSpeech(runState: state, provider: provider)
        let book = FakeChapterLibrary(chapters: 2)
        play(book, chapter: 0, on: speech)
        await speech.localTTS.selectEngine(FakeEngineProvider.fakeID)
        state.set(.background)
        try? await Task.sleep(nanoseconds: 100_000_000)

        apple.emit(.finished)
        XCTAssertEqual(speech.activeSessionID, book.key(1))
        XCTAssertEqual(speech.diagnostics.snapshot().engine, "Fake", "chapter 2 on the on-device engine")
        XCTAssertEqual(speech.audioSession.deactivationCount, 0)
    }

    // MARK: - Helpers

    /// A controller over a scripted Apple engine and, given `provider`, a fake on-device engine
    /// (Apple selected until the test selects it), its render queue on `runState`.
    private func makeSpeech(runState: AppRunState, provider: FakeEngineProvider?) -> (SpeechController, FakeListenEngine) {
        let suite = "PlaybackAdvance-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let registry = EngineRegistry(providers: [AppleSpeechProvider()] + (provider.map { [$0] } ?? []), gate: { _ in true })
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PlaybackAdvance-\(UUID().uuidString)")
        let coordinator = LocalTTSCoordinator(engines: registry, defaults: defaults,
                                              audioCache: ArticleAudioCache(root: root.appendingPathComponent("cache")),
                                              crashGuard: EngineCrashGuard(directory: root.appendingPathComponent("guard")))
        coordinator.synthQueue.usesBackgroundGrace = false
        coordinator.synthQueue.runState = runState
        let apple = FakeListenEngine()
        let speech = SpeechController(engines: registry, localTTS: coordinator,
                                      audioSession: ListenAudioSession(managesSystemSession: false),
                                      nowPlaying: NowPlayingController(commandCenter: nil, infoCenter: nil),
                                      appleEngine: apple, resumePoints: nil)
        cleanups.append {
            speech.stop()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        return (speech, apple)
    }
}
