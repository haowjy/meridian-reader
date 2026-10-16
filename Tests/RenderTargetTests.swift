import AVFoundation
import XCTest
@testable import MeridianReader

/// The render queue renders for one target, owned by the coordinator: the loaded on-device engine
/// in its selected voice. Turning the engine off parks the queue (no model is loaded again behind
/// Settings' back), a voice switch never files one voice's chunk under the other, and a chunk the
/// engine can't render falls back to the Apple voice the player uses for the article.
@MainActor
final class RenderTargetTests: XCTestCase {
    private var cleanups: [() -> Void] = []

    override func tearDown() async throws {
        cleanups.forEach { $0() }
        cleanups = []
    }

    private func makeCoordinator(_ provider: FakeEngineProvider) -> LocalTTSCoordinator {
        let stack = TestSpeech(providers: [provider], selected: FakeEngineProvider.fakeID)
        cleanups.append { stack.tearDown() }
        return stack.tts
    }

    private func makeQueue(_ provider: FakeEngineProvider) -> (GlobalSynthQueue, FakeQueueContext) {
        let ctx = FakeQueueContext(provider: provider)
        cleanups.append { ctx.cleanUp() }
        let queue = GlobalSynthQueue()
        queue.attach(coordinator: ctx)
        return (queue, ctx)
    }

    private func waitUntil(_ timeout: TimeInterval = 10, _ condition: () -> Bool) async throws {
        let start = Date()
        while !condition() {
            if Date().timeIntervalSince(start) > timeout { XCTFail("timed out"); return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    private func waitIdle(_ queue: GlobalSynthQueue, timeout: TimeInterval = 20) async throws {
        try await Task.sleep(nanoseconds: 20_000_000)
        try await waitUntil(timeout) { !queue.isWorkerRunning }
    }

    private func paragraphs(_ count: Int) -> [String] {
        (0..<count).map { "Paragraph \($0) has a few words in it." }
    }

    // MARK: - The engine turned off

    /// Apple picked, or the model deleted, while the queue bakes: the host's calls stop (the one
    /// in flight may finish), no host is built again, and nothing more is filed. Picking the engine
    /// again renders the rest.
    func testTurningTheEngineOffStopsTheQueueUntilItIsBack() async throws {
        for turnOff in ["apple", "delete"] {
            let provider = FakeEngineProvider(config: .init(latency: 0.05))
            let c = makeCoordinator(provider)
            await c.selectEngine(FakeEngineProvider.fakeID)
            XCTAssertNotNil(c.renderTarget)
            let key = UUID()
            let text = paragraphs(20)
            c.synthQueue.enqueue(cacheKey: key, paragraphs: text, isEphemeral: false, at: .front)
            let host = try XCTUnwrap(provider.lastHost)
            try await waitUntil { host.calls.count >= 3 }

            if turnOff == "apple" {
                await c.selectEngine(.apple)
            } else {
                try c.deleteModel()
                provider.installed = true // the files come back with the next pick
            }
            XCTAssertNil(c.renderTarget, turnOff)
            let callsAtTurnOff = host.calls.count
            try await waitIdle(c.synthQueue)
            try await Task.sleep(nanoseconds: 200_000_000)
            XCTAssertLessThanOrEqual(host.calls.count, callsAtTurnOff + 1, "\(turnOff): only the call in flight finished")
            XCTAssertTrue(provider.lastHost === host, "\(turnOff): no host was built again")
            XCTAssertTrue(c.synthQueue.hasJob(cacheKey: key), "\(turnOff): the bake waits for the engine")
            let ready = c.audioCache.readyIndices(articleID: key, paragraphCount: text.count,
                                                  engineID: FakeEngineProvider.fakeID.rawValue, voiceID: "fake.default")
            XCTAssertLessThan(ready.count, text.count, turnOff)

            await c.selectEngine(FakeEngineProvider.fakeID)
            try await waitIdle(c.synthQueue)
            XCTAssertEqual(c.audioCache.readyIndices(articleID: key, paragraphCount: text.count,
                                                     engineID: FakeEngineProvider.fakeID.rawValue, voiceID: "fake.default").count,
                           text.count, "\(turnOff): the bake finished once the engine was back")
        }
    }

    // MARK: - A voice switch mid-call

    /// The voice changes while a chunk renders in the old one: that chunk is never stitched into
    /// the new voice's paragraph or handed to a listener in the new voice. Every chunk of the
    /// published paragraph has the new voice's length.
    func testAVoiceSwitchDuringAChunkLeavesNoOldVoiceAudioInTheNewVoice() async throws {
        let config = FakeSynthHost.Config(latency: 0.3, secondsPerCharByVoice: ["a": 0.02, "b": 0.06])
        let (queue, ctx) = makeQueue(FakeEngineProvider(config: config))
        ctx.host.setVoice("a")
        ctx.renderTarget?.cacheVoice = "fake.a"
        let key = UUID()
        let text = (1...4).map { "Sentence \($0) is here and it runs on for a while longer." }.joined(separator: " ")
        let chunks = queue.chunkTexts(for: text)
        XCTAssertGreaterThanOrEqual(chunks.count, 2)
        queue.enqueue(cacheKey: key, paragraphs: [text], isEphemeral: false, at: .front)
        try await waitUntil { ctx.host.startedCalls == 1 } // chunk 0 is rendering in voice A

        ctx.host.setVoice("b")
        ctx.renderTarget?.cacheVoice = "fake.b"
        queue.renderTargetChanged()
        let resolution = try await queue.ensureChunk(cacheKey: key, paragraphIndex: 0, chunk: 0, text: text,
                                                     paragraphs: [text], isEphemeral: false)
        let chunk0: Double
        switch resolution {
        case .chunk(let url):
            let file = try AVAudioFile(forReading: url)
            chunk0 = Double(file.length) / file.processingFormat.sampleRate
        case .paragraph:
            chunk0 = try XCTUnwrap(ctx.audioCache.entry(articleID: key, paragraphIndex: 0)?.chunkDurations?.first)
        }
        XCTAssertEqual(chunk0, Double(chunks[0].count) * 0.06, accuracy: 0.01, "the listener got chunk 0 in the new voice")
        try await waitIdle(queue)

        let cache = ctx.audioCache
        XCTAssertEqual(cache.readyIndices(articleID: key, paragraphCount: 1, engineID: ctx.cacheEngineID, voiceID: "fake.b"), [0])
        let durations = try XCTUnwrap(cache.entry(articleID: key, paragraphIndex: 0)?.chunkDurations)
        XCTAssertEqual(durations.count, chunks.count)
        for (i, d) in durations.enumerated() {
            XCTAssertEqual(d, Double(chunks[i].count) * 0.06, accuracy: 0.01, "chunk \(i) is in the new voice")
        }
    }

    // MARK: - The Apple fallback

    /// A chunk the engine can't render is rendered by Apple in the voice the app gives the
    /// article (the user's pick for its language), as the player's own fallback is.
    func testTheQueuesAppleFallbackUsesTheArticlesAppleVoice() async throws {
        let (queue, ctx) = makeQueue(FakeEngineProvider(config: .init(failAlways: true)))
        ctx.appleVoice = "com.example.voice.premium.en-US.Zoe"
        let key = UUID()
        queue.enqueue(cacheKey: key, paragraphs: paragraphs(2), isEphemeral: false, at: .front)
        try await waitIdle(queue)
        XCTAssertEqual(ctx.fallbackVoices.count, 2)
        XCTAssertEqual(Set(ctx.fallbackVoices), ["com.example.voice.premium.en-US.Zoe"])
    }
}
