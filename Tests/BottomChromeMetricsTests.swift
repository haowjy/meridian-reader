import XCTest
@testable import MeridianReader

/// The field capsule and its controls grow with Dynamic Type, within limits.
final class BottomChromeMetricsTests: XCTestCase {
    func testGrowsWithTextUpToTheCap() {
        XCTAssertEqual(BottomChrome.grown(44, from: 44), 44, "default size")
        XCTAssertEqual(BottomChrome.grown(55, from: 44), 55, "grows with the text")
        XCTAssertEqual(BottomChrome.grown(140, from: 44), 44 * BottomChrome.maxTextGrowth, "capped")
        XCTAssertEqual(BottomChrome.grown(38, from: 44), 44, "never smaller than the default")
    }
}
