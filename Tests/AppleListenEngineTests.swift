import AVFoundation
import XCTest
@testable import Reader

/// Apple's article end is the live utterance's `didFinish`, not a guess from the last word's
/// offset; callbacks from an utterance that was stopped or replaced are dropped.
@MainActor
final class AppleListenEngineTests: XCTestCase {
    /// Ends on a word longer than 8 UTF-16 units: `willSpeakRange` reports its start, well before
    /// the end of the text.
    private let document = ParagraphDocument(parts: [
        "A long paragraph that the synthesizer takes a good while to speak, sentence after sentence. "
            + String(repeating: "Another clause keeps it going for a while longer. ", count: 8)
            + "It closes with a moment of understanding.",
    ])

    private func request(at offset: Int = 0) -> ListenPlayRequest {
        ListenPlayRequest(articleID: UUID(), document: document, utf16Offset: offset, startPaused: false, appleVoice: nil)
    }

    /// Let the delegate's main-actor hops run. Bounded, no clock.
    private func settle() async {
        for _ in 0..<50 { await Task.yield() }
    }

    func testLiveUtteranceFinishingEndsTheArticleWhateverWordItLastReported() async throws {
        let engine = AppleListenEngine()
        defer { engine.stop() }
        var events: [PlaybackEngineEvent] = []
        engine.onEvent = { events.append($0) }
        engine.play(request())
        let utterance = try XCTUnwrap(engine.utterance)

        let text = document.joinedText as NSString
        let lastWord = text.range(of: "understanding.")
        engine.speechSynthesizer(AVSpeechSynthesizer(), willSpeakRangeOfSpeechString: lastWord, utterance: utterance)
        engine.speechSynthesizer(AVSpeechSynthesizer(), didFinish: utterance)
        await settle()

        XCTAssertTrue(events.contains(.playheadAdvanced(paragraph: 0, utf16Offset: lastWord.location)))
        XCTAssertEqual(events.filter { $0 == .finished }.count, 1)
        XCTAssertNil(engine.utterance)
    }

    func testStoppedOrReplacedUtteranceIsNotTheEnd() async throws {
        let engine = AppleListenEngine()
        defer { engine.stop() }
        var events: [PlaybackEngineEvent] = []
        engine.onEvent = { events.append($0) }

        engine.play(request())
        let replaced = try XCTUnwrap(engine.utterance)
        engine.play(request(at: 10)) // speed change / seek: a new utterance
        let live = try XCTUnwrap(engine.utterance)
        engine.speechSynthesizer(AVSpeechSynthesizer(), willSpeakRangeOfSpeechString: NSRange(location: 400, length: 4),
                                 utterance: replaced)
        engine.speechSynthesizer(AVSpeechSynthesizer(), didFinish: replaced)
        await settle()
        XCTAssertFalse(events.contains(.finished), "the replaced utterance's finish is not the article's end")
        // Its late progress, read against the live utterance's base (10) or its own (0), is dropped.
        XCTAssertFalse(events.contains(.playheadAdvanced(paragraph: 0, utf16Offset: 410)))
        XCTAssertFalse(events.contains(.playheadAdvanced(paragraph: 0, utf16Offset: 400)))

        engine.stop()
        engine.speechSynthesizer(AVSpeechSynthesizer(), didFinish: live)
        await settle()
        XCTAssertFalse(events.contains(.finished), "stopped is not finished")
    }
}
