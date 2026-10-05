import XCTest
@testable import Reader

/// A committed pull-down carries on at the release speed, and the reader overlay looks like a
/// sheet while it is pulled: slightly smaller, with the dim behind it lifting.
final class PullDownDismissTests: XCTestCase {
    func testReleaseVelocityIsAFractionOfTheRemainingDistance() {
        XCTAssertEqual(Motion.releaseVelocity(1600, over: 800), 2)
        XCTAssertEqual(Motion.releaseVelocity(-500, over: 800), 0, "moving back up seeds nothing")
        XCTAssertEqual(Motion.releaseVelocity(1600, over: 0), 0, "nothing left to cover")
        XCTAssertEqual(Motion.releaseVelocity(100_000, over: 400), Motion.maxReleaseVelocity, "a flick is capped")
        XCTAssertEqual(Motion.releaseVelocity(.infinity, over: 400), Motion.maxReleaseVelocity, "never infinite")
        XCTAssertEqual(Motion.releaseVelocity(.nan, over: 400), 0, "unmeasured speed seeds nothing")
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

    /// The player's status bar stays light until it has gone, so the strip under it stays as dark
    /// as at rest however far the sheet is pulled: the dim and the scrim over it let through
    /// 1 - maxDim of the surface at every pull. At rest there is no scrim.
    func testThePlayersStatusBarStripStaysAsDarkAsAtRestThroughThePull() {
        let maxDim = SheetLook.player.maxDim
        XCTAssertEqual(PullDownLook(offset: 0, screenHeight: 874, maxDim: maxDim).statusBarScrim, 0, "none at rest")
        for offset in stride(from: 0, through: 874, by: 23) {
            let look = PullDownLook(offset: CGFloat(offset), screenHeight: 874, maxDim: maxDim)
            let through = (1 - look.dim) * (1 - look.statusBarScrim)
            XCTAssertEqual(through, 1 - maxDim, accuracy: 0.0001, "pulled \(offset) pt")
        }
        XCTAssertEqual(PullDownLook(offset: 874, screenHeight: 874, maxDim: maxDim).statusBarScrim, maxDim,
                       accuracy: 0.0001, "the dim gone: the scrim alone")
    }
}
