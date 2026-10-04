import XCTest
@testable import Reader

/// Every play button asks one question, `playState(of:)`: is this what you hear, and is it playing.
@MainActor
final class PlayStateTests: XCTestCase {
    private var fixture: TestSpeech!
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

    func testLegacyRandomIDSavedArticleMatchesItsWebPage() {
        // A save from before identity v2 keeps a random id; the page is found by canonical URL.
        let legacy = TestSpeech.article(pageA, id: UUID())
        XCTAssertNotEqual(legacy.id, ArticleIdentity.articleKey(canonicalURL: canonical(pageA)))
        speech.listen(to: legacy)
        XCTAssertEqual(speech.playState(of: .webPage(canonicalURL: canonical(pageA))), .playing)
        XCTAssertEqual(speech.playState(of: .page(legacy.id)), .playing)
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
        speech.beginPreparing(target)
        XCTAssertEqual(speech.playState(of: target), .preparing)
        XCTAssertEqual(speech.playState(of: .page(a.id)), .playing, "what's playing keeps playing meanwhile")
        speech.cancelPreparing()
        XCTAssertEqual(speech.playState(of: target), .idle, "extraction failed: back to grey")
        XCTAssertEqual(speech.nowPlaying?.pageKey, a.id)

        speech.beginPreparing(target)
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
