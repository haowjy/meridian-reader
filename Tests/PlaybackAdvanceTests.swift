import XCTest
@testable import MeridianReader

/// Playback through a book or series (`SpeechController+Advance`): when a chapter ends the next
/// one is bound and spoken in place, without deactivating the audio session, unbinding the page or
/// clearing the lock screen; at the end of the book it stops like any page.
@MainActor
final class PlaybackAdvanceTests: XCTestCase {
    private var fixture: TestSpeech!
    private var speech: SpeechController { fixture.speech }
    private var apple: FakeListenEngine { fixture.apple }
    private var cleanups: [() -> Void] = []
    /// Pages of tests with an on-device engine: stopping may file a bake job for them in the
    /// process-wide store, which another test's engine would adopt. Removed once all has stopped.
    private var bakeKeys: [UUID] = []

    override func setUp() async throws { fixture = TestSpeech() }

    override func tearDown() async throws {
        fixture.tearDown()
        cleanups.reversed().forEach { $0() }
        cleanups = []
        for key in bakeKeys { PendingBakeJobStore.shared.removePending(articleID: key) }
        bakeKeys = []
    }

    /// Plays chapter `index` of `book` from its start, with `book` as the library.
    private func play(_ book: FakeChapterLibrary, chapter index: Int, on speech: SpeechController? = nil) {
        let speech = speech ?? self.speech
        speech.nextChapters = book
        speech.start(book.sessions[index])
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

    /// A folder you made carries on the same way; it is what the pages play from, and the bar
    /// keeps each page's own site.
    func testAFolderOfPagesCarriesOnPageToPage() {
        let folder = FakeChapterLibrary(name: "Finance", isBookOrSeries: false, [.init(title: "Page 1"), .init(title: "Page 2")])
        play(folder, chapter: 0)
        apple.emit(.becameAudible)
        XCTAssertEqual(speech.nowPlaying?.playingFrom, .folder(id: folder.folder.id, name: "Finance"))
        XCTAssertEqual(speech.nowPlaying?.source, "An Author", "the page's site, not the folder")
        finishChapter()

        XCTAssertEqual(speech.activeSessionID, folder.key(1), "page 2 is what you hear")
        XCTAssertEqual(speech.playbackPhase, .playing)
        XCTAssertEqual(apple.plays.last?.articleID, folder.key(1))
        XCTAssertEqual(folder.finished, [folder.key(0)])
        apple.emit(.becameAudible)
        XCTAssertEqual(speech.playState(of: .folder(folder.folder.id)), .playing, "the folder's ▶ shows it playing")

        finishChapter()
        XCTAssertEqual(speech.playbackPhase, .finished, "the end of the folder")
        XCTAssertEqual(speech.activeSessionID, folder.key(1))
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
        speech.start(.page(start.page), at: start.spot)
        XCTAssertEqual(speech.activeFolderID, book.id)
        XCTAssertEqual(speech.lockScreen.lastInfo?.albumTitle, "The Book")
        XCTAssertEqual(book.currentPageKey, pages[1].key, "the chapter playing is the book's place")

        finishChapter()
        XCTAssertEqual(speech.activeSessionID, pages[2].key)
        XCTAssertNotNil(pages[1].finishedAt, "chapter one is finished")
        XCTAssertEqual(book.currentPageKey, pages[2].key, "the place moved on")

        finishChapter()
        XCTAssertEqual(speech.playbackPhase, .finished)
        XCTAssertNotNil(pages[2].finishedAt)
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
        speech.start(.page(pages[3]))
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

    /// Pause and resume while a link chapter is fetched say how it starts: nothing restarts the
    /// chapter that ended, and it stays finished (the recorder doesn't take the resume for a
    /// replay of it). The fetched chapter then plays. Over the real library.
    func testPauseAndResumeWhileFetchingLeaveTheEndedChapterFinished() async throws {
        let env = try LibraryTestEnvironment()
        cleanups.append { env.cleanUp() }
        let library: LibraryStore = env.library
        let series = Folder(name: "Serial", kind: .series)
        env.context.insert(series)
        let one = Page(key: UUID(), title: "One", byline: "", urlString: "https://example.com/s/1",
                       contentState: .saved, addedAt: env.now, sortKey: 0)
        one.storeListenParagraphs(["Chapter one begins.", "Chapter one ends."])
        let two = Page(key: UUID(), title: "Two", byline: "", urlString: "https://example.com/s/2",
                       contentState: .link, addedAt: env.now, sortKey: 1)
        for page in [one, two] {
            env.context.insert(page)
            page.setFolder(series)
        }
        library.commit("seed series")
        let recorder = ListeningProgressRecorder(speech: speech, library: library, notificationCenter: NotificationCenter())
        cleanups.append { _ = recorder }
        speech.nextChapters = FetchingLibrary(library, text: ["Chapter two, fetched."], delay: 0.3)

        speech.start(.page(one))
        let plays = apple.plays.count
        finishChapter()
        XCTAssertTrue(speech.isBufferingNext, "fetching chapter two")
        XCTAssertNotNil(one.finishedAt, "chapter one is finished")

        speech.pause()
        speech.resume()
        XCTAssertEqual(speech.playbackPhase, .playing)
        XCTAssertEqual(apple.plays.count, plays, "nothing restarts chapter one")
        XCTAssertNotNil(one.finishedAt, "resuming the wait doesn't make it unfinished")

        await waitUntil({ speech.activeSessionID == two.key }, "chapter two plays once fetched")
        XCTAssertEqual(apple.plays.last?.articleID, two.key)
        XCTAssertEqual(speech.playbackPhase, .playing)
        XCTAssertNotNil(one.finishedAt, "chapter one is still finished")
        XCTAssertNil(two.finishedAt)
        XCTAssertEqual(series.currentPageKey, two.key, "the place is chapter two")
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

    /// Going to the background during the wait shortens it to the background limit from then.
    func testTheWaitShortensWhenTheAppGoesToTheBackground() async {
        let state = AppRunState(phase: .active)
        let (speech, apple) = makeSpeech(runState: state, provider: nil)
        speech.chapterFlow.waitLimits = .init(foreground: 30, background: 0.3)
        let book = FakeChapterLibrary([.init(title: "One"), .init(title: "Two", isLink: true)])
        book.fetchDelay = 10
        play(book, chapter: 0, on: speech)
        finishChapter(apple, on: speech)
        XCTAssertTrue(speech.isBufferingNext)

        state.set(.background)
        await waitUntil({ speech.playbackPhase == .finished }, "ends after the background cap from then, not the foreground one",
                        timeout: 3)
        XCTAssertEqual(speech.nowPlaying?.pageKey, book.key(0))
    }

    // MARK: - Rendering (D7, D9)

    /// Audio held for library work a launch couldn't finish (`ArticleAudioCache.held`) isn't
    /// staged, after the launch hold has ended too: a render would replace audio that work still
    /// needs. Held pages, or all audio.
    func testHeldAudioIsNotStaged() async {
        let (speech, _) = makeSpeech(runState: AppRunState(phase: .active), provider: FakeEngineProvider())
        let tts = speech.localTTS
        let book = FakeChapterLibrary(chapters: 3)
        bakeKeys += book.sessions.map(\.id)
        await tts.selectEngine(FakeEngineProvider.fakeID)
        XCTAssertTrue(tts.usesLocalEngine)
        let stage = { (index: Int) in
            tts.stageNextChapter(cacheKey: book.key(index), after: book.key(index - 1),
                                 paragraphs: book.sessions[index].document.paragraphs)
        }
        for hold in [ArticleAudioCache.Hold.pages([book.key(1)]), .all] {
            tts.holdRenderingForLaunch()
            tts.audioCache.held = hold
            tts.endLaunchHold()
            XCTAssertFalse(stage(1), "\(hold)")
            XCTAssertNil(tts.synthQueue.stagedCacheKey, "\(hold)")
            XCTAssertFalse(tts.synthQueue.hasJob(cacheKey: book.key(1)), "\(hold)")
        }
        tts.audioCache.held = .pages([book.key(1)])
        XCTAssertTrue(stage(2), "a chapter whose audio isn't held is staged")
        XCTAssertEqual(tts.synthQueue.stagedCacheKey, book.key(2))
    }

    /// The catch-up bake that fills a finished page's gaps runs for pages outside books and
    /// series only: a book bakes only the chapter playing and the next one.
    func testTheCatchUpBakeIsOnlyForPagesOutsideBooksAndSeries() async {
        let (speech, apple) = makeSpeech(runState: AppRunState(phase: .active), provider: FakeEngineProvider())
        let page = SpeechSession(id: UUID(), document: ParagraphDocument(parts: ["A page outside any book.", "Its end."]),
                                 detectedLanguage: "en", title: "Page")
        let book = FakeChapterLibrary(chapters: 1)
        bakeKeys += [page.id, book.key(0)]
        speech.nextChapters = book
        // Apple speaks while the on-device engine loads, and finishes before it hands over.
        speech.start(page)
        await speech.localTTS.selectEngine(FakeEngineProvider.fakeID)
        XCTAssertTrue(speech.localTTS.usesLocalEngine)
        apple.emit(.finished)
        XCTAssertEqual(speech.playbackPhase, .finished)
        XCTAssertTrue(PendingBakeJobStore.shared.pendingJobs().contains { $0.articleID == page.id },
                      "a page outside books bakes its gaps")

        speech.stop()
        await speech.localTTS.selectEngine(.apple)
        speech.start(book.sessions[0])
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
        bakeKeys += book.sessions.map(\.id)
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

    /// A chapter whose paragraphs with words are all rendered counts as rendered, though one
    /// paragraph is a bare "—" that never gets audio: in the background on Core ML it keeps the
    /// on-device voice (Apple doesn't stand in), and while one plays the next is staged.
    func testAParagraphWithNothingToSpeakDoesntMakeAChapterUnrendered() async throws {
        let state = AppRunState(phase: .active)
        let provider = FakeEngineProvider()
        let (speech, apple) = makeSpeech(runState: state, provider: provider)
        let words = ["It begins here, with a few words.", "—", "It goes on for a while.", "Then it ends.",
                     "And one more after that."]
        let book = FakeChapterLibrary([.init(title: "One"), .init(title: "Two", paragraphs: words, verbatim: true),
                                       .init(title: "Three")])
        bakeKeys += book.sessions.map(\.id)
        play(book, chapter: 0, on: speech)
        await speech.localTTS.selectEngine(FakeEngineProvider.fakeID)
        let target = try XCTUnwrap(speech.localTTS.renderTarget)
        for i in words.indices where i != 1 { try storeAudio(speech.localTTS.audioCache, book.key(1), i, in: target) }
        state.set(.background)
        try? await Task.sleep(nanoseconds: 100_000_000)

        apple.emit(.finished)
        XCTAssertEqual(speech.activeSessionID, book.key(1))
        XCTAssertEqual(speech.diagnostics.snapshot().engine, "Fake", "chapter 2 is rendered: no Apple stand-in")

        speech.chapterBecameAudible()
        XCTAssertEqual(speech.localTTS.synthQueue.stagedCacheKey, book.key(2), "chapter 2 is rendered: chapter 3 is staged")
    }

    /// The ONNX route renders in the background: the next chapter keeps the on-device voice.
    func testInTheBackgroundOnTheONNXRouteTheNextChapterKeepsItsVoice() async {
        let state = AppRunState(phase: .active)
        let provider = FakeEngineProvider(config: .init(rendersInBackground: true))
        let (speech, apple) = makeSpeech(runState: state, provider: provider)
        let book = FakeChapterLibrary(chapters: 2)
        bakeKeys += book.sessions.map(\.id)
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

    /// Paragraph `index` of `key` rendered in `target`, as a finished bake leaves it.
    private func storeAudio(_ cache: ArticleAudioCache, _ key: UUID, _ index: Int, in target: RenderTarget) throws {
        let tone = FileManager.default.temporaryDirectory.appendingPathComponent("tone-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: tone) }
        try LocalPCMWriter.write(FakeSynthHost.tone(seconds: 0.2, sampleRate: 24_000), sampleRate: 24_000, to: tone)
        try cache.storeParagraph(articleID: key, paragraphIndex: index, sourceURL: tone, duration: 0.2,
                                 engineID: target.engineID, voiceID: target.cacheVoice)
    }

    /// The real library, with a fetch that gives a link chapter `text` after `delay`: no page
    /// fetcher is connected to it yet.
    @MainActor
    private final class FetchingLibrary: NextChapterProviding {
        let library: LibraryStore
        let text: [String]
        let delay: TimeInterval

        init(_ library: LibraryStore, text: [String], delay: TimeInterval) {
            self.library = library
            self.text = text
            self.delay = delay
        }

        func folder(containing pageKey: UUID) -> PlaybackFolder? { library.folder(containing: pageKey) }
        func chapters(of folderID: UUID) -> [ChapterAdvance.Chapter] { library.chapters(of: folderID) }
        func load(_ pageKey: UUID) -> SpeechSession? { library.load(pageKey) }
        func pageFinished(key: UUID, text: String?) { library.pageFinished(key: key, text: text) }

        func fetch(_ pageKey: UUID) async -> Bool {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let page = library.page(key: pageKey) else { return false }
            page.plainText = text.joined(separator: "\n\n")
            page.storeListenParagraphs(text)
            library.commit("fetched")
            return true
        }
    }

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
