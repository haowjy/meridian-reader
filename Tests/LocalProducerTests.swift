import XCTest
@testable import Reader

/// The local engine's producer fills the player buffer and then stops; the next unit to end
/// starts it again (no polling while the buffer is full).
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

    func testProducerStopsWhileTheBufferIsFullAndRestartsWhenAUnitEnds() async throws {
        let registry = EngineRegistry(providers: [AppleSpeechProvider(), FakeEngineProvider()], gate: { _ in true })
        let engine = LocalModelSpeechEngine(engines: registry)
        engine.resumePointStore = nil
        engine.setActiveLocalEngine(FakeEngineProvider.fakeID, voice: nil)
        let baked = try tone(seconds: 0.15)
        engine.bakedURLProvider = { _ in baked }
        defer { engine.stop() }

        // Every paragraph is baked: the buffer (8 units) fills at once.
        try await engine.speak(paragraphs: (0..<12).map { "Paragraph \($0)." }, startingAt: 0, chunk: 0,
                               fractionInChunk: 0, voiceID: nil)
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(engine.debugBufferedCount, 8)
        XCTAssertEqual(engine.debugNextProduceIndex, 8)
        XCTAssertFalse(engine.debugProducerActive, "full buffer: the producer stops instead of polling")

        // A unit ends → the producer runs again and refills.
        let deadline = Date().addingTimeInterval(5)
        while engine.debugNextProduceIndex == 8, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertGreaterThan(engine.debugNextProduceIndex, 8)
    }
}
