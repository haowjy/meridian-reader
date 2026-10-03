import XCTest
@testable import Reader

/// A committed pull-down carries on at the release speed, and the reader overlay looks like a
/// sheet while it is pulled: slightly smaller, with the dim behind it lifting.
final class PullDownDismissTests: XCTestCase {
    func testReleaseVelocityIsAFractionOfTheRemainingDistance() {
        XCTAssertEqual(Motion.releaseVelocity(1600, over: 800), 2)
        XCTAssertEqual(Motion.releaseVelocity(-500, over: 800), 0, "moving back up seeds nothing")
        XCTAssertEqual(Motion.releaseVelocity(1600, over: 0), 0, "nothing left to cover")
    }

    func testAtRestTheReaderIsFullSizeOverTheDim() {
        let look = PullDownLook(offset: 0, screenHeight: 800)
        XCTAssertEqual(look.scale, 1)
        XCTAssertEqual(look.dim, PullDownLook.maxDim)
        XCTAssertEqual(PullDownLook(offset: -30, screenHeight: 800), look, "a rubber-banded pull up changes nothing")
    }

    func testPullingShrinksTheReaderAndLiftsTheDim() {
        let little = PullDownLook(offset: 100, screenHeight: 900)
        XCTAssertLessThan(little.scale, 1)
        XCTAssertGreaterThan(little.scale, PullDownLook.minScale)
        XCTAssertLessThan(little.dim, PullDownLook.maxDim)

        let gone = PullDownLook(offset: 900, screenHeight: 900)
        XCTAssertEqual(gone.scale, PullDownLook.minScale, accuracy: 0.0001)
        XCTAssertEqual(gone.dim, 0)
        XCTAssertEqual(PullDownLook(offset: 1200, screenHeight: 900), gone, "clamped past the bottom")
    }
}
