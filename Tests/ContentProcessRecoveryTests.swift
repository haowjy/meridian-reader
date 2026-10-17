import XCTest
@testable import MeridianReader

/// The reloads after a web view's content process ends: at once, then slower, then none until a
/// quiet minute has passed.
final class ContentProcessRecoveryTests: XCTestCase {
    func testReloadsBackOffThenStopThenComeBack() {
        var recovery = ContentProcessRecovery()
        let start = Date(timeIntervalSinceReferenceDate: 0)
        XCTAssertEqual(recovery.delayAfterEnd(at: start), 0)
        XCTAssertEqual(recovery.delayAfterEnd(at: start + 1), 2)
        XCTAssertEqual(recovery.delayAfterEnd(at: start + 4), 5)
        XCTAssertNil(recovery.delayAfterEnd(at: start + 10), "a page that keeps ending its process is left")
        XCTAssertNil(recovery.delayAfterEnd(at: start + 59))
        XCTAssertEqual(recovery.delayAfterEnd(at: start + 61), 2, "ends a minute old no longer count")
        XCTAssertEqual(recovery.delayAfterEnd(at: start + 200), 0, "a page that stayed up starts over")
    }
}
