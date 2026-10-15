import XCTest
@testable import MeridianReader

/// Kokoro's ONNX route uses the configured thread count while the app is in front (by default
/// every core but one, 3 to 6) and one thread in the background. ORT fixes the count when a
/// session is built, so the call after a phase change rebuilds the session
/// (`KokoroONNXSessionSlot`), releasing the old one first. A memory warning lets go of the
/// session; the next call builds it again.
final class KokoroBackgroundThreadsTests: XCTestCase {
    func testOneThreadInTheBackgroundTheConfiguredCountInFront() {
        XCTAssertEqual(KokoroRouteSettings.onnxThreads(configured: 3, phase: .active), 3)
        XCTAssertEqual(KokoroRouteSettings.onnxThreads(configured: 3, phase: .inactive), 3)
        XCTAssertEqual(KokoroRouteSettings.onnxThreads(configured: 3, phase: .background), 1)
        XCTAssertEqual(KokoroRouteSettings.onnxThreads(configured: 5, phase: .active), 5)
        XCTAssertEqual(KokoroRouteSettings.onnxThreads(configured: 6, phase: .background), 1)
        XCTAssertEqual(KokoroRouteSettings.backgroundThreads, 1)
    }

    func testInFrontEveryCoreButOneFromThreeToSix() {
        XCTAssertEqual(KokoroRouteSettings.foregroundThreads(cores: 6), 5, "an iPhone's 2 + 4 cores")
        XCTAssertEqual(KokoroRouteSettings.foregroundThreads(cores: 4), 3)
        XCTAssertEqual(KokoroRouteSettings.foregroundThreads(cores: 2), 3, "never fewer than 3")
        XCTAssertEqual(KokoroRouteSettings.foregroundThreads(cores: 8), 6)
        XCTAssertEqual(KokoroRouteSettings.foregroundThreads(cores: 16), 6, "never more than 6")
        XCTAssertEqual(KokoroRouteSettings.defaultThreads,
                       KokoroRouteSettings.foregroundThreads(cores: ProcessInfo.processInfo.activeProcessorCount))
        XCTAssertTrue(KokoroRouteSettings.threadRange.contains(KokoroRouteSettings.defaultThreads))
    }

    /// The debug override sets the count in front only; the background keeps one thread.
    func testTheOverrideAppliesInFrontOnly() {
        let suite = "KokoroThreads-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = KokoroRouteSettings(defaults: defaults)
        XCTAssertEqual(settings.cpuThreads, KokoroRouteSettings.defaultThreads, "unset: the default")
        settings.cpuThreads = 2
        XCTAssertEqual(KokoroRouteSettings.onnxThreads(configured: settings.cpuThreads, phase: .active), 2)
        XCTAssertEqual(KokoroRouteSettings.onnxThreads(configured: settings.cpuThreads, phase: .background), 1)
        settings.cpuThreads = 0
        XCTAssertEqual(settings.cpuThreads, KokoroRouteSettings.defaultThreads, "0 clears the override")
    }

    /// A stand-in session that counts how many are alive.
    private final class FakeSession {
        static let lock = NSLock()
        nonisolated(unsafe) static var alive = 0
        let threads: Int
        init(threads: Int) {
            self.threads = threads
            Self.lock.withLock { Self.alive += 1 }
        }
        deinit { Self.lock.withLock { Self.alive -= 1 } }
    }

    /// What `make` saw: (threads, sessions alive when it was called).
    private final class Builds: @unchecked Sendable {
        private let lock = NSLock()
        private var _list: [(threads: Int, aliveBefore: Int)] = []
        var list: [(threads: Int, aliveBefore: Int)] { lock.withLock { _list } }
        func add(_ threads: Int) { lock.withLock { _list.append((threads, FakeSession.lock.withLock { FakeSession.alive })) } }
    }

    /// One call as the host makes it: the session for the phase now. Returns its threads and the
    /// count it was rebuilt from, keeping no reference to the session.
    private func call(_ slot: KokoroONNXSessionSlot<FakeSession>, _ state: AppRunState,
                      configured: Int = 3) async throws -> (Int, Int?) {
        let wanted = KokoroRouteSettings.onnxThreads(configured: configured, phase: state.phase)
        let picked = try await slot.session(threads: wanted)
        return (picked.session.threads, picked.rebuiltFrom)
    }

    func testAPhaseChangeRebuildsTheSessionAtTheNextCallOnly() async throws {
        let builds = Builds()
        let slot = KokoroONNXSessionSlot<FakeSession> { threads in
            builds.add(threads)
            return FakeSession(threads: threads)
        }
        let state = AppRunState(phase: .active)
        try await slot.load(threads: KokoroRouteSettings.onnxThreads(configured: 3, phase: state.phase))
        let (t0, r0) = try await call(slot, state)
        XCTAssertEqual(t0, 3)
        XCTAssertNil(r0)

        state.set(.background)
        XCTAssertEqual(slot.threads, 3, "nothing rebuilds until the next call")
        let (t1, r1) = try await call(slot, state)
        XCTAssertEqual(t1, 1)
        XCTAssertEqual(r1, 3)
        let (t2, r2) = try await call(slot, state)
        XCTAssertEqual(t2, 1)
        XCTAssertNil(r2, "same phase: the session is kept")

        state.set(.inactive) // unlocking: the app is on its way to the front
        let (t3, r3) = try await call(slot, state)
        XCTAssertEqual(t3, 3)
        XCTAssertEqual(r3, 1)

        XCTAssertEqual(builds.list.map(\.threads), [3, 1, 3])
        XCTAssertEqual(builds.list.map(\.aliveBefore), [0, 0, 0], "the old session is released before a new one is built")
        slot.drop()
        XCTAssertNil(slot.threads)
    }

    func testAFailedRebuildLeavesTheSlotEmpty() async throws {
        struct BuildFailed: Error {}
        let fail = Builds()
        let slot = KokoroONNXSessionSlot<FakeSession> { threads in
            fail.add(threads)
            if threads == 1 { throw BuildFailed() }
            return FakeSession(threads: threads)
        }
        try await slot.load(threads: 3)
        do {
            _ = try await slot.session(threads: 1)
            XCTFail("expected the rebuild to fail")
        } catch is BuildFailed {}
        XCTAssertNil(slot.threads)
        do {
            _ = try await slot.session(threads: 3)
            XCTFail("expected not loaded")
        } catch LocalSynthError.engineUnavailable {}

        // The host is then unprepared: its next render loads it again, at the phase's count.
        try await slot.load(threads: 3)
        let reloaded = try await slot.session(threads: 3)
        XCTAssertEqual(reloaded.session.threads, 3)
    }

    /// Back and forth at the default count: each call gets the phase's count, a change rebuilds once
    /// (however many phase changes came between two calls), and two sessions are never alive.
    func testSwitchingBackAndForthAtTheForegroundDefault() async throws {
        let front = KokoroRouteSettings.foregroundThreads(cores: 6)
        let builds = Builds()
        let slot = KokoroONNXSessionSlot<FakeSession> { threads in
            builds.add(threads)
            return FakeSession(threads: threads)
        }
        let state = AppRunState(phase: .active)
        try await slot.load(threads: KokoroRouteSettings.onnxThreads(configured: front, phase: state.phase))
        var seen: [Int] = []
        for phase in [AppRunState.Phase.active, .background, .background, .inactive, .active, .background] {
            state.set(phase)
            seen.append(try await call(slot, state, configured: front).0)
        }
        XCTAssertEqual(seen, [5, 1, 1, 5, 5, 1])

        // Locked and unlocked again before the next chunk: the session isn't rebuilt twice.
        state.set(.active)
        state.set(.background)
        let (threads, rebuiltFrom) = try await call(slot, state, configured: front)
        XCTAssertEqual(threads, 1)
        XCTAssertNil(rebuiltFrom)

        XCTAssertEqual(builds.list.map(\.threads), [5, 1, 5, 1])
        XCTAssertEqual(builds.list.map(\.aliveBefore), [0, 0, 0, 0], "the old session is released before a new one is built")
    }

    /// A memory warning (`release`) lets go of the session but keeps the slot loaded: the next
    /// call builds it again at the phase's count, with nothing else alive. Only a count change
    /// reports `rebuiltFrom`; a drop after a release unloads.
    func testAReleasedSessionIsBuiltAgainAtTheNextCall() async throws {
        let builds = Builds()
        let slot = KokoroONNXSessionSlot<FakeSession> { threads in
            builds.add(threads)
            return FakeSession(threads: threads)
        }
        XCTAssertFalse(slot.release(), "nothing loaded: nothing to let go")
        try await slot.load(threads: 3)
        _ = try await slot.session(threads: 3)

        XCTAssertTrue(slot.release())
        XCTAssertNil(slot.threads, "the session is gone")
        XCTAssertEqual(FakeSession.lock.withLock { FakeSession.alive }, 0, "its memory with it")
        XCTAssertFalse(slot.release(), "already let go")
        // Each call as the host makes it: no reference kept past the call.
        func call(_ threads: Int) async throws -> (Int, Int?) {
            let picked = try await slot.session(threads: threads)
            return (picked.session.threads, picked.rebuiltFrom)
        }
        let (again, againFrom) = try await call(3)
        XCTAssertEqual(again, 3)
        XCTAssertNil(againFrom, "same count: not a thread switch")

        XCTAssertTrue(slot.release())
        let (locked, lockedFrom) = try await call(1) // the phone was locked meanwhile
        XCTAssertEqual(locked, 1)
        XCTAssertEqual(lockedFrom, 3)
        XCTAssertEqual(builds.list.map(\.threads), [3, 3, 1])
        XCTAssertEqual(builds.list.map(\.aliveBefore), [0, 0, 0], "never two sessions")

        XCTAssertTrue(slot.release())
        slot.drop()
        do {
            _ = try await slot.session(threads: 1)
            XCTFail("dropped: not loaded")
        } catch LocalSynthError.engineUnavailable {}
    }
}
