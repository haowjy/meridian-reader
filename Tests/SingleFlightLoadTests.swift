import XCTest
@testable import MeridianReader

/// The one load a host runs (`KokoroHost`, `KokoroCPUHost`).
final class SingleFlightLoadTests: XCTestCase {
    func testCallersShareOneLoad() async throws {
        let load = SingleFlightLoad()
        let runs = Counter()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<3 {
                group.addTask {
                    try await load.run {
                        runs.add()
                        try await Task.sleep(for: .milliseconds(50))
                    }
                }
            }
            try await group.waitForAll()
        }
        XCTAssertEqual(runs.value, 1)
        XCTAssertTrue(load.isLoaded)
    }

    /// Settings' cancel cancels the task waiting on the load; the download must stop with it.
    func testCancellingTheCallerCancelsTheLoad() async {
        let load = SingleFlightLoad()
        let started = expectation(description: "the load started")
        let stopped = expectation(description: "the load saw the cancel")
        let caller = Task {
            try await load.run {
                started.fulfill()
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    stopped.fulfill()
                    throw error
                }
            }
        }
        await fulfillment(of: [started], timeout: 5)
        caller.cancel()
        await fulfillment(of: [stopped], timeout: 5)
        XCTAssertFalse(load.isLoaded)
    }

    /// An unloading host closes its load: the load in flight ends before `close` returns (so it
    /// can't set its models afterwards), and nothing loads again.
    func testCloseEndsTheLoadInFlightAndRefusesAnother() async throws {
        let load = SingleFlightLoad()
        let started = expectation(description: "the load started")
        let ended = Counter()
        let caller = Task {
            try await load.run {
                started.fulfill()
                defer { ended.add() }
                try await Task.sleep(for: .seconds(30))
            }
        }
        await fulfillment(of: [started], timeout: 5)
        await load.close()
        XCTAssertEqual(ended.value, 1, "the load had ended when close returned")
        _ = await caller.result
        do {
            try await load.run { XCTFail("a closed load runs nothing") }
            XCTFail("a closed load throws")
        } catch is CancellationError {}
        XCTAssertFalse(load.isLoaded)
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func add() { lock.withLock { count += 1 } }
}
