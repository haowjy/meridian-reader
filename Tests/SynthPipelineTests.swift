import XCTest
@testable import Reader

/// Shared synth pipeline with the fake engine: chunking by capabilities, overflow → re-split,
/// hard failure → Apple fallback (never skip), and queue priority.
@MainActor
final class SynthPipelineTests: XCTestCase {
    private var contexts: [FakeQueueContext] = []

    override func tearDown() async throws {
        contexts.forEach { $0.cleanUp() }
        contexts = []
    }

    private func makeQueue(_ provider: FakeEngineProvider) -> (GlobalSynthQueue, FakeQueueContext) {
        let ctx = FakeQueueContext(provider: provider)
        contexts.append(ctx)
        let queue = GlobalSynthQueue()
        queue.attach(coordinator: ctx)
        return (queue, ctx)
    }

    private func waitIdle(_ queue: GlobalSynthQueue, timeout: TimeInterval = 20) async throws {
        let start = Date()
        try await Task.sleep(nanoseconds: 20_000_000)
        while queue.isWorkerRunning {
            if Date().timeIntervalSince(start) > timeout { XCTFail("worker never went idle"); return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func sentence(_ n: Int) -> String {
        "Sentence number \(n) is here, and it runs on for a little while longer."
    }

    // MARK: - Chunking by capabilities

    func testQueueChunksWithActiveEngineLimits() {
        let provider = FakeEngineProvider(limits: .init(target: 40, hardMax: 50, firstTarget: 30, minResplit: 10))
        let (queue, _) = makeQueue(provider)
        let text = (1...6).map(sentence).joined(separator: " ")
        let chunks = queue.chunkTexts(for: text)
        XCTAssertGreaterThan(chunks.count, 6)
        XCTAssertTrue(chunks.allSatisfy { TextChunker.estimatedUnits($0) <= 50 }, "\(chunks.map(\.count))")
        XCTAssertEqual(chunks.joined(separator: " "), TextChunker.normalize(text))
        // Same text, Kokoro-sized limits → fewer, longer chunks.
        let kokoro = TextChunker.chunks(for: text, limits: FluidAudioProvider.kokoroDescriptor.limits)
        XCTAssertLessThan(kokoro.count, chunks.count)
    }

    // MARK: - Overflow → re-split

    func testOverflowResplitsRecursivelyInSharedRenderer() async throws {
        let provider = FakeEngineProvider(config: .init(maxCharsPerCall: 30))
        let ctx = FakeQueueContext(provider: provider)
        contexts.append(ctx)
        let text = "The ports closed, the farms failed, the grid went dark, and nobody could say when."
        let url = ctx.root.appendingPathComponent("one.caf")
        let duration = try await ctx.chunkRenderer.renderChunk(text: text, to: url, seed: 1, context: [:])
        let calls = ctx.host.calls
        XCTAssertTrue(calls.contains { !$0.ok && $0.text.count > 30 }, "first call overflowed")
        let ok = calls.filter(\.ok)
        XCTAssertGreaterThan(ok.count, 1)
        XCTAssertTrue(ok.allSatisfy { $0.text.count <= 30 })
        XCTAssertEqual(ok.map(\.text).joined(separator: " "), text, "re-split keeps every word, in order")
        XCTAssertEqual(duration, Double(ok.map(\.text.count).reduce(0, +)) * 0.05, accuracy: 0.01)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testResplitGivesUpBelowMinimumAndThrowsInputTooLong() async {
        let provider = FakeEngineProvider(config: .init(maxCharsPerCall: 3))
        let ctx = FakeQueueContext(provider: provider)
        contexts.append(ctx)
        do {
            _ = try await ctx.chunkRenderer.renderChunk(
                text: "Too long for this engine.", to: ctx.root.appendingPathComponent("x.caf"), seed: 1, context: [:])
            XCTFail("expected inputTooLong")
        } catch LocalSynthError.inputTooLong {
            // expected
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    // MARK: - Fail → Apple fallback (never skip)

    func testEngineFailureFallsBackToAppleAndParagraphStillBakes() async throws {
        let provider = FakeEngineProvider(config: .init(failAlways: true))
        let (queue, ctx) = makeQueue(provider)
        let key = UUID()
        let paragraphs = [sentence(1), (1...3).map(sentence).joined(separator: " ")]
        queue.openArticle(cacheKey: key, paragraphs: paragraphs, rate: 1, voiceID: "fake.default", isEphemeral: false)
        try await waitIdle(queue)
        let expectedChunks = paragraphs.map { queue.chunkTexts(for: $0).count }.reduce(0, +)
        XCTAssertEqual(ctx.fallbackTexts.count, expectedChunks, "every chunk rendered by the fallback")
        for i in paragraphs.indices {
            XCTAssertNotNil(ctx.audioCache.audioURL(articleID: key, paragraphIndex: i,
                                                    engineID: ctx.cacheEngineID, voiceID: "fake.default"),
                            "p\(i) baked (not skipped)")
        }
        XCTAssertEqual(ctx.completed, [key])
    }

    func testOverflowThatCannotResplitFallsBackToApple() async throws {
        let provider = FakeEngineProvider(config: .init(maxCharsPerCall: 3))
        let (queue, ctx) = makeQueue(provider)
        let key = UUID()
        queue.openArticle(cacheKey: key, paragraphs: [sentence(7)], rate: 1, voiceID: "v", isEphemeral: false)
        try await waitIdle(queue)
        XCTAssertFalse(ctx.fallbackTexts.isEmpty)
        XCTAssertNotNil(ctx.audioCache.audioURL(articleID: key, paragraphIndex: 0, engineID: ctx.cacheEngineID, voiceID: "v"))
    }

    // MARK: - Queue priority

    /// Regression: `drainPendingIntoQueue` used to `openArticle` any pending job with
    /// `priorityStart > 0`, stealing #1 from the article being listened to.
    func testPendingMidArticleJobDoesNotStealActiveArticle() async throws {
        let provider = FakeEngineProvider()
        let (queue, ctx) = makeQueue(provider)
        queue.isPausedForProbe = true
        let active = UUID(), backgroundMid = UUID(), backgroundTop = UUID()
        let paras = (0..<4).map(sentence)
        queue.openArticle(cacheKey: active, paragraphs: paras, rate: 1, voiceID: "v", resumeParagraph: 2, isEphemeral: false)
        queue.adoptPending([
            .init(cacheKey: backgroundMid, paragraphs: paras, rate: 1, voiceID: "v", priorityStart: 3, isEphemeral: false),
            .init(cacheKey: backgroundTop, paragraphs: paras, rate: 1, voiceID: "v", priorityStart: 0, isEphemeral: true),
        ])
        XCTAssertEqual(queue.primaryCacheKey, active)
        XCTAssertEqual(queue.demotedCount, 2)
        queue.isPausedForProbe = false
        try await waitIdle(queue)
        let order = ctx.renders.filter { $0.c == 0 }.map { ($0.key, $0.p) }
        XCTAssertEqual(order.prefix(4).map(\.0), [active, active, active, active])
        XCTAssertEqual(order.prefix(4).map(\.1), [2, 3, 0, 1], "playhead → end, then gap-fill")
        XCTAssertEqual(order.dropFirst(4).prefix(4).map(\.0), [backgroundMid, backgroundMid, backgroundMid, backgroundMid])
        XCTAssertEqual(order.dropFirst(4).prefix(4).map(\.1), [3, 0, 1, 2], "demoted job kept its mid-article plan")
        XCTAssertEqual(order.dropFirst(8).map(\.0), [backgroundTop, backgroundTop, backgroundTop, backgroundTop])
    }

    func testFocusedArticleIsAdoptedFirstWhenQueueEmpty() {
        let provider = FakeEngineProvider()
        let (queue, _) = makeQueue(provider)
        queue.isPausedForProbe = true
        let other = UUID(), focused = UUID()
        let paras = (0..<3).map(sentence)
        queue.adoptPending([
            .init(cacheKey: other, paragraphs: paras, rate: 1, voiceID: "v", priorityStart: 1, isEphemeral: false),
            .init(cacheKey: focused, paragraphs: paras, rate: 1, voiceID: "v", priorityStart: 2, isEphemeral: false),
        ], focusKey: focused)
        XCTAssertEqual(queue.primaryCacheKey, focused)
        XCTAssertEqual(queue.nextMissingIndex(), 2)
        XCTAssertEqual(queue.demotedCount, 1)
        queue.isPausedForProbe = false
    }
}
