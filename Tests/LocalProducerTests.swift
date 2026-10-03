import AVFoundation
import XCTest
@testable import Reader

/// The local engine's producer fills the player buffer and then stops; the next unit to end
/// starts it again (no polling while the buffer is full). The article's end is reported once,
/// by the player. Units are long tones that never end on their own during a test: the test ends
/// them through the player's delegate entry point, so nothing waits on wall-clock audio.
@MainActor
final class LocalProducerTests: XCTestCase {
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

    /// Engine over a fake on-device engine whose every paragraph is baked (`baked` URL).
    private func makeEngine(player: ChunkPlaybackQueue, baked: URL,
                            prepareGate: TestGate? = nil) -> LocalModelSpeechEngine {
        let provider = FakeEngineProvider(config: .init(prepareGate: prepareGate))
        let registry = EngineRegistry(providers: [AppleSpeechProvider(), provider], gate: { _ in true })
        let engine = LocalModelSpeechEngine(engines: registry, player: player)
        engine.resumePointStore = nil
        engine.setActiveLocalEngine(FakeEngineProvider.fakeID, voice: nil)
        engine.bakedURLProvider = { _ in baked }
        return engine
    }

    /// The unit playing now ends (as `AVAudioPlayer` reports it).
    private func endCurrentUnit(_ player: ChunkPlaybackQueue, file: URL) throws {
        player.audioPlayerDidFinishPlaying(try AVAudioPlayer(contentsOf: file), successfully: true)
    }

    /// Let main-actor work queued so far (the producer task) run. Bounded, no clock.
    private func settle(until condition: () -> Bool = { false }) async {
        for _ in 0..<200 where !condition() { await Task.yield() }
    }

    func testProducerStopsWhileTheBufferIsFullAndRestartsWhenAUnitEnds() async throws {
        let player = ChunkPlaybackQueue(maxBuffered: 8)
        let baked = try tone(seconds: 30)
        let engine = makeEngine(player: player, baked: baked)
        defer { engine.stop() }

        // Every paragraph is baked: the buffer (8 units) fills at once.
        try await engine.speak(paragraphs: (0..<12).map { "Paragraph \($0)." }, startingAt: 0, chunk: 0,
                               fractionInChunk: 0, voiceID: nil)
        await settle { engine.debugNextProduceIndex == 8 && !engine.debugProducerActive }
        XCTAssertEqual(engine.debugBufferedCount, 8)
        XCTAssertEqual(engine.debugNextProduceIndex, 8)
        XCTAssertFalse(engine.debugProducerActive, "full buffer: the producer stops instead of polling")

        // A unit ends → the producer runs again and refills.
        try endCurrentUnit(player, file: baked)
        await settle { engine.debugNextProduceIndex == 9 && !engine.debugProducerActive }
        XCTAssertEqual(engine.debugNextProduceIndex, 9)
        XCTAssertEqual(engine.debugBufferedCount, 8)
        XCTAssertFalse(engine.debugProducerActive)
    }

    func testArticleEndIsReportedOnce() async throws {
        let player = ChunkPlaybackQueue(maxBuffered: 8)
        let baked = try tone(seconds: 30)
        let engine = makeEngine(player: player, baked: baked)
        defer { engine.stop() }
        var finished = 0
        engine.onFinished = { finished += 1 }

        try await engine.speak(paragraphs: ["One.", "Two."], startingAt: 0, chunk: 0, fractionInChunk: 0, voiceID: nil)
        await settle { !engine.debugProducerActive && engine.debugBufferedCount == 2 }
        XCTAssertEqual(engine.debugBufferedCount, 2)
        XCTAssertFalse(engine.debugAwaitingMore, "everything produced")

        try endCurrentUnit(player, file: baked)
        await settle()
        XCTAssertEqual(finished, 0, "paragraph 2 is still playing")

        try endCurrentUnit(player, file: baked)
        await settle()
        XCTAssertEqual(finished, 1)
        XCTAssertFalse(engine.isSpeaking)
    }

    /// Wait (bounded, no clock) until an async condition holds.
    private func settleAsync(until condition: () async -> Bool) async {
        for _ in 0..<500 { if await condition() { return }; await Task.yield() }
    }

    func testSecondSpeakDuringTheModelLoadPlaysTheSecondRequest() async throws {
        let gate = TestGate()
        let player = ChunkPlaybackQueue(maxBuffered: 8)
        let baked = try tone(seconds: 30)
        let engine = makeEngine(player: player, baked: baked, prepareGate: gate)
        defer { engine.stop() }

        let first = Task { try await engine.speak(paragraphs: ["A0.", "A1."], startingAt: 0, chunk: 0,
                                                  fractionInChunk: 0, voiceID: nil) }
        await settleAsync { await gate.waiting == 1 }
        let second = Task { try await engine.speak(paragraphs: (0..<6).map { "B\($0)." }, startingAt: 3, chunk: 0,
                                                   fractionInChunk: 0, voiceID: nil) }
        await settleAsync { await gate.waiting == 2 }
        XCTAssertEqual(player.bufferedCount, 0, "nothing plays while the model loads")

        await gate.open()
        _ = try? await first.value
        try await second.value
        await settle { player.currentParagraphIndex == 3 && !engine.debugProducerActive }
        XCTAssertEqual(player.currentParagraphIndex, 3, "the second request plays")
        XCTAssertEqual(engine.debugBufferedCount, 3, "B3…B5 only; nothing of the first request")
        XCTAssertFalse(engine.debugProducerActive)
    }

    func testStopDuringTheModelLoadLeavesTheEngineSilent() async throws {
        let gate = TestGate()
        let player = ChunkPlaybackQueue(maxBuffered: 8)
        let baked = try tone(seconds: 30)
        let engine = makeEngine(player: player, baked: baked, prepareGate: gate)
        defer { engine.stop() }

        let speak = Task { try await engine.speak(paragraphs: ["One.", "Two."], startingAt: 0, chunk: 0,
                                                  fractionInChunk: 0, voiceID: nil) }
        await settleAsync { await gate.waiting == 1 }
        engine.stop()
        await gate.open()
        _ = try? await speak.value
        await settle()
        XCTAssertEqual(player.bufferedCount, 0, "stopped before the load finished: nothing plays")
        XCTAssertFalse(engine.isSpeaking)
        XCTAssertFalse(engine.debugProducerActive)
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
