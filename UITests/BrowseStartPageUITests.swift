import XCTest

/// Start page (no page loaded): Continue listening (in-progress saves, tap to resume in the ✕
/// reader) and Saved (recent saves, Show All → library sheet).
final class BrowseStartPageUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func row(_ app: XCUIApplication, in section: String) -> XCUIElement {
        el(app, section).buttons.matching(NSPredicate(format: "label CONTAINS 'Demo Listen Article'")).firstMatch
    }

    func testContinueListeningResumesWhereYouLeftOff() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedDemoArticle", "-seedDemoProgress", "1", "-uiTesting"]
        app.launch()

        XCTAssertTrue(el(app, "startContinue").waitForExistence(timeout: 10), "Continue listening section")
        let resume = row(app, in: "startContinue")
        XCTAssertTrue(resume.exists, "in-progress article listed")
        XCTAssertFalse(el(app, "startSaved").exists, "not repeated under Saved")

        resume.tap()
        let close = app.buttons["readerClose"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertEqual(close.label, "Hide Reader", "opens in the ✕ reader over the browser")
        let scrubber = el(app, "readerScrubber")
        XCTAssertTrue(scrubber.waitForExistence(timeout: 5))
        XCTAssertEqual(scrubber.value as? String, "Paragraph 2 of 3", "resumes at the saved paragraph")
        close.tap()
        XCTAssertTrue(el(app, "startContinue").waitForExistence(timeout: 5))
    }

    func testSavedSectionShowAllOpensLibrary() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedDemoArticle", "-uiTesting"]
        app.launch()

        XCTAssertTrue(el(app, "startSaved").waitForExistence(timeout: 10), "Saved section")
        XCTAssertFalse(el(app, "startContinue").exists, "unstarted article isn't in progress")
        XCTAssertTrue(row(app, in: "startSaved").exists)

        el(app, "startSavedShowAll").tap()
        XCTAssertTrue(app.navigationBars["Saved"].waitForExistence(timeout: 5), "library sheet")
        XCTAssertTrue(app.searchFields["Search saved"].exists, "search pinned under the title")
        app.cells.staticTexts["Demo Listen Article"].tap()
        let close = app.buttons["readerClose"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertEqual(close.label, "Back", "library pushes the ‹ reader")
    }
}
