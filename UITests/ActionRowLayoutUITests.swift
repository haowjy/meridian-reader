import XCTest

/// Decision D21 on the demo book's screen: the header's action row (Continue, From Start,
/// Download) stays on one line at the default and the largest text size, on any phone width the
/// suite runs on; a page row is two lines (its title on one), with Download and ▶ side by side,
/// and ▶ turns to ⏸ on the page that plays. Offline, Apple voice.
final class ActionRowLayoutUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private static let largestText = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]

    func testHeaderActionsShareOneRow() throws {
        let app = launchLibrary(["-seedDemoBookPlace", "2"])
        openFolder(app, "The Demo Book")
        assertActionsOnOneRow(app)
    }

    func testHeaderActionsShareOneRowAtTheLargestText() throws {
        let app = launchLibrary(["-seedDemoBookPlace", "2"] + Self.largestText)
        openFolder(app, "The Demo Book")
        assertActionsOnOneRow(app)
    }

    func testPageRowsAreTwoLines() throws {
        let app = launchLibrary()
        openFolder(app, "The Demo Book")
        assertTwoLineRows(app, maxRowHeight: 72)
    }

    func testPageRowsAreTwoLinesAtTheLargestText() throws {
        let app = launchLibrary(Self.largestText)
        openFolder(app, "The Demo Book")
        assertTwoLineRows(app, maxRowHeight: nil)
    }

    /// D23: one compact row everywhere. On the Library home a book (cover and details) and a page
    /// are the same height, two lines tall.
    func testBookAndPageRowsShareOneCompactHeight() throws {
        let app = launchLibrary()
        let book = libraryCell(app, "The Demo Book"), page = libraryCell(app, "Demo Listen Article")
        XCTAssertTrue(book.waitForExistence(timeout: 5), "book row")
        XCTAssertTrue(page.waitForExistence(timeout: 5), "page row")
        XCTAssertEqual(book.frame.height, page.frame.height, accuracy: 1, "book and page rows the same height")
        XCTAssertLessThan(book.frame.height, 72, "compact, got \(book.frame.height) pt")
    }

    /// ▶ on a row plays that page and turns to ⏸ there; the row's second line says so.
    func testARowsPlayTurnsToPause() throws {
        let app = launchLibrary()
        openFolder(app, "The Demo Book")
        let title = "Chapter 3: The Tide"
        let cell = libraryCell(app, title)
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        cell.buttons["Play"].tap()
        XCTAssertTrue(cell.buttons["Pause"].waitForExistence(timeout: 10), "▶ turned to ⏸")
        let row = libraryRow(app, title)
        XCTAssertTrue(eventually(5) { (row.value as? String)?.contains("Playing") == true }, "got \(row.value ?? "nil")")
        cell.buttons["Pause"].tap()
        XCTAssertTrue(eventually(5) { (row.value as? String)?.contains("Paused") == true }, "got \(row.value ?? "nil")")
    }

    // MARK: - Checks

    private func assertActionsOnOneRow(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let ids = ["folderContinue", "folderPlayFromStart", "folderDownload"]
        var frames: [CGRect] = []
        for id in ids {
            let button = app.buttons[id]
            XCTAssertTrue(button.waitForExistence(timeout: 5), id, file: file, line: line)
            frames.append(button.frame)
        }
        let window = app.windows.firstMatch.frame
        for (id, frame) in zip(ids, frames) {
            XCTAssertEqual(frame.midY, frames[0].midY, accuracy: 1, "\(id) on Continue's row", file: file, line: line)
            XCTAssertGreaterThanOrEqual(frame.minX, window.minX, "\(id) on screen", file: file, line: line)
            XCTAssertLessThanOrEqual(frame.maxX, window.maxX, "\(id) on screen", file: file, line: line)
        }
        for i in 1..<frames.count {
            XCTAssertLessThanOrEqual(frames[i - 1].maxX, frames[i].minX, "\(ids[i]) after \(ids[i - 1])", file: file, line: line)
        }
        let download = frames[2]
        XCTAssertEqual(download.width, download.height, accuracy: 1, "Download is round, icon only", file: file, line: line)
    }

    /// Every chapter's title takes one line (as tall as the shortest title's), the row stays
    /// under `maxRowHeight`, the author isn't repeated on it, and Download and ▶ sit side by side
    /// on the row's middle.
    private func assertTwoLineRows(_ app: XCUIApplication, maxRowHeight: CGFloat?,
                                   file: StaticString = #filePath, line: UInt = #line) {
        let short = libraryRow(app, "Title Page")
        // At the largest text the header fills the screen: scroll the first rows into view.
        for _ in 0..<4 where !short.waitForExistence(timeout: 2) || !short.isHittable {
            find(app, "folderScreen").swipeUp()
            idle(0.4)
        }
        XCTAssertTrue(short.waitForExistence(timeout: 5), "Title Page row", file: file, line: line)
        let oneLine = short.frame.height
        for title in ["Chapter 1: The Harbor", "Chapter 2: The Lighthouse", "Chapter 3: The Tide"] {
            let row = libraryRow(app, title), cell = libraryCell(app, title)
            for _ in 0..<3 where !row.isHittable {
                find(app, "folderScreen").swipeUp()
                idle(0.4)
            }
            XCTAssertTrue(row.waitForExistence(timeout: 5), title, file: file, line: line)
            XCTAssertEqual(row.frame.height, oneLine, accuracy: 2, "\(title): one line", file: file, line: line)
            if let maxRowHeight {
                XCTAssertLessThan(cell.frame.height, maxRowHeight, "\(title): two lines, got \(cell.frame.height) pt",
                                  file: file, line: line)
            }
            XCTAssertFalse((row.value as? String)?.contains("Demo Author") == true,
                           "\(title): no author line, got \(row.value ?? "nil")", file: file, line: line)
            let download = cell.buttons["libraryRowDownload"].frame, play = cell.buttons["Play"].frame
            XCTAssertEqual(download.midY, play.midY, accuracy: 1, "\(title): side by side", file: file, line: line)
            XCTAssertEqual(play.midY, cell.frame.midY, accuracy: 2, "\(title): centred on the row", file: file, line: line)
            XCTAssertLessThanOrEqual(download.maxX, play.minX, "\(title): Download, then ▶", file: file, line: line)
        }
    }
}
