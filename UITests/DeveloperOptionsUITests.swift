import XCTest

/// Developer options off (the Release default): no Debug rows or pill anywhere; a long-press on
/// the version row in Voice settings turns them on and off.
final class DeveloperOptionsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func wait(_ s: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }

    private func waitFor(_ timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            wait(0.1)
        }
        return condition()
    }

    /// Release default (forced here with the launch argument): no Debug anywhere; the version row
    /// is in Voice settings.
    func testDeveloperOptionsOffHidesDebug() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedDemoArticle", "-uiTesting", "-openLibrary", "-resetBookmarks", "-reader.rateMultiplier", "1",
                               "-selectEngine", "apple",
                               "-reader.developerOptions", "NO", "-reader.listenDebugEnabled", "YES"]
        app.launch()
        let row = app.cells.staticTexts["Demo Listen Article"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.buttons["readerClose"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["listenPlayPause"].waitForExistence(timeout: 5))
        XCTAssertFalse(el(app, "listenBakeDebugChip").exists, "no Debug pill even with Listen debug stored on")

        app.buttons["readerMore"].tap()
        XCTAssertTrue(el(app, "moreVoice").waitForExistence(timeout: 3))
        XCTAssertFalse(el(app, "moreDebug").exists, "no Debug row in the reader ⋯")
        wait(0.6)
        el(app, "moreVoice").tap()
        XCTAssertTrue(app.navigationBars["Listen"].waitForExistence(timeout: 5))
        let version = el(app, "settingsVersionRow")
        for _ in 0..<6 where !version.exists { app.swipeUp() }
        XCTAssertTrue(version.waitForExistence(timeout: 3), "version row")
        XCTAssertFalse(el(app, "listenDebugEnabledToggle").exists, "no Listen debug section")

        // Long-press the version (2 s): developer options on, Listen debug comes back.
        version.press(forDuration: 2.4)
        let alert = app.alerts["Developer options on"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3), "confirmation")
        alert.buttons["OK"].tap()
        XCTAssertTrue(el(app, "listenDebugEnabledToggle").waitForExistence(timeout: 3), "debug section shown")
        for _ in 0..<4 where !(version.exists && version.isHittable) { app.swipeUp() }
        version.press(forDuration: 2.4)
        XCTAssertTrue(app.alerts["Developer options off"].waitForExistence(timeout: 3))
        app.alerts["Developer options off"].buttons["OK"].tap()
        XCTAssertTrue(waitFor { !self.el(app, "listenDebugEnabledToggle").exists })
    }

    func testDeveloperOptionsOffHidesBrowseDebugRow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetBookmarks", "-reader.developerOptions", "NO"]
        app.launch()
        let more = app.buttons["browseMore"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()
        XCTAssertTrue(el(app, "moreVoice").waitForExistence(timeout: 3))
        XCTAssertFalse(el(app, "moreDebug").exists, "no Debug row in the browser ⋯")
    }
}
