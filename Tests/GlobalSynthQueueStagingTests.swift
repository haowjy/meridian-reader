import XCTest
@testable import MeridianReader

/// The next chapter of a book or series renders its opening ahead of its turn
/// (`GlobalSynthQueue.stageNext`): right behind the playing chapter (at the front once its job is
/// done), ahead of demoted work, in the background on a route that may render there, at
/// bake-ahead priority, capped until it plays.
@MainActor
final class GlobalSynthQueueStagingTests: XCTestCase {
    private var cleanups: [() -> Void] = []

    override func tearDown() async throws {
        cleanups.reversed().forEach { $0() }
        cleanups = []
    }

    private func makeQueue(_ provider: FakeEngineProvider? = nil,
                           phase: AppRunState.Phase = .active) -> (GlobalSynthQueue, FakeQueueContext, AppRunState) {
        let state = AppRunState(phase: phase)
        let ctx = FakeQueueContext(provider: provider ?? FakeEngineProvider(), runState: state)
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

    private func stage(_ queue: GlobalSynthQueue, _ key: UUID, after playing: UUID?, _ text: [String], cap: Int = 3) {
        queue.stageNext(cacheKey: key, after: playing, paragraphs: text, voiceID: "v", upTo: cap, isEphemeral: false)
    }

    private func paragraphs(_ name: String, _ count: Int) -> [String] {
        (1...count).map { "\(name) paragraph \($0) is short." }
    }

    private func rendered(_ ctx: FakeQueueContext, _ key: UUID, _ count: Int) -> [Int] {
        (0..<count).filter {
            ctx.audioCache.audioURL(articleID: key, paragraphIndex: $0, engineID: ctx.cacheEngineID, voiceID: "v") != nil
        }
    }

    /// Locked, on the ONNX route, with a save job queued before the next chapter was known: the
    /// next chapter's opening still renders (it is staged ahead of the demoted job and counts as
    /// playing), while the demoted job waits for the foreground. Appended behind it instead, it
    /// would wait too.
    func testInTheBackgroundTheStagedChapterRendersAheadOfADemotedJob() async throws {
        let (queue, ctx, _) = makeQueue(FakeEngineProvider(config: .init(rendersInBackground: true)), phase: .background)
        let playing = UUID(), saved = UUID(), next = UUID()
        ctx.playingCacheKey = playing
        queue.openArticle(cacheKey: playing, paragraphs: paragraphs("Playing", 2), voiceID: "v", isEphemeral: false)
        queue.enqueueDemoted(cacheKey: saved, paragraphs: paragraphs("Saved", 2), voiceID: "v", isEphemeral: false)
        stage(queue, next, after: playing, paragraphs("Next", 2))
        XCTAssertEqual(queue.playingCacheKeys, [playing, next])
        try await waitIdle(queue)

        XCTAssertEqual(rendered(ctx, next, 2), [0, 1], "the staged chapter renders in the background")
        XCTAssertFalse(ctx.renders.contains { $0.key == saved }, "the demoted job waits for the foreground")

        // Without staging: the same chapter behind the demoted job parks with it.
        let (plain, plainCtx, _) = makeQueue(FakeEngineProvider(config: .init(rendersInBackground: true)), phase: .background)
        plainCtx.playingCacheKey = playing
        plain.openArticle(cacheKey: playing, paragraphs: paragraphs("Playing", 2), voiceID: "v", isEphemeral: false)
        plain.enqueueDemoted(cacheKey: saved, paragraphs: paragraphs("Saved", 2), voiceID: "v", isEphemeral: false)
        plain.enqueueDemoted(cacheKey: next, paragraphs: paragraphs("Next", 2), voiceID: "v", isEphemeral: false)
        try await waitIdle(plain)
        XCTAssertTrue(rendered(plainCtx, next, 2).isEmpty, "queued behind a parked job, it never renders")
    }

    /// Staging comes from playback, not from the queue: the chapter playing may have been
    /// rendered in full, its job gone, by the time its successor is staged, leaving a save job at
    /// the front that waits for the foreground. Locked on the ONNX route, the staged chapter goes
    /// ahead of it and renders; behind it, it would wait too.
    func testWhenThePlayingChaptersJobIsDoneTheStagedChapterGoesAheadOfAJobThatWaits() async throws {
        let (queue, ctx, _) = makeQueue(FakeEngineProvider(config: .init(rendersInBackground: true)), phase: .background)
        let playing = UUID(), saved = UUID(), next = UUID()
        ctx.playingCacheKey = playing
        queue.openArticle(cacheKey: playing, paragraphs: paragraphs("Playing", 2), voiceID: "v", isEphemeral: false)
        queue.enqueueDemoted(cacheKey: saved, paragraphs: paragraphs("Saved", 2), voiceID: "v", isEphemeral: false)
        try await waitIdle(queue)
        XCTAssertEqual(rendered(ctx, playing, 2), [0, 1])
        XCTAssertFalse(queue.hasJob(cacheKey: playing), "the playing chapter's job is done")
        XCTAssertEqual(queue.primaryCacheKey, saved, "the save job is at the front, waiting for the foreground")

        stage(queue, next, after: playing, paragraphs("Next", 2))
        XCTAssertEqual(queue.primaryCacheKey, next, "staged ahead of it")
        try await waitIdle(queue)
        XCTAssertEqual(rendered(ctx, next, 2), [0, 1], "the staged chapter renders in the background")
        XCTAssertFalse(ctx.renders.contains { $0.key == saved }, "the save job still waits")
    }

    /// Another page opened while a chapter plays becomes #1; the chapter's next live request puts
    /// it back in front, and the staged chapter goes with it rather than stay behind the other page.
    func testThePlayingChapterBackAtTheFrontTakesTheStagedChapterAlong() async throws {
        let (queue, ctx, _) = makeQueue(FakeEngineProvider(config: .init(rendersInBackground: true)), phase: .background)
        let playing = UUID(), opened = UUID(), next = UUID()
        ctx.playingCacheKey = playing
        queue.isHeldForLaunch = true // only the queue's shape until released
        queue.openArticle(cacheKey: playing, paragraphs: paragraphs("Playing", 2), voiceID: "v", isEphemeral: false)
        stage(queue, next, after: playing, paragraphs("Next", 2))
        queue.openArticle(cacheKey: opened, paragraphs: paragraphs("Opened", 2), voiceID: "v", isEphemeral: false)
        queue.focusPlayhead(cacheKey: playing, paragraph: 1)
        XCTAssertEqual(queue.primaryCacheKey, playing)

        queue.isHeldForLaunch = false
        try await waitIdle(queue)
        XCTAssertEqual(rendered(ctx, next, 2), [0, 1], "the staged chapter renders behind the playing one")
        XCTAssertFalse(ctx.renders.contains { $0.key == opened }, "the other page waits for the foreground")
    }

    func testTheStagedJobNeverRendersAtListenerPriority() async throws {
        let (queue, ctx, _) = makeQueue()
        let playing = UUID(), next = UUID()
        ctx.playingCacheKey = playing
        queue.openArticle(cacheKey: playing, paragraphs: paragraphs("Playing", 1), voiceID: "v", isEphemeral: false)
        stage(queue, next, after: playing, paragraphs("Next", 2))
        try await waitIdle(queue)
        let staged = ctx.renders.filter { $0.key == next }
        XCTAssertFalse(staged.isEmpty)
        XCTAssertTrue(staged.allSatisfy { $0.priority == .bakeAhead }, "\(staged.map(\.priority))")
        XCTAssertTrue(ctx.renders.filter { $0.key == playing }.allSatisfy { $0.priority == .listener })
    }

    func testOnlyTheFirstParagraphsRenderUntilTheChapterPlays() async throws {
        let (queue, ctx, _) = makeQueue()
        let next = UUID()
        let text = paragraphs("Next", 5)
        stage(queue, next, after: nil, text)
        try await waitIdle(queue)
        XCTAssertEqual(rendered(ctx, next, 5), [0, 1, 2], "capped at 3 paragraphs")
        XCTAssertTrue(queue.hasJob(cacheKey: next), "still queued")

        // It plays: it becomes #1 and the cap lifts.
        queue.openArticle(cacheKey: next, paragraphs: text, voiceID: "v", isEphemeral: false)
        try await waitIdle(queue)
        XCTAssertEqual(rendered(ctx, next, 5), [0, 1, 2, 3, 4])
        XCTAssertNil(queue.stagedCacheKey)
    }

    /// The chapter playing finished rendering, so the staged one reaches the front early: at its
    /// cap it steps aside and the save job behind it renders.
    func testACappedStagedJobAtTheFrontLetsTheJobBehindItRun() async throws {
        let (queue, ctx, _) = makeQueue()
        let playing = UUID(), saved = UUID(), next = UUID()
        queue.openArticle(cacheKey: playing, paragraphs: paragraphs("Playing", 1), voiceID: "v", isEphemeral: false)
        queue.enqueueDemoted(cacheKey: saved, paragraphs: paragraphs("Saved", 2), voiceID: "v", isEphemeral: false)
        stage(queue, next, after: playing, paragraphs("Next", 4), cap: 1)
        try await waitIdle(queue)
        XCTAssertEqual(rendered(ctx, next, 4), [0], "the staged chapter's opening")
        XCTAssertEqual(rendered(ctx, saved, 2), [0, 1], "the save job behind it ran")
        XCTAssertEqual(queue.primaryCacheKey, next, "the staged chapter waits at the front for its turn")
        XCTAssertEqual(queue.stagedCacheKey, next)
    }

    func testOnCoreMLTheStagedChapterParksInTheBackground() async throws {
        let (queue, ctx, state) = makeQueue(phase: .background)
        let next = UUID()
        stage(queue, next, after: nil, paragraphs("Next", 2))
        try await waitIdle(queue)
        XCTAssertTrue(ctx.host.calls.isEmpty, "no model call in the background on Core ML")

        state.set(.active)
        try await waitIdle(queue)
        XCTAssertEqual(rendered(ctx, next, 2), [0, 1], "it renders once the app is in front")
    }

    /// A later stage replaces the staged job; another page playing unstages it. A job staging
    /// made leaves the queue; one that was queued before stays.
    func testALaterStageReplacesItAndUnstagingRemovesOnlyWhatStagingAdded() {
        let (queue, _, _) = makeQueue(phase: .background) // nothing renders: only the queue's shape
        let playing = UUID(), first = UUID(), second = UUID(), queued = UUID()
        queue.openArticle(cacheKey: playing, paragraphs: paragraphs("Playing", 1), voiceID: "v", isEphemeral: false)
        stage(queue, first, after: playing, paragraphs("First", 1))
        stage(queue, second, after: playing, paragraphs("Second", 1))
        XCTAssertFalse(queue.hasJob(cacheKey: first), "replaced")
        XCTAssertEqual(queue.stagedCacheKey, second)
        queue.unstage()
        XCTAssertFalse(queue.hasJob(cacheKey: second), "unstaged")
        XCTAssertNil(queue.stagedCacheKey)

        queue.enqueueDemoted(cacheKey: queued, paragraphs: paragraphs("Queued", 1), voiceID: "v", isEphemeral: false)
        stage(queue, queued, after: playing, paragraphs("Queued", 1))
        queue.unstage()
        XCTAssertTrue(queue.hasJob(cacheKey: queued), "a job queued before staging stays")
        XCTAssertEqual(queue.primaryCacheKey, playing)
    }
}
