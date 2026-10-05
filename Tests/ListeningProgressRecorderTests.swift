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
}
