import SwiftData
import UIKit
import XCTest
@testable import Reader

/// The listening position is saved from the playback session, not from a screen.
@MainActor
final class ListeningProgressRecorderTests: XCTestCase {
    private var fixture: TestSpeech!
    private var container: ModelContainer!
    private var library: LibraryStore!
    private var recorder: ListeningProgressRecorder?
    private let notifications = NotificationCenter()

    override func setUp() async throws {
        fixture = TestSpeech()
        container = try LibraryStoreConfiguration.makeInMemoryContainer()
        library = LibraryStore(context: container.mainContext, tts: fixture.speech.localTTS)
        recorder = ListeningProgressRecorder(
            speech: fixture.speech,
            store: LibraryProgressStore(library: library),
            notificationCenter: notifications)
    }

    override func tearDown() async throws {
        recorder = nil
        fixture.tearDown()
    }

    private func saved(_ url: String) -> (ReaderArticle, Page) {
        let article = TestSpeech.article(url, title: url)
        return (article, library.save(article))
    }

    /// 🎧 on a saved article with no screen open, then another page replaces it: the first one's
    /// stored spot moved to where it was, including its progress inside the paragraph, which
    /// only the replacement writes.
    func testReplacedPageKeepsItsSpot() {
        let (a, rowA) = saved("https://example.com/a")
        let b = TestSpeech.article("https://example.com/b")
        let speech = fixture.speech
        speech.listen(to: a)
        let p2 = a.document.startUTF16Offset(forParagraph: 2)
        fixture.apple.emit(.position(paragraph: 2, utf16: p2))
        XCTAssertEqual(rowA.positionParagraph, 2, "written on the new paragraph")
        fixture.apple.emit(.position(paragraph: 2, utf16: p2 + 3))
        XCTAssertEqual(rowA.positionUTF16, p2, "not on the ticks inside the paragraph")

        speech.listen(to: b)
        XCTAssertEqual(speech.nowPlaying?.pageKey, b.id)
        XCTAssertEqual(rowA.positionParagraph, 2, "the replaced page keeps its paragraph")
        XCTAssertEqual(rowA.positionUTF16, p2 + 3, "and its spot in it")
        XCTAssertNotNil(rowA.lastPlayedAt, "listened: in Continue")
        XCTAssertNil(library.page(key: b.id), "a page the library doesn't have keeps nothing")
    }

    /// Leaving the app writes the live spot inside the paragraph.
    func testLeavingTheAppKeepsTheSpotInsideTheParagraph() {
        let (a, row) = saved("https://example.com/a")
        let speech = fixture.speech
        speech.listen(to: a)
        let p1 = a.document.startUTF16Offset(forParagraph: 1)
        fixture.apple.emit(.position(paragraph: 1, utf16: p1))
        fixture.apple.emit(.position(paragraph: 1, utf16: p1 + 5))
        XCTAssertEqual(row.positionUTF16, p1)

        notifications.post(name: UIApplication.willResignActiveNotification, object: nil)
        XCTAssertEqual(row.positionParagraph, 1)
        XCTAssertEqual(row.positionUTF16, p1 + 5, "the scene leaving writes the live offset")

        fixture.apple.emit(.position(paragraph: 1, utf16: p1 + 9))
        notifications.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertEqual(row.positionUTF16, p1 + 9, "and so does going to the background")
        XCTAssertEqual(speech.nowPlaying?.pageKey, a.id, "it keeps playing")
    }

    func testPauseAndFinishAreRecorded() {
        let (a, row) = saved("https://example.com/a")
        let speech = fixture.speech
        speech.listen(to: a)
        let p1 = a.document.startUTF16Offset(forParagraph: 1)
        fixture.apple.emit(.position(paragraph: 1, utf16: p1))
        speech.pause()
        XCTAssertEqual(row.positionParagraph, 1)
        XCTAssertNotNil(row.lastPlayedAt)
        XCTAssertNil(row.finishedAt)

        speech.resume()
        fixture.apple.emit(.position(paragraph: 2, utf16: a.document.startUTF16Offset(forParagraph: 2)))
        fixture.apple.emit(.finished)
        XCTAssertEqual(row.positionParagraph, 2)
        XCTAssertNotNil(row.finishedAt, "heard to the end")

        speech.press(.page(a.id)) {}
        XCTAssertNil(row.finishedAt, "playing it again puts it back in progress")
    }
}
