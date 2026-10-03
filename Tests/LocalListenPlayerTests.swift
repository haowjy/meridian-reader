import AVFoundation
import XCTest
@testable import Reader

/// The local listen player over a fake unit source. The producer fills the player buffer and then
/// stops; the next unit to end starts it again (no polling while the buffer is full). The
/// article's end is reported once, by the player. A play or stop during the model load wins over
/// the play that was waiting. Units are long tones that never end on their own during a test:
/// the test ends them through the player's delegate entry point, so nothing waits on wall-clock
/// audio.
@MainActor
final class LocalListenPlayerTests: XCTestCase {
    private var tempFiles: [URL] = []

    override func tearDown() {
        for url in tempFiles { try? FileManager.default.removeItem(at: url) }
        super.tearDown()
    }

    private func tone(seconds: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("producer-\(UUID().uuidString).caf")
        tempFiles.append(url)
        try LocalPCMWriter.write(FakeSynthHost.tone(seconds: seconds, sampleRate: 24_000), sampleRate: 24_000, to: url)
        return url
    }

    private func makePlayer(_ queue: ChunkPlaybackQueue) -> LocalListenPlayer {
        LocalListenPlayer(player: queue)
    }

    /// The unit playing now ends (as `AVAudioPlayer` reports it).
    private func endCurrentUnit(_ queue: ChunkPlaybackQueue, file: URL) throws {
        queue.audioPlayerDidFinishPlaying(try AVAudioPlayer(contentsOf: file), successfully: true)
    }

    /// Let main-actor work queued so far (the producer task) run. Bounded, no clock.
    private func settle(until condition: () -> Bool = { false }) async {
        for _ in 0..<200 where !condition() { await Task.yield() }
    }

    /// Wait (bounded, no clock) until an async condition holds.
    private func settleAsync(until condition: () async -> Bool) async {
        for _ in 0..<500 { if await condition() { return }; await Task.yield() }
    }

    func testProducerStopsWhileTheBufferIsFullAndRestartsWhenAUnitEnds() async throws {
        let queue = ChunkPlaybackQueue(maxBuffered: 8)
        let baked = try tone(seconds: 30)
        let player = makePlayer(queue)
        defer { player.stop() }

        // Every paragraph is rendered: the buffer (8 units) fills at once.
        let source = FakeUnitSource(paragraphs: (0..<12).map { "Paragraph \($0)." }, rendered: baked)
        try await player.play(source, from: 0, chunk: 0, fractionInChunk: 0)
        await settle { player.debugNextProduceIndex == 8 && !player.debugProducerActive }
        XCTAssertEqual(player.debugBufferedCount, 8)
        XCTAssertEqual(player.debugNextProduceIndex, 8)
        XCTAssertFalse(player.debugProducerActive, "full buffer: the producer stops instead of polling")

        // A unit ends → the producer runs again and refills.
        try endCurrentUnit(queue, file: baked)
        await settle { player.debugNextProduceIndex == 9 && !player.debugProducerActive }
        XCTAssertEqual(player.debugNextProduceIndex, 9)
        XCTAssertEqual(player.debugBufferedCount, 8)
        XCTAssertFalse(player.debugProducerActive)
    }

    func testArticleEndIsReportedOnce() async throws {
        let queue = ChunkPlaybackQueue(maxBuffered: 8)
        let baked = try tone(seconds: 30)
        let player = makePlayer(queue)
        defer { player.stop() }
        var finished = 0
        player.onFinished = { finished += 1 }

        try await player.play(FakeUnitSource(paragraphs: ["One.", "Two."], rendered: baked),
                              from: 0, chunk: 0, fractionInChunk: 0)
        await settle { !player.debugProducerActive && player.debugBufferedCount == 2 }
        XCTAssertEqual(player.debugBufferedCount, 2)
        XCTAssertFalse(player.debugAwaitingMore, "everything produced")

        try endCurrentUnit(queue, file: baked)
        await settle()
        XCTAssertEqual(finished, 0, "paragraph 2 is still playing")

        try endCurrentUnit(queue, file: baked)
        await settle()
        XCTAssertEqual(finished, 1)
        XCTAssertFalse(player.isSpeaking)
    }

    func testAChunkTheEngineCannotRenderPlaysWithApple() async throws {
        let queue = ChunkPlaybackQueue(maxBuffered: 8)
        let player = makePlayer(queue)
        defer { player.stop() }
        let source = FakeUnitSource(paragraphs: ["Only paragraph."], rendered: nil)

        try await player.play(source, from: 0, chunk: 0, fractionInChunk: 0)
        await settle { queue.currentParagraphIndex == 0 }
        XCTAssertEqual(source.appleRenders, ["Only paragraph."], "never a silent skip")
        XCTAssertEqual(queue.currentPosition?.item.source, .appleFallback(fromChunk: 0, reason: .engineError))
        XCTAssertEqual(player.currentAppleFallbackReason, .engineError)
    }

    func testSecondPlayDuringTheModelLoadPlaysTheSecondRequest() async throws {
        let gate = TestGate()
        let queue = ChunkPlaybackQueue(maxBuffered: 8)
        let baked = try tone(seconds: 30)
        let player = makePlayer(queue)
        defer { player.stop() }

        let a = FakeUnitSource(paragraphs: ["A0.", "A1."], rendered: baked, prepareGate: gate)
        let first = Task { try await player.play(a, from: 0, chunk: 0, fractionInChunk: 0) }
        await settleAsync { await gate.waiting == 1 }
        let b = FakeUnitSource(paragraphs: (0..<6).map { "B\($0)." }, rendered: baked, prepareGate: gate)
        let second = Task { try await player.play(b, from: 3, chunk: 0, fractionInChunk: 0) }
        await settleAsync { await gate.waiting == 2 }
        XCTAssertEqual(queue.bufferedCount, 0, "nothing plays while the model loads")

        await gate.open()
        _ = try? await first.value
        try await second.value
        await settle { queue.currentParagraphIndex == 3 && !player.debugProducerActive }
        XCTAssertEqual(queue.currentParagraphIndex, 3, "the second request plays")
        XCTAssertEqual(player.debugBufferedCount, 3, "B3…B5 only; nothing of the first request")
        XCTAssertFalse(player.debugProducerActive)
        XCTAssertEqual(player.playingArticleID, b.articleID)
    }

    func testStopDuringTheModelLoadLeavesThePlayerSilent() async throws {
        let gate = TestGate()
        let queue = ChunkPlaybackQueue(maxBuffered: 8)
        let baked = try tone(seconds: 30)
        let player = makePlayer(queue)
        defer { player.stop() }

        let source = FakeUnitSource(paragraphs: ["One.", "Two."], rendered: baked, prepareGate: gate)
        let play = Task { try await player.play(source, from: 0, chunk: 0, fractionInChunk: 0) }
        await settleAsync { await gate.waiting == 1 }
        player.stop()
        await gate.open()
        _ = try? await play.value
        await settle()
        XCTAssertEqual(queue.bufferedCount, 0, "stopped before the load finished: nothing plays")
        XCTAssertFalse(player.isSpeaking)
        XCTAssertFalse(player.debugProducerActive)
    }

    func testEndOfInputWhileIdleFinishesUnlessPaused() {
        let player = ChunkPlaybackQueue()
        var finished = 0
        player.onFinished = { finished += 1 }

        player.awaitingMore = true
        player.pause()
        player.endOfInput()
        XCTAssertEqual(finished, 0, "paused: Resume finishes")
        player.resume()
        XCTAssertEqual(finished, 1)

        player.clear()
        XCTAssertEqual(finished, 1, "stop is not an end")
    }
}
