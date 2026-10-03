import XCTest
import SwiftUI
@testable import Reader

/// The ⋯ morph grows the glass's frame and corner radius (never a stretch): from the button's
/// circle to the panel, with the point it grows out of kept in place.
final class MorphMenuGeometryTests: XCTestCase {
    private let button = CGSize(width: 44, height: 44)
    private let panel = CGSize(width: 300, height: 420)

    func testFocusSitsUpAndLeftOfTheButton() {
        // 12 pt left, 10 pt up: Safari's inset, deliberately not dead-on the ⋯.
        XCTAssertEqual(MorphMenu.focusOffsetFromAnchor.width, 12)
        XCTAssertEqual(MorphMenu.focusOffsetFromAnchor.height, 10)
    }

    func testStartsAsTheButtonAndEndsAsThePanel() {
        let anchor = UnitPoint.bottomTrailing
        let start = MorphMenu.morphFrame(progress: 0, button: button, panel: panel, anchor: anchor)
        XCTAssertEqual(start, CGRect(x: 256, y: 376, width: 44, height: 44), "button-sized, in the bottom-right corner")
        XCTAssertEqual(MorphMenu.morphFrame(progress: 1, button: button, panel: panel, anchor: anchor),
                       CGRect(origin: .zero, size: panel))
        XCTAssertEqual(MorphMenu.morphCornerRadius(progress: 0, button: button), 22, "a circle")
        XCTAssertEqual(MorphMenu.morphCornerRadius(progress: 1, button: button), MorphMenu.cornerRadius)
    }

    func testTheAnchorStaysPutWhileItGrows() {
        let anchor = UnitPoint(x: 0.8, y: 0.9)
        for p in [0, 0.3, 0.7, 1] as [CGFloat] {
            let f = MorphMenu.morphFrame(progress: p, button: button, panel: panel, anchor: anchor)
            XCTAssertEqual(f.minX + f.width * anchor.x, panel.width * anchor.x, accuracy: 1e-6)
            XCTAssertEqual(f.minY + f.height * anchor.y, panel.height * anchor.y, accuracy: 1e-6)
        }
    }

    func testWithoutAButtonTheGlassIsThePanelThroughout() {
        XCTAssertEqual(MorphMenu.morphFrame(progress: 0.2, button: nil, panel: panel, anchor: .center),
                       CGRect(origin: .zero, size: panel))
        XCTAssertEqual(MorphMenu.morphCornerRadius(progress: 0.2, button: nil), MorphMenu.cornerRadius)
    }

    func testRoundingNudgesOfTheFocusPointAreIgnored() {
        let focus = CGPoint(x: 256.5, y: 344.33)
        XCTAssertFalse(MorphMenu.isNewFocus(CGPoint(x: 256.533, y: 344.35), comparedTo: focus))
        XCTAssertTrue(MorphMenu.isNewFocus(CGPoint(x: 256.5, y: 333.7), comparedTo: focus))
        XCTAssertTrue(MorphMenu.isNewFocus(focus, comparedTo: nil), "first measurement")
        XCTAssertTrue(MorphMenu.isNewFocus(nil, comparedTo: focus), "focus icon gone")
        XCTAssertFalse(MorphMenu.isNewFocus(nil, comparedTo: nil))
    }
}
