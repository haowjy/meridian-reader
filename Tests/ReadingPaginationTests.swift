import XCTest
@testable import MeridianReader

/// Pages mode's page breaks: whole lines only, and a box taller than a page on a page of its own.
final class ReadingPaginationTests: XCTestCase {
    func testPagesHoldWholeLines() {
        typealias Line = ReadingPagination.Line
        // Four 30 pt lines from 10, a 250 pt image after a gap, one more line; pages 100 pt tall.
        let lines = [Line(top: 10, bottom: 40), Line(top: 40, bottom: 70), Line(top: 70, bottom: 100),
                     Line(top: 100, bottom: 130), Line(top: 150, bottom: 400), Line(top: 410, bottom: 440)]
        let pages = ReadingPagination(lines: lines, pageHeight: 100, margin: 8).pages
        XCTAssertEqual(pages.map(\.top), [0, 100, 150, 410], "the first page from the top, the rest from a line's top")
        XCTAssertEqual(pages.map(\.bottom), [100, 130, 250, 440], "the line at 100–130 ends a page; the image is cut")
        XCTAssertEqual(pages[1].visibleTop, 100, "no room above: the line before touches it")
        XCTAssertEqual(pages[1].visibleBottom, 138, "into the gap below, up to the margin")
    }
}
