import SwiftData
import XCTest
@testable import Reader

/// The listening position is saved from the playback session, not from a screen.
@MainActor
final class ListeningProgressRecorderTests: XCTestCase {
    private var fixture: TestSpeech!
    private var container: ModelContainer!
    private var defaults: UserDefaults!
    private let suite = "RecorderTests-\(UUID().uuidString)"
    private var recorder: ListeningProgressRecorder?

    override func setUp() async throws {
        fixture = TestSpeech()
        container = try ModelContainer(for: SavedArticle.self, RecentVisit.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        defaults = UserDefaults(suiteName: suite)
        recorder = ListeningProgressRecorder(
            speech: fixture.speech,
            store: SavedArticleProgressStore(context: container.mainContext, defaults: defaults),
            notificationCenter: NotificationCenter())
    }

    override func tearDown() async throws {
        recorder = nil
        fixture.tearDown()
        defaults.removePersistentDomain(forName: suite)
    }

    private func saved(_ url: String) -> (ReaderArticle, SavedArticle) {
        let article = TestSpeech.article(url, title: url)
        let row = ArticleLibrary.save(article, in: container.mainContext)
        return (article, row)
    }

    /// 🎧 on a saved article with no screen open, then another page replaces it: the first one's
    /// stored spot moved to where it was.
    func testReplacedPageKeepsItsSpot() {
        let (a, rowA) = saved("https://example.com/a")
        let b = TestSpeech.article("https://example.com/b")
        let speech = fixture.speech
        speech.listen(to: a)
        let p2 = a.document.startUTF16Offset(forParagraph: 2)
        fixture.apple.emit(.position(paragraph: 2, utf16: p2 + 3))
        XCTAssertEqual(rowA.playbackParagraphIndex, 2, "written on the new paragraph")

        speech.listen(to: b)
        XCTAssertEqual(speech.nowPlaying?.pageKey, b.id)
        XCTAssertEqual(rowA.playbackParagraphIndex, 2, "the replaced page keeps its paragraph")
        XCTAssertEqual(rowA.playbackUTF16Offset, p2 + 3, "and its spot in it")
        let history = ListenHistory(defaults: defaults)
        XCTAssertNotNil(history.entry(for: a.id), "listened: in Continue")
        XCTAssertNil(history.entry(for: b.id), "unsaved pages keep no history")
    }

    func testPauseAndFinishAreRecorded() {
        let (a, row) = saved("https://example.com/a")
        let speech = fixture.speech
        speech.listen(to: a)
        let p1 = a.document.startUTF16Offset(forParagraph: 1)
        fixture.apple.emit(.position(paragraph: 1, utf16: p1))
        speech.pause()
        XCTAssertEqual(row.playbackParagraphIndex, 1)
        XCTAssertEqual(ListenHistory(defaults: defaults).entry(for: a.id)?.done, false)

        speech.resume()
        fixture.apple.emit(.position(paragraph: 2, utf16: a.document.startUTF16Offset(forParagraph: 2)))
        fixture.apple.emit(.finished)
        XCTAssertEqual(row.playbackParagraphIndex, 2)
        XCTAssertEqual(ListenHistory(defaults: defaults).entry(for: a.id)?.done, true, "heard to the end")

        speech.press(.page(a.id)) {}
        XCTAssertEqual(ListenHistory(defaults: defaults).entry(for: a.id)?.done, false,
                       "playing it again puts it back in progress")
    }
}
