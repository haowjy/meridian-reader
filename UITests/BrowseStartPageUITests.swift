import XCTest

/// Start page (no page loaded): Continue listening (in-progress saves, tap to open in the Reader
/// sheet at their spot) and Saved (recent saves, Show All → library).
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
        XCTAssertEqual(close.label, "Back to Browser", "opens in the Reader sheet over the browser")
        let listen = app.buttons["listenPlayPause"]
        XCTAssertTrue(listen.waitForExistence(timeout: 5))
        XCTAssertTrue(listen.label.hasPrefix("Resume"), "resumes at the saved paragraph: \(listen.label)")
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
        XCTAssertTrue(app.navigationBars["Saved"].waitForExistence(timeout: 5), "library surface")
        XCTAssertTrue(el(app, "librarySearchField").exists, "search in the bottom field capsule")
        app.cells.staticTexts["Demo Listen Article"].tap()
        let close = app.buttons["readerClose"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertEqual(close.label, "Back to Library", "library pushes the reader")
    }
}
