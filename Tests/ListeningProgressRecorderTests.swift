import UIKit
import XCTest
@testable import MeridianReader

/// Listening progress is saved into the library from the playback session, not from a screen.
@MainActor
final class ListeningProgressRecorderTests: XCTestCase {
    private var fixture: TestSpeech!
    private var env: LibraryTestEnvironment!
    private var recorder: ListeningProgressRecorder?
    private let notifications = NotificationCenter()
    private var speech: SpeechController { fixture.speech }
    private var library: LibraryStore { env.library }

    override func setUp() async throws {
        fixture = TestSpeech()
        env = try LibraryTestEnvironment(fileBacked: true)
        recorder = ListeningProgressRecorder(speech: fixture.speech, library: env.library,
                                             notificationCenter: notifications)
    }

    override func tearDown() async throws {
        recorder = nil
        fixture.tearDown()
        env.cleanUp()
    }

    private struct SaveFailed: Error {}
    private func failSaves() { library.saveContext = { _ in throw SaveFailed() } }
    private func allowSaves() { library.saveContext = { try $0.save() } }

    /// A Saved row's ▶ on `page` (no article at hand).
    private func play(_ page: Page) {
        speech.press(.page(page.listenKey)) {
            speech.toggle(.page(page), resumeParagraph: page.positionParagraph, resumeUTF16Offset: page.positionUTF16)
        }
    }

    /// The page at `url` as 🎧 and the Reader get it: resolved against the library.
    private func article(_ url: String, title: String) -> ReaderArticle {
        library.readerArticle(url: URL(string: url)!, extracted: DelayedExtractor.article(title: title))
    }

    /// 🎧 on the page at `url`, with no screen open: the browser's decision
    /// (`PageArticleService.listen`), extracting `title`'s article.
    private func listenNow(_ url: String, title: String) async throws -> ReaderArticle {
        let outcome = await PageArticleService.listen(toPageAt: URL(string: url)!, speech: speech, library: library) {
            article(url, title: title)
        }
        guard case .started(let article) = outcome else {
            XCTFail("🎧 didn't start \(url): \(outcome)")
            throw CancellationError()
        }
        return article
    }

    /// 🎧 on a saved article with no screen open, then 🎧 on another page replaces it: the first
    /// page's stored spot moved to where it was, including its progress inside the paragraph,
    /// which only the replacement writes.
    func testReplacedPageKeepsItsSpot() async throws {
        let saved = try library.save(article("https://example.com/a", title: "A"))
        let a = try await listenNow("https://example.com/a", title: "A")
        XCTAssertEqual(a.id, saved.listenKey)
        let p2 = a.document.startUTF16Offset(forParagraph: 2)
        fixture.apple.emit(.position(paragraph: 2, utf16: p2))
        XCTAssertEqual(saved.positionParagraph, 2, "written on the new paragraph")
        fixture.apple.emit(.position(paragraph: 2, utf16: p2 + 3))
        XCTAssertEqual(saved.positionUTF16, p2, "not on the ticks inside the paragraph")

        let b = try await listenNow("https://example.com/b", title: "B")
        XCTAssertEqual(speech.nowPlaying?.pageKey, b.id)
        XCTAssertEqual(saved.positionParagraph, 2, "the replaced page keeps its paragraph")
        XCTAssertEqual(saved.positionUTF16, p2 + 3, "and its spot in it")
        XCTAssertNotNil(saved.lastPlayedAt, "listened: in Continue")
        XCTAssertTrue(saved.isSavedToLibrary, "still saved")
    }

    /// D5: a page played without saving is kept, not in the Library, with its text and its spot,
    /// and is all there after a relaunch: in Continue, opening in the Reader at its spot, and
    /// Now Playing's text.
    func testAPagePlayedWithoutSavingIsRestoredAfterARelaunch() async throws {
        let b = try await listenNow("https://example.com/unsaved", title: "Unsaved")
        let p1 = b.document.startUTF16Offset(forParagraph: 1)
        fixture.apple.emit(.position(paragraph: 1, utf16: p1))
        fixture.apple.emit(.position(paragraph: 1, utf16: p1 + 4))
        speech.pause()
        let kept = try XCTUnwrap(library.page(key: b.id), "kept from its first play")
        XCTAssertFalse(kept.isInLibrary, "not in the Library")

        recorder = nil
        try env.relaunch()
        let page = try XCTUnwrap(env.library.page(key: b.id), "there after a relaunch")
        XCTAssertNil(page.addedAt, "still not in the Library")
        XCTAssertNotNil(page.lastPlayedAt)
        XCTAssertNil(page.finishedAt)
        XCTAssertEqual(page.positionParagraph, 1)
        XCTAssertEqual(page.positionUTF16, p1 + 4, "where it was paused, inside the paragraph")

        XCTAssertEqual(try env.context.fetch(LibraryQueries.playedNotSaved).map(\.listenKey), [b.id],
                       "at the top of the Library's Pages, not saved")

        var opened: ReaderArticle?
        await ReaderArticle.loadSaved(id: b.id, in: env.library) { opened = $0 }
        XCTAssertEqual(opened?.document.paragraphs, b.document.paragraphs, "the Reader has its text")
        XCTAssertEqual(opened?.resumeParagraph, 1, "and opens it at its spot")

        let nowPlaying = await env.library.content(for: b.id)
        XCTAssertEqual(nowPlaying?.title, "Unsaved", "Now Playing shows it")
        XCTAssertEqual(nowPlaying?.displayHTML.contains("first paragraph of Unsaved"), true)
    }

    /// Leaving the app writes the live spot inside the paragraph.
    func testLeavingTheAppKeepsTheSpotInsideTheParagraph() throws {
        let a = article("https://example.com/a", title: "A")
        let page = try library.save(a)
        speech.listen(to: a)
        let p1 = a.document.startUTF16Offset(forParagraph: 1)
        fixture.apple.emit(.position(paragraph: 1, utf16: p1))
        fixture.apple.emit(.position(paragraph: 1, utf16: p1 + 5))
        XCTAssertEqual(page.positionUTF16, p1)

        notifications.post(name: UIApplication.willResignActiveNotification, object: nil)
        XCTAssertEqual(page.positionParagraph, 1)
        XCTAssertEqual(page.positionUTF16, p1 + 5, "the scene leaving writes the live offset")

        fixture.apple.emit(.position(paragraph: 1, utf16: p1 + 9))
        notifications.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertEqual(page.positionUTF16, p1 + 9, "and so does going to the background")
        XCTAssertEqual(speech.nowPlaying?.pageKey, a.id, "it keeps playing")
    }

    /// A Saved row's ▶ (no article at hand): its start, pause, end and replay are recorded.
    func testPauseAndFinishAreRecorded() throws {
        let page = try library.save(article("https://example.com/a", title: "A"))
        let key = page.listenKey
        speech.press(.page(key)) {
            speech.toggle(.page(page), resumeParagraph: page.positionParagraph, resumeUTF16Offset: page.positionUTF16)
        }
        XCTAssertNotNil(page.lastPlayedAt, "dated when it starts")
        let doc = speech.document
        fixture.apple.emit(.position(paragraph: 1, utf16: doc.startUTF16Offset(forParagraph: 1)))
        speech.pause()
        XCTAssertEqual(page.positionParagraph, 1)
        XCTAssertNil(page.finishedAt)

        speech.resume()
        fixture.apple.emit(.position(paragraph: 2, utf16: doc.startUTF16Offset(forParagraph: 2)))
        fixture.apple.emit(.finished)
        XCTAssertEqual(page.positionParagraph, 2)
        XCTAssertNotNil(page.finishedAt, "heard to the end")

        speech.press(.page(key)) {}
        XCTAssertNil(page.finishedAt, "playing it again puts it back in progress")
    }

    // MARK: Saves that fail

    /// Saves fail from the first play of a page the library doesn't have: the page that play made
    /// isn't stored, and a failed ⊕ on it and a failed edit roll it back. The library makes it
    /// again with its progress and the date it started, the recorder writes on to it, and once
    /// saves work the next save stores it all: after a relaunch it is there, at its spot, not in
    /// the Library (the failed Save stays undone), and the failed edit stays undone too.
    func testAPagePlayedWhileSavesFailIsKeptThroughARollback() async throws {
        let started = env.now
        failSaves()
        let b = try await listenNow("https://example.com/unsaved", title: "Unsaved")
        let p1 = b.document.startUTF16Offset(forParagraph: 1)
        fixture.apple.emit(.position(paragraph: 1, utf16: p1))

        env.now = started.addingTimeInterval(60)
        XCTAssertThrowsError(try library.save(b), "⊕ can't be stored")
        XCTAssertThrowsError(try library.makeFolder(name: "Later", in: nil))
        let page = try XCTUnwrap(library.page(key: b.id), "made again after the rollbacks")
        XCTAssertFalse(page.isInLibrary, "the failed Save stays undone")
        XCTAssertEqual(page.lastPlayedAt, started, "dated when it started")
        XCTAssertEqual(page.positionParagraph, 1, "at its spot")

        let p2 = b.document.startUTF16Offset(forParagraph: 2)
        fixture.apple.emit(.position(paragraph: 2, utf16: p2))
        XCTAssertEqual(page.positionParagraph, 2, "the recorder writes to the page made again")
        fixture.apple.emit(.position(paragraph: 2, utf16: p2 + 4))
        allowSaves()
        notifications.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        recorder = nil
        try env.relaunch()
        let stored = try XCTUnwrap(env.library.page(key: b.id), "there after a relaunch")
        XCTAssertNil(stored.addedAt, "not in the Library: the failed Save stays undone")
        XCTAssertEqual(stored.lastPlayedAt, started)
        XCTAssertNil(stored.finishedAt)
        XCTAssertEqual(stored.positionParagraph, 2)
        XCTAssertEqual(stored.positionUTF16, p2 + 4, "where it was when the app left")
        XCTAssertEqual(stored.cachedListenParagraphs, b.document.paragraphs, "with its text")
        XCTAssertFalse(env.folders().contains { $0.name == "Later" }, "the failed edit stays undone")
    }

    /// Saved pages, saves failing: the first plays to its end, then the second starts and moves
    /// on a paragraph. None of it is stored, and a failed move rolls it back. It is written again
    /// (the first still finished, the second dated and at its spot), and once saves work the next
    /// save stores it: so it is after a relaunch. The move stays undone.
    func testAFinishAndAReplacingPagesSpotAreKeptThroughARollback() throws {
        let shelf = try library.makeFolder(name: "Shelf", in: nil)
        let first = try library.save(article("https://example.com/a", title: "A"))
        let second = try library.save(article("https://example.com/b", title: "B"))
        let (firstKey, secondKey) = (first.listenKey, second.listenKey)
        play(first)
        let doc = speech.document
        failSaves()
        env.now = env.now.addingTimeInterval(600)
        let finished = env.now
        fixture.apple.emit(.position(paragraph: 2, utf16: doc.startUTF16Offset(forParagraph: 2)))
        fixture.apple.emit(.finished)
        XCTAssertEqual(first.finishedAt, finished)

        env.now = env.now.addingTimeInterval(60)
        let secondStarted = env.now
        play(second)
        XCTAssertEqual(speech.nowPlaying?.pageKey, secondKey)
        let firstSpot = (first.positionParagraph, first.positionUTF16)
        let p1 = speech.document.startUTF16Offset(forParagraph: 1)
        fixture.apple.emit(.position(paragraph: 1, utf16: p1))

        env.now = env.now.addingTimeInterval(60)
        XCTAssertThrowsError(try library.move([.page(first)], to: shelf))
        XCTAssertNil(first.folder, "the move is undone")
        XCTAssertEqual(first.finishedAt, finished, "still finished")
        XCTAssertEqual(second.lastPlayedAt, secondStarted)
        XCTAssertEqual(second.positionParagraph, 1)

        allowSaves()
        fixture.apple.emit(.position(paragraph: 1, utf16: p1 + 2))
        notifications.post(name: UIApplication.willResignActiveNotification, object: nil)

        recorder = nil
        try env.relaunch()
        let a = try XCTUnwrap(env.library.page(key: firstKey))
        XCTAssertEqual(a.finishedAt, finished, "finished after a relaunch")
        XCTAssertEqual(a.positionParagraph, firstSpot.0)
        XCTAssertEqual(a.positionUTF16, firstSpot.1)
        XCTAssertNil(a.folder, "the failed move stays undone")
        let b = try XCTUnwrap(env.library.page(key: secondKey))
        XCTAssertEqual(b.lastPlayedAt, secondStarted, "dated when it started")
        XCTAssertNil(b.finishedAt)
        XCTAssertEqual(b.positionParagraph, 1)
        XCTAssertEqual(b.positionUTF16, p1 + 2)
    }

    /// Progress a save stored is forgotten: a rollback after a later change to the page
    /// (*Mark as Unfinished*) doesn't write it again over that change.
    func testStoredProgressIsntWrittenAgainByALaterRollback() throws {
        let page = try library.save(article("https://example.com/a", title: "A"))
        let key = page.listenKey
        play(page)
        failSaves()
        fixture.apple.emit(.finished)
        XCTAssertNotNil(page.finishedAt)
        allowSaves()
        try library.setFinished([page], false)
        XCTAssertNil(page.finishedAt, "the mark stored, with the finish before it")

        failSaves()
        XCTAssertThrowsError(try library.makeFolder(name: "Later", in: nil))
        XCTAssertNil(page.finishedAt, "the stored finish isn't written again")
        allowSaves()
        recorder = nil
        try env.relaunch()
        XCTAssertNil(try XCTUnwrap(env.library.page(key: key)).finishedAt, "nor after a relaunch")
    }

    /// A saved page opens with newer text while saves fail: the refresh's own save fails, so
    /// only the context holds that text when 🎧 plays it. The play keeps the article (unlike a
    /// play of a page whose text is stored), and after a failed edit's rollback the newer text
    /// is written again with the spot on it. Once saves work both are stored.
    func testRefreshedTextAndItsSpotSurviveARollbackWhenTheRefreshWasntStored() throws {
        let url = URL(string: "https://example.com/a")!
        let page = try library.save(library.readerArticle(url: url, extracted: extracted(["One here.", "Two here."])))
        let unchanged = try library.save(article("https://example.com/b", title: "B"))
        let key = page.listenKey
        failSaves()
        speech.listen(to: article("https://example.com/b", title: "B"))
        XCTAssertNotNil(library.pendingListening[unchanged.listenKey]?.startedAt)
        XCTAssertNil(library.pendingListening[unchanged.listenKey]?.article, "its text is stored: no copy kept")

        let refreshed = library.readerArticle(url: url, extracted: extracted(["One here.", "Two, rewritten.", "Three.", "Four."]))
        let newer = refreshed.document.paragraphs
        XCTAssertEqual(page.cachedListenParagraphs, newer, "refreshed on open, not stored")
        speech.listen(to: refreshed)
        fixture.apple.emit(.position(paragraph: 3, utf16: refreshed.document.startUTF16Offset(forParagraph: 3)))
        XCTAssertNotNil(library.pendingListening[key]?.article, "only the context holds the text this play is on")

        XCTAssertThrowsError(try library.makeFolder(name: "Later", in: nil))
        XCTAssertEqual(page.cachedListenParagraphs, newer, "the text the spot is on is written again")
        XCTAssertEqual(page.positionParagraph, 3)

        allowSaves()
        library.commit("next")
        recorder = nil
        try env.relaunch()
        let stored = try XCTUnwrap(env.library.page(key: key))
        XCTAssertEqual(stored.cachedListenParagraphs, newer)
        XCTAssertEqual(stored.positionParagraph, 3)
    }

    /// The same refresh, played from the page's Library row (`LibraryActions.play`: a
    /// `SpeechSession.page` start, no article) before the Reader plays it. The start keeps a copy
    /// of the page's text, since only the context holds it (a row's ▶ on a page whose text is
    /// stored keeps none). After a failed edit's rollback the newer text is back with the spot on
    /// paragraph 3, not the spot on the two stored paragraphs; once saves work both are stored.
    func testRefreshedTextPlayedFromItsRowSurvivesARollbackWhenTheRefreshWasntStored() throws {
        let url = URL(string: "https://example.com/a")!
        let page = try library.save(library.readerArticle(url: url, extracted: extracted(["One here.", "Two here."])))
        let unchanged = try library.save(article("https://example.com/b", title: "B"))
        let key = page.listenKey
        let rows = LibraryActions(library: library, speech: speech, shell: ShellState())
        failSaves()
        rows.play(unchanged)
        XCTAssertEqual(speech.nowPlaying?.pageKey, unchanged.listenKey)
        XCTAssertNotNil(library.pendingListening[unchanged.listenKey]?.startedAt)
        XCTAssertNil(library.pendingListening[unchanged.listenKey]?.article, "its text is stored: no copy kept")

        let newer = library.readerArticle(url: url, extracted: extracted(["One here.", "Two, rewritten.", "Three.", "Four."]))
            .document.paragraphs
        XCTAssertEqual(page.cachedListenParagraphs, newer, "refreshed on open, not stored")
        rows.play(page)
        XCTAssertEqual(speech.nowPlaying?.pageKey, key)
        XCTAssertEqual(speech.document.paragraphs, newer, "the row plays the text the page holds")
        let p3 = speech.document.startUTF16Offset(forParagraph: 3)
        fixture.apple.emit(.position(paragraph: 3, utf16: p3))
        XCTAssertEqual(library.pendingListening[key]?.article?.document.paragraphs, newer,
                       "only the context holds the text this play is on: a copy is kept")

        XCTAssertThrowsError(try library.makeFolder(name: "Later", in: nil))
        XCTAssertEqual(page.cachedListenParagraphs, newer, "the text the spot is on is written again")
        XCTAssertEqual(page.positionParagraph, 3)
        XCTAssertEqual(page.positionUTF16, p3)

        allowSaves()
        library.commit("next")
        recorder = nil
        try env.relaunch()
        let stored = try XCTUnwrap(env.library.page(key: key))
        XCTAssertEqual(stored.cachedListenParagraphs, newer)
        XCTAssertEqual(stored.positionParagraph, 3)
        XCTAssertEqual(stored.positionUTF16, p3)
        XCTAssertFalse(env.folders().contains { $0.name == "Later" }, "the failed edit stays undone")
    }

    /// Saves failing, a refreshed page plays in the Reader (its article kept) and is stopped,
    /// then opens with newer text still and plays from its row. The row's copy replaces the earlier article: the
    /// rollback writes the text the spot was played on, not the earlier play's.
    func testARowPlayKeepsTheNewerTextOverAnEarlierPlaysArticle() throws {
        let url = URL(string: "https://example.com/a")!
        let page = try library.save(library.readerArticle(url: url, extracted: extracted(["One here.", "Two here."])))
        let key = page.listenKey
        failSaves()
        speech.listen(to: library.readerArticle(url: url, extracted: extracted(["One here.", "Two, rewritten.", "Three."])))
        XCTAssertEqual(library.pendingListening[key]?.article?.document.paragraphs.count, 3)
        speech.stop()

        let newest = library.readerArticle(url: url, extracted: extracted(["One here.", "Two, again.", "Three.", "Four."]))
            .document.paragraphs
        LibraryActions(library: library, speech: speech, shell: ShellState()).play(page)
        XCTAssertEqual(speech.document.paragraphs, newest)
        fixture.apple.emit(.position(paragraph: 3, utf16: speech.document.startUTF16Offset(forParagraph: 3)))

        XCTAssertThrowsError(try library.makeFolder(name: "Later", in: nil))
        XCTAssertEqual(page.cachedListenParagraphs, newest, "the text the spot was played on")
        XCTAssertEqual(page.positionParagraph, 3)
        allowSaves()
        library.commit("next")
        recorder = nil
        try env.relaunch()
        let stored = try XCTUnwrap(env.library.page(key: key))
        XCTAssertEqual(stored.cachedListenParagraphs, newest)
        XCTAssertEqual(stored.positionParagraph, 3)
    }

    /// A book chapter with no address, whose listen blocks aren't built yet, plays from its row
    /// while saves fail: the session builds them (`Page.listenDocument`), only in the context.
    /// After a failed edit's rollback the start's copy writes them again with the spot on them,
    /// and the chapter still has no address: the copy's empty one isn't written to it.
    func testAChapterWithNoAddressKeepsNoneWhenARollbackWritesItsTextAgain() throws {
        let book = Folder(name: "Book", kind: .book)
        env.context.insert(book)
        let chapter = Page(key: UUID(), title: "Chapter 1", byline: "An Author", urlString: nil,
                           contentState: .saved, addedAt: env.now)
        let paragraphs = ["The first paragraph.", "The second paragraph.", "The third paragraph."]
        chapter.plainText = paragraphs.joined(separator: "\n\n")
        chapter.cleanedHTML = paragraphs.map { "<p>\($0)</p>" }.joined()
        env.context.insert(chapter)
        chapter.setFolder(book)
        XCTAssertTrue(library.commit("chapter"))
        XCTAssertNil(chapter.cachedListenParagraphs, "no listen blocks yet")
        let key = try XCTUnwrap(chapter.key)
        failSaves()

        LibraryActions(library: library, speech: speech, shell: ShellState()).play(chapter)
        let built = speech.document.paragraphs
        XCTAssertEqual(built.count, 3)
        XCTAssertEqual(chapter.cachedListenParagraphs, built, "built as it starts, not stored")
        let p1 = speech.document.startUTF16Offset(forParagraph: 1)
        fixture.apple.emit(.position(paragraph: 1, utf16: p1))

        XCTAssertThrowsError(try library.makeFolder(name: "Later", in: nil))
        XCTAssertEqual(chapter.cachedListenParagraphs, built, "written again")
        XCTAssertEqual(chapter.positionParagraph, 1)
        XCTAssertNil(chapter.urlString, "still no address")
        XCTAssertNil(chapter.canonicalURL)

        allowSaves()
        library.commit("next")
        recorder = nil
        try env.relaunch()
        let stored = try XCTUnwrap(env.library.page(key: key))
        XCTAssertEqual(stored.cachedListenParagraphs, built)
        XCTAssertEqual(stored.positionParagraph, 1)
        XCTAssertEqual(stored.positionUTF16, p1)
        XCTAssertNil(stored.urlString)
        XCTAssertNil(stored.canonicalURL)
    }

    private func extracted(_ paragraphs: [String]) -> ExtractedArticle {
        ExtractedArticle(title: "A", siteName: nil, cleanedHTML: paragraphs.map { "<p>\($0)</p>" }.joined(),
                         plainText: paragraphs.joined(separator: "\n\n"), excerpt: "")
    }

    // MARK: Deleting the playing page

    /// Deleting stops the page's playback as the app does (`AppComposition.makeLibrary`), and
    /// stopping records the spot inside the paragraph.
    private func stopsPlaybackOnDelete(then afterStop: @escaping () -> Void = {}) {
        library.stopPlaybackIfPlaying = { [unowned self] key in
            guard speech.activeSessionID == key else { return }
            speech.stop()
            afterStop()
        }
    }

    /// *Delete Folder and Contents* reaches the playing page after staging the delete of a page
    /// before it. Stopping that playback records its spot, and that save would work; the
    /// delete's own save then fails. Nothing is deleted, by the store or on disk: the position
    /// waits for the delete's save instead of storing half of it. After the rollback the
    /// stopped page keeps its spot, stored once saves work, and a relaunch agrees.
    func testAFolderDeleteThatFailsDeletesNothingThoughStoppingItsPlayingPageRecordsASpot() throws {
        let shelf = try library.makeFolder(name: "Shelf", in: nil)
        let inner = try library.makeFolder(name: "Inner", in: shelf)
        let (shelfID, innerID) = (shelf.id, inner.id)
        let first = try library.save(article("https://example.com/a", title: "A"), placement: .folder(inner))
        let playing = try library.save(article("https://example.com/b", title: "B"), placement: .folder(shelf))
        let (firstKey, playingKey) = (first.listenKey, playing.listenKey)
        for page in [first, playing] { try env.storeAudio(page.listenKey, paragraphs: page.cachedListenParagraphs ?? []) }
        let audioBefore = try [firstKey, playingKey].map { try audioFiles($0) }
        play(playing)
        let p1 = speech.document.startUTF16Offset(forParagraph: 1)
        fixture.apple.emit(.position(paragraph: 1, utf16: p1))
        fixture.apple.emit(.position(paragraph: 1, utf16: p1 + 5))
        var failing = false
        library.saveContext = { if failing { throw SaveFailed() }; try $0.save() }
        stopsPlaybackOnDelete { failing = true }

        XCTAssertThrowsError(try library.deleteFolder(shelf, keepContents: false)) {
            XCTAssertEqual($0 as? LibraryStoreError, .saveFailed)
        }
        XCTAssertNil(speech.nowPlaying, "playback stopped")
        XCTAssertNotNil(library.folder(id: shelfID))
        XCTAssertNotNil(library.folder(id: innerID))
        XCTAssertNotNil(library.page(key: firstKey), "the page staged before the playing one stays")
        XCTAssertEqual(try [firstKey, playingKey].map { try audioFiles($0) }, audioBefore, "no audio deleted")
        let stopped = try XCTUnwrap(library.page(key: playingKey))
        XCTAssertEqual(stopped.positionParagraph, 1)
        XCTAssertEqual(stopped.positionUTF16, p1 + 5, "the spot stopping recorded")

        allowSaves()
        library.commit("next")
        recorder = nil
        try env.relaunch()
        XCTAssertNotNil(env.library.folder(id: shelfID), "nothing was deleted")
        XCTAssertNotNil(env.library.folder(id: innerID))
        XCTAssertNotNil(env.library.page(key: firstKey))
        XCTAssertEqual(try [firstKey, playingKey].map { try audioFiles($0) }, audioBefore)
        let stored = try XCTUnwrap(env.library.page(key: playingKey))
        XCTAssertEqual(stored.positionParagraph, 1)
        XCTAssertEqual(stored.positionUTF16, p1 + 5, "stored once saves work")
    }

    /// A row's *Delete* on the playing page while saves fail: playback stops, the page and its
    /// audio stay, at the spot stopping recorded, and that spot is stored once saves work.
    func testDeletingThePlayingPageWhileSavesFailKeepsItAtItsSpot() throws {
        let page = try library.save(article("https://example.com/a", title: "A"))
        let key = page.listenKey
        try env.storeAudio(key, paragraphs: page.cachedListenParagraphs ?? [])
        let audioBefore = try audioFiles(key)
        play(page)
        let p2 = speech.document.startUTF16Offset(forParagraph: 2)
        fixture.apple.emit(.position(paragraph: 2, utf16: p2))
        fixture.apple.emit(.position(paragraph: 2, utf16: p2 + 3))
        stopsPlaybackOnDelete()
        failSaves()

        library.delete(page)
        XCTAssertNil(speech.nowPlaying, "playback stopped")
        let back = try XCTUnwrap(library.page(key: key), "the page stays")
        XCTAssertEqual(back.positionParagraph, 2)
        XCTAssertEqual(back.positionUTF16, p2 + 3)
        XCTAssertEqual(try audioFiles(key), audioBefore, "and its audio")

        allowSaves()
        notifications.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        recorder = nil
        try env.relaunch()
        let stored = try XCTUnwrap(env.library.page(key: key))
        XCTAssertEqual(stored.positionParagraph, 2)
        XCTAssertEqual(stored.positionUTF16, p2 + 3)
        XCTAssertEqual(try audioFiles(key), audioBefore)
    }

    /// Every file under a key's audio directory in the library's cache, by relative path.
    private func audioFiles(_ key: UUID) throws -> [String: Data] {
        let dir = env.cache.directory(for: key)
        var out: [String: Data] = [:]
        for name in FileManager.default.subpaths(atPath: dir.path) ?? [] {
            var isDir: ObjCBool = false
            let url = dir.appending(path: name)
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { continue }
            out[name] = try Data(contentsOf: url)
        }
        return out
    }
}
