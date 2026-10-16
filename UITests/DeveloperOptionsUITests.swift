import XCTest

/// Developer options off (the Release default): no Developer section or Debug pill anywhere; a
/// long-press on the version row at the bottom of Settings turns them on and off. On: Settings ›
/// Developer opens the listen debug panel; no ⋯ has a Debug row.
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
    /// is at the bottom of Settings.
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
        XCTAssertTrue(el(app, "moreSettings").waitForExistence(timeout: 3))
        XCTAssertFalse(el(app, "moreDebug").exists, "no Debug row in the reader ⋯")
        wait(0.6)
        el(app, "moreSettings").tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let version = el(app, "settingsVersionRow")
        for _ in 0..<10 where !(version.exists && version.isHittable) { el(app, "settingsList").swipeUp() }
        XCTAssertTrue(version.waitForExistence(timeout: 3), "version row")
        XCTAssertFalse(el(app, "listenDebugEnabledToggle").exists, "no Developer section")

        // Long-press the version (2 s): developer options on, the Developer section comes back.
        version.press(forDuration: 2.4)
        let alert = app.alerts["Developer options on"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3), "confirmation")
        alert.buttons["OK"].tap()
        XCTAssertTrue(el(app, "listenDebugEnabledToggle").waitForExistence(timeout: 3), "Developer section shown")
        XCTAssertTrue(el(app, "fakeExtractionFailureToggle").exists, "with the browser's fake failure")
        for _ in 0..<4 where !(version.exists && version.isHittable) { el(app, "settingsList").swipeUp() }
        version.press(forDuration: 2.4)
        XCTAssertTrue(app.alerts["Developer options off"].waitForExistence(timeout: 3))
        app.alerts["Developer options off"].buttons["OK"].tap()
        XCTAssertTrue(waitFor { !self.el(app, "listenDebugEnabledToggle").exists })
    }

    /// Developer options on or off, no ⋯ has a Debug row: debug tools live in Settings › Developer.
    func testNoMenuHasADebugRow() throws {
        let app = launchLibrary(["-reader.developerOptions", "YES"])
        app.buttons["libraryMore"].tap()
        XCTAssertTrue(find(app, "moreSettings").waitForExistence(timeout: 3))
        XCTAssertFalse(find(app, "moreDebug").exists, "no Debug row in the Library ⋯")
        tapMenuRow(app, "moreBrowser")
        let more = app.buttons["browseMore"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()
        XCTAssertTrue(find(app, "moreSettings").waitForExistence(timeout: 3))
        XCTAssertFalse(find(app, "moreDebug").exists, "no Debug row in the browser ⋯")
    }

    /// Settings › Developer › Listen Debug Panel opens the panel over Settings, which stays.
    func testSettingsOpensTheListenDebugPanel() throws {
        let app = launchLibrary(["-reader.developerOptions", "YES"])
        let panel = app.navigationBars["Listen debug"]
        app.buttons["libraryMore"].tap()
        tapMenuRow(app, "moreSettings")
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let open = find(app, "listenDebugSettings")
        for _ in 0..<10 where !(open.exists && open.isHittable) { find(app, "settingsList").swipeUp() }
        open.tap()
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "the panel over Settings")
        panel.buttons["Done"].tap()
        XCTAssertTrue(eventually(5) { !panel.exists })
        XCTAssertTrue(app.navigationBars["Settings"].exists, "Settings stays")
    }

    /// Now Playing's other way in: a long-press on ⏸ (developer options on).
    func testLongPressOnPauseOpensTheListenDebugPanel() throws {
        let app = launchLibrary(["-reader.developerOptions", "YES", "-reader.listenDebugEnabled", "YES"])
        let panel = app.navigationBars["Listen debug"]
        let row = libraryRow(app, "Demo Listen Article")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let play = app.buttons["listenPlayPause"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        play.tap()
        XCTAssertTrue(find(app, "nowPlayingHeader").waitForExistence(timeout: 5), "Now Playing")
        play.press(forDuration: 1.2)
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "long-press ⏸ opens it")
        panel.buttons["Done"].tap()
        XCTAssertTrue(eventually(5) { !panel.exists })
        play.tap()
    }
}
