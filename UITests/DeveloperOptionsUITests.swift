import XCTest

/// Developer options off (the Release default): no Debug rows or pill anywhere; a long-press on
/// the version row in Voice settings turns them on and off. On: the ⋯ Debug rows open the listen
/// debug panel, over the Library and the Reader.
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

    /// Developer options on: the Library's ⋯ has *Debug*, and the Reader's row opens it too.
    func testLibraryDebugRowOpensTheListenDebugPanel() throws {
        let app = launchLibrary(["-reader.developerOptions", "YES"])
        let panel = app.navigationBars["Listen debug"]

        app.buttons["libraryMore"].tap()
        tapMenuRow(app, "moreDebug")
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "the panel over the Library")
        panel.buttons["Done"].tap()
        XCTAssertTrue(eventually(5) { !panel.exists }, "Done closes it")
        XCTAssertTrue(app.libraryHome.exists, "back on the Library")

        let row = libraryRow(app, "Demo Listen Article")
        find(app, "libraryHome").swipeUp()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.buttons["readerMore"].waitForExistence(timeout: 5), "the Reader")
        app.buttons["readerMore"].tap()
        tapMenuRow(app, "moreDebug")
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "the panel over the Reader")
    }

    /// The panel's other ways in, which share the shell's host: Now Playing's ⋯ *Debug*, long-press
    /// ⏸, and Voice settings' *Open full panel* (its own host, over the settings sheet).
    func testNowPlayingAndSettingsOpenTheListenDebugPanel() throws {
        let app = launchLibrary(["-reader.developerOptions", "YES", "-reader.listenDebugEnabled", "YES"])
        let panel = app.navigationBars["Listen debug"]
        let row = libraryRow(app, "Demo Listen Article")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let play = app.buttons["listenPlayPause"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        play.tap()
        XCTAssertTrue(find(app, "nowPlayingFrom").waitForExistence(timeout: 5), "Now Playing")

        app.buttons["readerMore"].tap()
        tapMenuRow(app, "moreDebug")
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "the panel over Now Playing")
        panel.buttons["Done"].tap()
        XCTAssertTrue(eventually(5) { !panel.exists })

        play.press(forDuration: 1.2)
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "long-press ⏸ opens it")
        panel.buttons["Done"].tap()
        XCTAssertTrue(eventually(5) { !panel.exists })

        app.buttons["readerMore"].tap()
        tapMenuRow(app, "moreVoice")
        XCTAssertTrue(app.navigationBars["Listen"].waitForExistence(timeout: 5), "Voice settings")
        let open = find(app, "listenDebugSettings")
        for _ in 0..<6 where !(open.exists && open.isHittable) { app.swipeUp() }
        open.tap()
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "the panel over Voice settings")
        panel.buttons["Done"].tap()
        XCTAssertTrue(eventually(5) { !panel.exists })
        XCTAssertTrue(app.navigationBars["Listen"].exists, "Voice settings stays")
    }

    /// Developer options off: no Debug row in the Library's ⋯.
    func testDeveloperOptionsOffHidesLibraryDebugRow() throws {
        let app = launchLibrary(["-reader.developerOptions", "NO"])
        app.buttons["libraryMore"].tap()
        XCTAssertTrue(find(app, "moreVoice").waitForExistence(timeout: 3))
        XCTAssertFalse(find(app, "moreDebug").exists, "no Debug row in the Library ⋯")

    }
}
