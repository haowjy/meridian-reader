import SwiftData
import XCTest
@testable import Reader

/// 🎧 extracts its page before it plays. Each tap is its own request: Stop Listening, another ▶
/// or another 🎧 during extraction supersedes it, and only the current request may start.
@MainActor
final class ListenNowTests: XCTestCase {
    private var fixture: TestSpeech!
    private var container: ModelContainer!
    private let extractor = DelayedExtractor()
    private var speech: SpeechController { fixture.speech }

    private let pageA = "https://example.com/a"
    private let pageB = URL(string: "https://example.com/b")!
    private let pageC = URL(string: "https://example.com/c")!

    override func setUp() async throws {
        fixture = TestSpeech()
        container = try ModelContainer(for: SavedArticle.self, RecentVisit.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    override func tearDown() async throws { fixture.tearDown() }

    private func target(_ url: URL) -> ListenTarget {
        .webPage(canonicalURL: ArticleIdentity.canonicalURLString(from: url))
    }

    /// 🎧 on the page at `url`, extracting through `extractor`; returns the running request.
    private func tapListen(_ url: URL) -> Task<ListenNowOutcome, Never> {
        let context = container.mainContext
        let extractor = extractor
        let speech = speech
        return Task {
            await PageArticleService.listen(toPageAt: url, speech: speech, context: context) {
                let extracted = try await extractor.extract(from: ExtractionContext(url: url, pageTitle: nil,
                                                                                    htmlSnapshot: ""))
                return ArticleLibrary.readerArticle(url: url, extracted: extracted, in: context)
            }
        }
    }

    private func playA() -> ReaderArticle {
        let a = TestSpeech.article(pageA)
        speech.listen(to: a)
        return a
    }

    func testReadyPageReplacesWhatIsPlaying() async throws {
        let a = playA()
        let request = tapListen(pageB)
        try await extractor.waitForPending()
        XCTAssertEqual(speech.playState(of: target(pageB)), .preparing)
        XCTAssertEqual(speech.playState(of: .page(a.id)), .playing, "A plays while B extracts")

        extractor.finish(with: DelayedExtractor.article(title: "B"))
        guard case .started = await request.value else { return XCTFail("B starts") }
        XCTAssertEqual(speech.playState(of: target(pageB)), .playing)
        XCTAssertEqual(speech.playState(of: .page(a.id)), .idle)
    }

    func testStopListeningDuringExtractionStartsNothing() async throws {
        _ = playA()
        let request = tapListen(pageB)
        try await extractor.waitForPending()
        let plays = fixture.apple.plays.count

        speech.stop()
        XCTAssertEqual(speech.playState(of: target(pageB)), .idle, "Stop Listening ends the request")
        extractor.finish(with: DelayedExtractor.article(title: "B"))
        guard case .superseded = await request.value else { return XCTFail("B was superseded") }
        XCTAssertNil(speech.nowPlaying, "nothing plays after Stop Listening")
        XCTAssertEqual(fixture.apple.plays.count, plays)
    }

    func testSavedRowPlayDuringExtractionWins() async throws {
        _ = playA()
        let c = ArticleLibrary.save(ReaderArticle(id: ArticleIdentity.articleKey(
            canonicalURL: ArticleIdentity.canonicalURLString(from: pageC)), url: pageC,
            extracted: DelayedExtractor.article(title: "C")), in: container.mainContext)
        let request = tapListen(pageB)
        try await extractor.waitForPending()

        // The Saved row's ▶ (SavedListView).
        speech.press(.page(c.id)) {
            speech.toggle(.saved(c), resumeParagraph: c.playbackParagraphIndex,
                          resumeUTF16Offset: c.playbackUTF16Offset)
        }
        XCTAssertEqual(speech.playState(of: .page(c.id)), .playing)
        XCTAssertEqual(speech.playState(of: target(pageB)), .idle)

        extractor.finish(with: DelayedExtractor.article(title: "B"))
        guard case .superseded = await request.value else { return XCTFail("B was superseded") }
        XCTAssertEqual(speech.nowPlaying?.pageKey, c.id, "C keeps playing")
        XCTAssertEqual(speech.playState(of: .page(c.id)), .playing)
    }

    func testPausingWhatYouHearDuringExtractionStartsNothing() async throws {
        let a = playA()
        let request = tapListen(pageB)
        try await extractor.waitForPending()

        speech.press(.page(a.id)) { XCTFail("A pauses") }
        extractor.finish(with: DelayedExtractor.article(title: "B"))
        guard case .superseded = await request.value else { return XCTFail("B was superseded") }
        XCTAssertEqual(speech.nowPlaying?.pageKey, a.id)
        XCTAssertEqual(speech.playState(of: .page(a.id)), .paused, "A stays paused")
    }

    func testExtractorThrowingChangesNothing() async throws {
        let a = playA()
        let request = tapListen(pageB)
        try await extractor.waitForPending()

        extractor.fail()
        guard case .nothingToListenTo = await request.value else { return XCTFail("says so") }
        XCTAssertEqual(speech.playState(of: target(pageB)), .idle, "back to grey")
        XCTAssertEqual(speech.playState(of: .page(a.id)), .playing, "A keeps playing")
    }

    func testOnlyTheNewestTapStarts() async throws {
        _ = playA()
        let first = tapListen(pageB)
        try await extractor.waitForPending(1)
        let second = tapListen(pageB)
        try await extractor.waitForPending(2)

        // The older request failing doesn't clear the newer one on the same page.
        extractor.fail()
        guard case .superseded = await first.value else { return XCTFail("the first tap was superseded") }
        XCTAssertEqual(speech.playState(of: target(pageB)), .preparing, "the second tap is still preparing")

        extractor.finish(with: DelayedExtractor.article(title: "B"))
        guard case .started = await second.value else { return XCTFail("the second tap starts") }
        XCTAssertEqual(speech.playState(of: target(pageB)), .playing)
    }

    func testAnotherPagesTapWins() async throws {
        _ = playA()
        let b = tapListen(pageB)
        try await extractor.waitForPending(1)
        let c = tapListen(pageC)
        try await extractor.waitForPending(2)

        extractor.finish(with: DelayedExtractor.article(title: "B"))
        guard case .superseded = await b.value else { return XCTFail("B was superseded by C") }
        extractor.finish(with: DelayedExtractor.article(title: "C"))
        guard case .started = await c.value else { return XCTFail("C starts") }
        XCTAssertEqual(speech.playState(of: target(pageC)), .playing)
        XCTAssertEqual(speech.playState(of: target(pageB)), .idle)
    }
}
