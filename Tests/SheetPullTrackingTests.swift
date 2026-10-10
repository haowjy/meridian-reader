import XCTest
@testable import MeridianReader

/// A sheet's scrolling body hands a pull at its top to the sheet (`SheetPullTracking`): only a
/// drag that began at the top can pull, the pull follows the finger, and moving back up lowers the
/// pull before the content scrolls again.
final class SheetPullTrackingTests: XCTestCase {
    private let down = CGSize(width: 1, height: 12)
    private let up = CGSize(width: 1, height: -12)

    func testADragThatBeginsAtTheTopGoingDownPullsTheSheet() {
        var t = SheetPullTracking(scrolledIn: -4, translation: down, isInSheet: true)
        XCTAssertTrue(t.canPull)
        XCTAssertTrue(t.move(by: 12, scrolledIn: -4), "the content is held at its top")
        XCTAssertEqual(t.pull, 12)
        XCTAssertTrue(t.move(by: 100, scrolledIn: -2))
        XCTAssertEqual(t.pull, 112, "follows the finger 1:1")
        XCTAssertFalse(t.scrolled, "the text never moved")
    }

    func testADragThatBeginsMidContentNeverPulls() {
        var t = SheetPullTracking(scrolledIn: 300, translation: down, isInSheet: true)
        XCTAssertFalse(t.canPull)
        XCTAssertFalse(t.move(by: 200, scrolledIn: 100))
        XCTAssertFalse(t.move(by: 200, scrolledIn: -40), "reaching the top only bounces")
        XCTAssertEqual(t.pull, 0)
        XCTAssertTrue(t.scrolled)
    }

    func testADragThatBeganAtTheTopGoingUpCanComeBackDownAndPull() {
        // The scroll view already moved the content up by the first movement.
        var t = SheetPullTracking(scrolledIn: 12, translation: up, isInSheet: true)
        XCTAssertTrue(t.canPull)
        XCTAssertFalse(t.move(by: -12, scrolledIn: 12))
        XCTAssertTrue(t.scrolled)
        XCTAssertFalse(t.move(by: 12, scrolledIn: 0), "back at the top: nothing pulled yet")
        XCTAssertTrue(t.move(by: 30, scrolledIn: -10))
        XCTAssertEqual(t.pull, 30)
    }

    func testMovingBackUpLowersThePullBeforeTheContentScrolls() {
        var t = SheetPullTracking(scrolledIn: 0, translation: down, isInSheet: true)
        _ = t.move(by: 80, scrolledIn: -5)
        XCTAssertTrue(t.move(by: -50, scrolledIn: 6), "still pulled: the content is held")
        XCTAssertEqual(t.pull, 30)
        XCTAssertFalse(t.scrolled)
        XCTAssertFalse(t.move(by: -50, scrolledIn: 20), "back at rest: the content scrolls")
        XCTAssertEqual(t.pull, 0)
        XCTAssertTrue(t.scrolled)
    }

    func testOutsideASheetOrSidewaysNothingPulls() {
        XCTAssertFalse(SheetPullTracking(scrolledIn: 0, translation: down, isInSheet: false).canPull)
        XCTAssertFalse(SheetPullTracking(scrolledIn: 0, translation: CGSize(width: 20, height: 8),
                                         isInSheet: true).canPull)
    }

    /// A release commits like a pull on the header: far enough, or flung.
    func testReleaseCommitsOnDistanceOrSpeed() {
        func commits(_ offset: CGFloat, _ velocity: CGFloat) -> Bool {
            SwipeGesturePolicy.shouldCommitDownwardDismiss(
                translation: offset, predicted: SwipeGesturePolicy.projectedTranslation(offset, velocity: velocity))
        }
        XCTAssertTrue(commits(80, 0), "far enough")
        XCTAssertFalse(commits(40, 100), "short and slow springs back")
        XCTAssertTrue(commits(20, 800), "a flick")
        XCTAssertFalse(commits(60, -400), "moving back up")
        XCTAssertFalse(commits(40, .nan), "an unmeasured speed")
    }
}
