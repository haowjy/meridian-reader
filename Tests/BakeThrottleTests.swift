import XCTest
@testable import MeridianReader

/// Bake-ahead renders at a lower priority than chunks someone is listening to, and waits while
/// the device is hot or in Low Power Mode; listener chunks always render.
@MainActor
final class BakeThrottleTests: XCTestCase {
    private var contexts: [FakeQueueContext] = []

    override func tearDown() async throws {
        contexts.forEach { $0.cleanUp() }
        contexts = []
    }

    func testHoldReasons() {
        func hold(_ t: ProcessInfo.ThermalState, lowPower: Bool = false) -> BakeConditions.Hold? {
            BakeConditions(thermalState: t, isLowPowerModeEnabled: lowPower).bakeAheadHold
        }
        XCTAssertNil(hold(.nominal))
        XCTAssertNil(hold(.fair))
        XCTAssertEqual(hold(.serious), .thermal(.serious))
        XCTAssertEqual(hold(.critical), .thermal(.critical))
        XCTAssertEqual(hold(.nominal, lowPower: true), .lowPowerMode)
        XCTAssertEqual(hold(.serious, lowPower: true), .thermal(.serious))
    }

    private func makeQueue() -> (GlobalSynthQueue, FakeQueueContext) {
        let state = AppRunState(phase: .active)
        let ctx = FakeQueueContext(provider: FakeEngineProvider(), runState: state)
        contexts.append(ctx)
        let queue = GlobalSynthQueue()
        queue.usesBackgroundGrace = false
        queue.runState = state
        queue.attach(coordinator: ctx)
        return (queue, ctx)
    }

    private func waitIdle(_ queue: GlobalSynthQueue, timeout: TimeInterval = 20) async throws {
        let start = Date()
        try await Task.sleep(nanoseconds: 30_000_000)
        while queue.isWorkerRunning {
            if Date().timeIntervalSince(start) > timeout { XCTFail("worker never went idle"); return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private let paras = [
        "Sentence number one is here, and it runs on for a little while longer.",
        "Sentence number two is here, and it runs on for a little while longer.",
        "Sentence number three is here, and it runs on for a little while longer.",
    ]

    func testHotDeviceHoldsBakeAheadButServesTheListener() async throws {
        let (queue, ctx) = makeQueue()
        var conditions = BakeConditions(thermalState: .serious, isLowPowerModeEnabled: false)
        queue.bakeConditions = { conditions }
        let key = UUID()

        queue.openArticle(cacheKey: key, paragraphs: paras, voiceID: "v", isEphemeral: false)
        try await waitIdle(queue)
        XCTAssertTrue(ctx.renders.isEmpty, "saved-article bake waits while the device is hot")

        _ = try await queue.ensureChunk(cacheKey: key, paragraphIndex: 1, chunk: 0, text: paras[1],
                                        paragraphs: paras, voiceID: "v", isEphemeral: false)
        try await waitIdle(queue)
        XCTAssertEqual(ctx.renders.map { "\($0.p).\($0.c)" }, ["1.0"], "only the chunk a listener waits for")
        XCTAssertEqual(ctx.renders.map(\.priority), [.listener])

        conditions.thermalState = .nominal
        queue.bakeConditionsChanged()
        try await waitIdle(queue)
        let all = paras.flatMap(queue.chunkTexts(for:))
        XCTAssertEqual(ctx.renders.count, all.count, "bake-ahead resumes once the device cools")
        XCTAssertTrue(ctx.renders.dropFirst().allSatisfy { $0.priority == .bakeAhead })
    }

    func testPlayingArticleRendersAtListenerPriority() async throws {
        let (queue, ctx) = makeQueue()
        let playing = UUID()
        ctx.playingCacheKey = playing
        queue.openArticle(cacheKey: playing, paragraphs: paras, voiceID: "v", isEphemeral: false)
        try await waitIdle(queue)
        XCTAssertFalse(ctx.renders.isEmpty)
        XCTAssertTrue(ctx.renders.allSatisfy { $0.priority == .listener })
    }
}
