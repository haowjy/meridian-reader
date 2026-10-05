import UIKit
import XCTest
@testable import Reader

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

        let recent = try env.context.fetch(LibraryQueries.recentlyPlayed)
        let undated = try env.context.fetch(LibraryQueries.undatedInProgress)
        XCTAssertEqual(LibraryQueries.continuePages(recent: recent, undated: undated).map(\.listenKey), [b.id],
                       "in Continue")

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
}
