import XCTest
import SwiftUI
@testable import Reader

/// Swipe-to-dismiss rules shared by the ⋯ menu panel and the reader overlay's pull-down: axis
/// fixed by the first movement, rubber-banded upward drags, and the release threshold.
final class SwipeGesturePolicyTests: XCTestCase {
    func testFirstMovementDecidesTheAxis() {
        XCTAssertEqual(SwipeGesturePolicy.axis(ofFirstMovement: CGSize(width: 4, height: 14)), .vertical)
        XCTAssertEqual(SwipeGesturePolicy.axis(ofFirstMovement: CGSize(width: 3, height: -14)), .vertical)
        XCTAssertEqual(SwipeGesturePolicy.axis(ofFirstMovement: CGSize(width: -14, height: 6)), .horizontal)
    }

    func testDismissOffsetFollowsDownAndResistsUp() {
        XCTAssertEqual(SwipeGesturePolicy.dismissOffset(forVerticalTranslation: 0), 0)
        XCTAssertEqual(SwipeGesturePolicy.dismissOffset(forVerticalTranslation: 120), 120)
        let up = SwipeGesturePolicy.dismissOffset(forVerticalTranslation: -100)
        XCTAssertLessThan(up, 0, "moves up a little")
        XCTAssertGreaterThan(up, -40, "far less than the finger")
        XCTAssertLessThan(SwipeGesturePolicy.dismissOffset(forVerticalTranslation: -200), up, "keeps moving, never jumps back")
    }

    func testDownwardDismissCommitsOnDistanceOrFling() {
        XCTAssertTrue(SwipeGesturePolicy.shouldCommitDownwardDismiss(translation: 80, predicted: 90))
        XCTAssertTrue(SwipeGesturePolicy.shouldCommitDownwardDismiss(translation: 30, predicted: 200))
        XCTAssertFalse(SwipeGesturePolicy.shouldCommitDownwardDismiss(translation: 30, predicted: 60))
        XCTAssertFalse(SwipeGesturePolicy.shouldCommitDownwardDismiss(translation: -80, predicted: -200))
    }
}
