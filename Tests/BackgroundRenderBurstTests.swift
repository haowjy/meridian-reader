import XCTest
@testable import MeridianReader

/// In the background, on a route that renders there (Kokoro's ONNX CPU route), bake-ahead of the
/// playing article runs in bursts: one starts below the low-water mark of listening ready ahead
/// and stops at the high-water mark; between them nothing new starts, and playback wakes the
/// worker. A listener's chunk renders regardless; foreground and inactive ignore the marks. The
/// listening ready ahead is scripted (`FakeQueueContext.readyAhead`), each render adding a minute.
@MainActor
final class BackgroundRenderBurstTests: XCTestCase {
    private var cleanups: [() -> Void] = []
    private let low = BackgroundRenderWatermarks.lowWater
    private let high = BackgroundRenderWatermarks.highWater

    override func tearDown() async throws {
        cleanups.reversed().forEach { $0() }
        cleanups = []
    }

    // MARK: - Watermarks

    func testABurstStartsBelowLowWaterStopsAtHighWaterAndHoldsInBetween() {
        var marks = BackgroundRenderWatermarks()
        XCTAssertNil(marks.update(readyAhead: high + 60), "plenty ahead: no burst")
        XCTAssertNil(marks.update(readyAhead: low), "at the low-water mark: still none")
        XCTAssertFalse(marks.isBursting)
        XCTAssertEqual(marks.update(readyAhead: low - 1), .started)
        XCTAssertNil(marks.update(readyAhead: (low + high) / 2), "between the marks a burst carries on")
        XCTAssertTrue(marks.isBursting)
        XCTAssertEqual(marks.update(readyAhead: high), .stoppedAtHighWater)
        XCTAssertNil(marks.update(readyAhead: (low + high) / 2), "between the marks nothing new starts")
        XCTAssertFalse(marks.isBursting)
        XCTAssertEqual(marks.update(readyAhead: 0), .started)
        XCTAssertTrue(marks.end(), "ended while running")
        XCTAssertFalse(marks.end())
        XCTAssertFalse(marks.isBursting)
    }

    // MARK: - Render queue

    private func makeQueue(phase: AppRunState.Phase) -> (GlobalSynthQueue, FakeQueueContext, AppRunState) {
        let state = AppRunState(phase: phase)
        let provider = FakeEngineProvider(config: .init(rendersInBackground: true))
        let ctx = FakeQueueContext(provider: provider, runState: state)
        cleanups.append { ctx.cleanUp() }
        let queue = GlobalSynthQueue()
        queue.usesBackgroundGrace = false
        queue.runState = state
        queue.attach(coordinator: ctx)
        return (queue, ctx, state)
    }

    private func waitIdle(_ queue: GlobalSynthQueue) async throws {
        let start = Date()
        try await Task.sleep(nanoseconds: 30_000_000)
        while queue.isWorkerRunning {
            if Date().timeIntervalSince(start) > 20 { XCTFail("worker never went idle"); return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    /// One short paragraph per synth chunk.
    private func paragraphs(_ name: String, _ count: Int) -> [String] {
        (1...count).map { "\(name) paragraph \($0) is short." }
    }

    func testAboveTheHighWaterMarkNothingIsBakedAhead() async throws {
        let (queue, ctx, _) = makeQueue(phase: .background)
        let playing = UUID()
        ctx.playingCacheKey = playing
        ctx.readyAhead = { [high] in high + 60 }
        queue.openArticle(cacheKey: playing, paragraphs: paragraphs("Playing", 4), isEphemeral: false)
        try await waitIdle(queue)
        XCTAssertTrue(ctx.renders.isEmpty)
    }

    func testBetweenTheMarksNoBurstStarts() async throws {
        let (queue, ctx, _) = makeQueue(phase: .background)
        let playing = UUID()
        ctx.playingCacheKey = playing
        ctx.readyAhead = { [low, high] in (low + high) / 2 }
        queue.openArticle(cacheKey: playing, paragraphs: paragraphs("Playing", 4), isEphemeral: false)
        try await waitIdle(queue)
        queue.playbackAdvanced()
        try await waitIdle(queue)
        XCTAssertTrue(ctx.renders.isEmpty)
    }

    /// Below the low-water mark a burst renders until the high-water mark, then the worker idles;
    /// playback in the band between the marks doesn't wake it, and once below the low-water mark
    /// again it does.
    func testABurstRendersFromBelowLowWaterToHighWaterThenIdlesUntilPlaybackDrainsIt() async throws {
        let (queue, ctx, _) = makeQueue(phase: .background)
        let playing = UUID()
        ctx.playingCacheKey = playing
        var played: TimeInterval = 0
        ctx.readyAhead = { [unowned ctx] in 200 + 60 * Double(ctx.renders.count) - played }
        queue.openArticle(cacheKey: playing, paragraphs: paragraphs("Playing", 14), isEphemeral: false)
        try await waitIdle(queue)
        XCTAssertEqual(ctx.renders.count, 5, "200 s + 5 × 60 s reaches the high-water mark (480 s)")
        XCTAssertFalse(queue.isWorkerRunning, "idle between bursts")

        played = 150 // 350 s ahead: between the marks
        queue.playbackAdvanced()
        try await waitIdle(queue)
        XCTAssertEqual(ctx.renders.count, 5, "no burst between the marks")

        played = 300 // 200 s ahead: below the low-water mark
        queue.playbackAdvanced()
        try await waitIdle(queue)
        XCTAssertEqual(ctx.renders.count, 10, "the next burst again stops at the high-water mark")
        XCTAssertEqual(ctx.renders.map(\.p), Array(0..<10), "in reading order")
    }

    /// Listening from mid-article: in the background the burst renders from the playhead to the end,
    /// not the paragraphs above it (the readiness ahead can't grow from them); those render in front.
    func testInTheBackgroundOnlyTheParagraphsFromThePlayheadOnRender() async throws {
        let (queue, ctx, state) = makeQueue(phase: .background)
        let playing = UUID()
        ctx.playingCacheKey = playing
        queue.openArticle(cacheKey: playing, paragraphs: paragraphs("Playing", 6), resumeParagraph: 3,
                          isEphemeral: false)
        try await waitIdle(queue)
        XCTAssertEqual(ctx.renders.map(\.p), [3, 4, 5])
        queue.playbackAdvanced()
        try await waitIdle(queue)
        XCTAssertEqual(ctx.renders.map(\.p), [3, 4, 5], "the paragraphs above the playhead wait for the front")

        state.set(.active)
        try await waitIdle(queue)
        XCTAssertEqual(ctx.renders.map(\.p), [3, 4, 5, 0, 1, 2])
    }

    func testAListenersChunkRendersAboveTheHighWaterMark() async throws {
        let (queue, ctx, _) = makeQueue(phase: .background)
        let playing = UUID()
        ctx.playingCacheKey = playing
        ctx.readyAhead = { [high] in high + 60 }
        let text = paragraphs("Playing", 6)
        queue.openArticle(cacheKey: playing, paragraphs: text, isEphemeral: false)
        _ = try await queue.ensureChunk(cacheKey: playing, paragraphIndex: 3, chunk: 0, text: text[3], paragraphs: text,
                                        isEphemeral: false)
        try await waitIdle(queue)
        XCTAssertEqual(ctx.renders.map { "\($0.p).\($0.c)" }, ["3.0"], "the listener's chunk, then no bake-ahead")
    }

    func testInFrontTheWatermarksDontApply() async throws {
        for phase in [AppRunState.Phase.active, .inactive] {
            let (queue, ctx, _) = makeQueue(phase: phase)
            let playing = UUID()
            ctx.playingCacheKey = playing
            ctx.readyAhead = { [high] in high * 10 }
            queue.openArticle(cacheKey: playing, paragraphs: paragraphs("Playing", 4), isEphemeral: false)
            try await waitIdle(queue)
            XCTAssertEqual(ctx.renders.count, 4, "\(phase): the whole article renders")
        }
    }

    /// Coming to the front ends the burst: everything renders again, other articles included.
    func testComingToTheFrontLiftsTheWatermarks() async throws {
        let (queue, ctx, state) = makeQueue(phase: .background)
        let playing = UUID(), saved = UUID()
        ctx.playingCacheKey = playing
        ctx.readyAhead = { [high] in high + 60 }
        queue.openArticle(cacheKey: playing, paragraphs: paragraphs("Playing", 3), isEphemeral: false)
        queue.enqueueDemoted(cacheKey: saved, paragraphs: paragraphs("Saved", 2), isEphemeral: false)
        try await waitIdle(queue)
        XCTAssertTrue(ctx.renders.isEmpty)

        state.set(.active)
        try await waitIdle(queue)
        XCTAssertEqual(ctx.renders.filter { $0.key == playing }.count, 3)
        XCTAssertEqual(ctx.renders.filter { $0.key == saved }.count, 2)
    }

    /// Near a chapter's end, the next chapter's opening renders only once less than the low-water
    /// mark of the chapter playing is left.
    func testTheStagedChapterRendersOnlyBelowLowWater() async throws {
        let (queue, ctx, _) = makeQueue(phase: .background)
        let playing = UUID(), next = UUID()
        ctx.playingCacheKey = playing
        var ahead: TimeInterval = (low + high) / 2
        ctx.readyAhead = { ahead }
        queue.stageNext(cacheKey: next, after: playing, paragraphs: paragraphs("Next", 5), upTo: 3,
                        isEphemeral: false)
        try await waitIdle(queue)
        XCTAssertTrue(ctx.renders.isEmpty, "enough of the chapter playing is ready ahead")

        ahead = low - 30
        queue.playbackAdvanced()
        try await waitIdle(queue)
        XCTAssertEqual(ctx.renders.map(\.p), [0, 1, 2], "its opening, up to the staging cap")
        XCTAssertTrue(ctx.renders.allSatisfy { $0.key == next && $0.priority == .bakeAhead })
    }
}
