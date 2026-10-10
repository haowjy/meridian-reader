import SwiftData
import XCTest
@testable import Reader

/// Every play button asks one question, `playState(of:)`: is this what you hear, and is it playing.
@MainActor
final class PlayStateTests: XCTestCase {
    private var fixture: TestSpeech!
    /// The library store of a test that needs one.
    private var container: ModelContainer?
    private var speech: SpeechController { fixture.speech }

    override func setUp() async throws { fixture = TestSpeech() }
    override func tearDown() async throws { fixture.tearDown() }

    private let pageA = "https://example.com/a"
    private let pageB = "https://example.com/b"

    private func canonical(_ url: String) -> String { ArticleIdentity.canonicalURLString(from: url) }

    func testNothingPlayingIsIdle() {
        XCTAssertNil(speech.nowPlaying)
        XCTAssertEqual(speech.playState(of: .page(UUID())), .idle)
        XCTAssertEqual(speech.playState(of: .webPage(canonicalURL: canonical(pageA))), .idle)
    }

    func testPlayingPageByKeyAndByCanonicalURL() {
        let a = TestSpeech.article(pageA)
        speech.listen(to: a)
        XCTAssertEqual(speech.playState(of: .page(a.id)), .playing)
        XCTAssertEqual(speech.playState(of: .webPage(canonicalURL: canonical(pageA))), .playing)
        XCTAssertEqual(speech.playState(of: .webPage(canonicalURL: canonical(pageB))), .idle, "another page")
        XCTAssertEqual(speech.playState(of: .page(UUID())), .idle)
        XCTAssertEqual(speech.nowPlaying?.title, "Article")
        XCTAssertEqual(speech.nowPlaying?.source, "example.com")
        XCTAssertEqual(speech.nowPlaying?.playingFrom, .site(host: "example.com"))
    }

    func testLegacyRandomKeyPageMatchesItsWebPage() throws {
        // A save from before identity v2 became a page with its random key; played from its row
        // (no article at hand), its web page still matches it by canonical URL.
        let container = try LibraryStoreConfiguration.makeInMemoryContainer()
        self.container = container
        let library = LibraryStore(context: container.mainContext, tts: speech.localTTS)
        let legacy = library.save(TestSpeech.article(pageA, id: UUID()))
        XCTAssertNotEqual(legacy.listenKey, ArticleIdentity.articleKey(canonicalURL: canonical(pageA)))
        speech.press(.page(legacy.listenKey)) {
            speech.toggle(.page(legacy), resumeParagraph: legacy.positionParagraph,
                          resumeUTF16Offset: legacy.positionUTF16)
        }
        XCTAssertEqual(speech.playState(of: .webPage(canonicalURL: canonical(pageA))), .playing)
        XCTAssertEqual(speech.playState(of: .page(legacy.listenKey)), .playing)
        XCTAssertEqual(speech.playState(of: .webPage(canonicalURL: canonical(pageB))), .idle, "another page")
    }

    func testPausedThenResumed() {
        let a = TestSpeech.article(pageA)
        speech.listen(to: a)
        speech.press(.page(a.id)) { XCTFail("what you hear pauses, it doesn't start") }
        XCTAssertEqual(speech.playState(of: .page(a.id)), .paused)
        speech.press(.page(a.id)) { XCTFail("resumes") }
        XCTAssertEqual(speech.playState(of: .page(a.id)), .playing)
    }

    func testPreparingUntilReadyOrCancelled() {
        let a = TestSpeech.article(pageA)
        let b = TestSpeech.article(pageB)
        speech.listen(to: a)
        let target = ListenTarget.webPage(canonicalURL: canonical(pageB))
        let request = speech.beginPreparing(target)
        XCTAssertEqual(speech.playState(of: target), .preparing)
        XCTAssertEqual(speech.playState(of: .page(a.id)), .playing, "what's playing keeps playing meanwhile")
        speech.endPreparing(request)
        XCTAssertEqual(speech.playState(of: target), .idle, "extraction failed: back to grey")
        XCTAssertEqual(speech.nowPlaying?.pageKey, a.id)

        _ = speech.beginPreparing(target)
        speech.listen(to: b)
        XCTAssertEqual(speech.playState(of: target), .playing, "ready: it replaces what was playing")
        XCTAssertEqual(speech.playState(of: .page(a.id)), .idle)
    }

    func testPreparedShowsAsPaused() {
        let a = TestSpeech.article(pageA)
        speech.prepare(SpeechSession(article: a))
        XCTAssertEqual(speech.playbackPhase, .prepared)
        XCTAssertEqual(speech.playState(of: .page(a.id)), .paused)
        XCTAssertNotNil(speech.nowPlaying, "the bar shows a prepared page")
    }

    func testFinishedStaysBoundAsPausedAndReplays() {
        let a = TestSpeech.article(pageA)
        speech.listen(to: a)
        fixture.apple.emit(.finished)
        XCTAssertEqual(speech.playbackPhase, .finished)
        XCTAssertEqual(speech.nowPlaying?.pageKey, a.id, "the finished page stays bound")
        XCTAssertEqual(speech.nowPlaying?.isFinished, true)
        XCTAssertEqual(speech.playState(of: .page(a.id)), .paused)

        let plays = fixture.apple.plays.count
        speech.press(.page(a.id)) { XCTFail("▶ replays what you hear") }
        XCTAssertEqual(speech.playState(of: .page(a.id)), .playing)
        XCTAssertEqual(fixture.apple.plays.count, plays + 1)
        XCTAssertEqual(fixture.apple.plays.last?.utf16Offset, 0, "from the start")
    }

    /// D3 on a one-paragraph article: the replay paragraph is the playhead, so both coordinates
    /// have to reset, or ▶ would carry on from where the voice finished.
    func testFinishedOneParagraphArticleReplaysFromItsStart() {
        let url = URL(string: pageA)!
        let text = "Only one paragraph here. It still has a few sentences in it. This is the last of them."
        let one = ReaderArticle(id: ArticleIdentity.articleKey(canonicalURL: canonical(pageA)), url: url,
                                extracted: ExtractedArticle(title: "One", siteName: nil, cleanedHTML: "<p>\(text)</p>",
                                                            plainText: text, excerpt: ""))
        XCTAssertEqual(one.document.count, 1)
        speech.listen(to: one)
        let nearTheEnd = (text as NSString).length - 10
        fixture.apple.emit(.position(paragraph: 0, utf16: nearTheEnd))
        XCTAssertEqual(speech.spokenUTF16Offset, nearTheEnd)
        fixture.apple.emit(.finished)
        XCTAssertEqual(speech.playbackPhase, .finished)

        speech.press(.page(one.id)) { XCTFail("▶ replays what you hear") }
        XCTAssertEqual(fixture.apple.plays.last?.utf16Offset, 0, "from the start, not where it finished")
        XCTAssertEqual(speech.spokenUTF16Offset, 0)
        XCTAssertEqual(speech.currentParagraphIndex, 0)
    }

    /// Ordinary resume still starts where it paused (a scrubbed sentence of a prepared page).
    func testPreparedPageResumesAtItsSentence() {
        let a = TestSpeech.article(pageA)
        speech.prepare(SpeechSession(article: a))
        let second = a.document.paragraphs[0].firstIndex(of: ".").map {
            a.document.paragraphs[0].utf16.distance(from: a.document.paragraphs[0].startIndex, to: $0) + 2
        }!
        speech.seek(toUTF16Offset: second)
        speech.press(.page(a.id)) { XCTFail("▶ plays what you hear") }
        XCTAssertEqual(fixture.apple.plays.last?.utf16Offset, second, "from the scrubbed sentence")
    }

    func testStopListeningUnbinds() {
        let a = TestSpeech.article(pageA)
        speech.listen(to: a)
        speech.stop()
        XCTAssertNil(speech.nowPlaying, "Stop Listening hides the bar")
        XCTAssertEqual(speech.playState(of: .page(a.id)), .idle)
    }

    func testPressOnSomethingElseRunsStart() {
        let a = TestSpeech.article(pageA)
        speech.listen(to: a)
        var started = false
        speech.press(.page(UUID())) { started = true }
        XCTAssertTrue(started)
        XCTAssertEqual(speech.playState(of: .page(a.id)), .playing, "press itself never replaces")
    }
}
