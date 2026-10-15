import XCTest
@testable import MeridianReader

/// The on-device engine's 5 Hz clock (position and listen-bar status) runs only while audio is
/// wanted and the app is in front. Locking the phone (the background) stops it, so a locked
/// listen doesn't wake the app 5×/s; back in front it starts again. Pause, stop and the end stop
/// it whatever the phase.
@MainActor
final class LocalListenEngineClockTests: XCTestCase {
    private let suite = "LocalListenEngineClock-\(UUID().uuidString)"
    private let root = FileManager.default.temporaryDirectory.appending(path: "LocalListenEngineClock-\(UUID().uuidString)")
    private var engine: LocalListenEngine!
    private let runState = AppRunState(phase: .active)

    override func setUp() {
        let registry = EngineRegistry(providers: [AppleSpeechProvider()], gate: { _ in true })
        let coordinator = LocalTTSCoordinator(engines: registry, defaults: UserDefaults(suiteName: suite)!,
                                              audioCache: ArticleAudioCache(root: root.appending(path: "cache")),
                                              crashGuard: EngineCrashGuard(directory: root.appending(path: "guard")))
        coordinator.synthQueue.runState = runState
        engine = LocalListenEngine(coordinator: coordinator)
    }

    override func tearDown() {
        engine.stop()
        engine = nil
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }

    private func play(paused: Bool = false) {
        engine.play(ListenPlayRequest(articleID: UUID(), document: ParagraphDocument(parts: ["One.", "Two."]),
                                      utf16Offset: 0, startPaused: paused, appleVoice: nil))
    }

    /// Phase changes reach the engine through `AppRunState.didChange` on the main queue.
    private func set(_ phase: AppRunState.Phase) async {
        runState.set(phase)
        for _ in 0..<20 { await Task.yield() }
    }

    func testTheClockStopsInTheBackgroundAndStartsAgainInFront() async {
        play()
        XCTAssertTrue(engine.isClockRunning, "playing in front")

        await set(.inactive)
        XCTAssertTrue(engine.isClockRunning, "Control Center over the app: still on screen")
        await set(.background)
        XCTAssertFalse(engine.isClockRunning, "locked: nothing on screen to update")
        await set(.inactive)
        XCTAssertTrue(engine.isClockRunning, "unlocking")
        await set(.active)
        XCTAssertTrue(engine.isClockRunning)
    }

    func testPauseAndStopKeepTheClockOffInEveryPhase() async {
        play()
        engine.pause()
        XCTAssertFalse(engine.isClockRunning, "paused")
        await set(.background)
        await set(.active)
        XCTAssertFalse(engine.isClockRunning, "back in front, still paused")

        play()
        XCTAssertTrue(engine.isClockRunning)
        await set(.background)
        engine.stop()
        await set(.active)
        XCTAssertFalse(engine.isClockRunning, "stopped in the background: nothing to sample")
    }

    /// A play that starts with the phone locked (the lock screen's ▶) doesn't start the clock.
    func testAPlayStartedInTheBackgroundWaitsForTheForeground() async {
        await set(.background)
        play()
        XCTAssertFalse(engine.isClockRunning)
        await set(.active)
        XCTAssertTrue(engine.isClockRunning)
    }

    func testAPausedPlayHasNoClock() {
        play(paused: true)
        XCTAssertFalse(engine.isClockRunning)
    }
}
