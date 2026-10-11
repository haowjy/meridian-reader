import XCTest
@testable import MeridianReader

/// Kokoro's ONNX route uses the configured thread count while the app is in front and one thread
/// in the background. ORT fixes the count when a session is built, so the call after a phase
/// change rebuilds the session (`KokoroONNXSessionSlot`), releasing the old one first.
final class KokoroBackgroundThreadsTests: XCTestCase {
    func testOneThreadInTheBackgroundTheConfiguredCountInFront() {
        XCTAssertEqual(KokoroRouteSettings.onnxThreads(configured: 3, phase: .active), 3)
        XCTAssertEqual(KokoroRouteSettings.onnxThreads(configured: 3, phase: .inactive), 3)
        XCTAssertEqual(KokoroRouteSettings.onnxThreads(configured: 3, phase: .background), 1)
        XCTAssertEqual(KokoroRouteSettings.onnxThreads(configured: 4, phase: .active), 4)
        XCTAssertEqual(KokoroRouteSettings.backgroundThreads, 1)
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
    private func call(_ slot: KokoroONNXSessionSlot<FakeSession>, _ state: AppRunState) async throws -> (Int, Int?) {
        let wanted = KokoroRouteSettings.onnxThreads(configured: 3, phase: state.phase)
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
    }
}
