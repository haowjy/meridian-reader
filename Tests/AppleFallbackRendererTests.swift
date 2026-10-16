import AVFoundation
import XCTest
@testable import MeridianReader

/// The Apple fallback can't stall the render queue or the player.
final class AppleFallbackRendererTests: XCTestCase {
    func testASynthesizerThatNeverCallsBackThrowsAfterTheTimeout() async throws {
        let silent = SilentSynthesizer()
        let renderer = AppleFallbackRenderer(idleTimeout: .milliseconds(200), makeSynthesizer: { silent })
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("apple-fallback-\(UUID().uuidString).caf")
        let start = ContinuousClock.now
        do {
            _ = try await renderer.render(text: "The engine couldn't render this sentence.", to: url, voiceID: nil)
            XCTFail("a synthesizer that never answers must not hang the render")
        } catch is AppleFallbackRenderer.TimedOut {}
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(3))
        XCTAssertTrue(silent.stopped, "the stalled write is stopped")
    }

    /// The queue's fallback and the player's each get a synthesizer: neither waits on the other.
    func testEachRenderWritesThroughItsOwnSynthesizer() async {
        let made = SynthesizerCount()
        let renderer = AppleFallbackRenderer(idleTimeout: .milliseconds(100), makeSynthesizer: {
            made.add()
            return SilentSynthesizer()
        })
        let dir = FileManager.default.temporaryDirectory
        async let first = try? renderer.render(text: "One.", to: dir.appendingPathComponent("a-\(UUID()).caf"), voiceID: nil)
        async let second = try? renderer.render(text: "Two.", to: dir.appendingPathComponent("b-\(UUID()).caf"), voiceID: nil)
        _ = await (first, second)
        XCTAssertEqual(made.value, 2)
    }
}

private final class SilentSynthesizer: SpeechBufferWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var _stopped = false
    var stopped: Bool { lock.withLock { _stopped } }

    func write(_ utterance: AVSpeechUtterance, toBufferCallback bufferCallback: @escaping AVSpeechSynthesizer.BufferCallback) {}

    func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool {
        lock.withLock { _stopped = true }
        return true
    }
}

private final class SynthesizerCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func add() { lock.withLock { count += 1 } }
}
