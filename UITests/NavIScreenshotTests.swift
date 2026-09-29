import XCTest

/// Nav I screenshots into `.probe/navI/`: five-slot toolbars (Browse / reader), scrub bubble,
/// ⋯ menus with developer options off, Voice settings version row, mini player.
/// Only runs with `TEST_RUNNER_READER_NAVI_SHOTS=1`.
final class NavIScreenshotTests: XCTestCase {
    private let dir = URL(fileURLWithPath: "/Users/jimmyyao/Developer/Reader/.probe/navI")

    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["READER_NAVI_SHOTS"] == "1" else {
            throw XCTSkip("Set TEST_RUNNER_READER_NAVI_SHOTS=1 to capture screenshots.")
        }
        continueAfterFailure = true
    }

    private func shot(_ name: String) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: dir.appendingPathComponent(name))
    }

    private func wait(_ s: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    func testCaptureToolbarsAndMenus() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetBookmarks", "-browseTestPages", "-selectEngine", "apple",
                               "-reader.developerOptions", "NO"]
        app.launch()
        let link = app.links["Next page"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.tap()
        XCTAssertTrue(el(app, "addressReader").waitForExistence(timeout: 5))
        wait(1)
        try shot("1-browse-toolbar.png")
        app.buttons["browseMore"].tap()
        wait(1.5)
        try shot("2-browse-menu-no-debug.png")
        el(app, "moreMenuDismiss").tap()
        wait(1)
        el(app, "addressReader").tap()
        XCTAssertTrue(app.buttons["readerClose"].waitForExistence(timeout: 10))
        wait(1.5)
        try shot("3-reader-toolbar.png")
        app.buttons["readerMore"].tap()
        wait(1.5)
        try shot("4-reader-menu-no-debug.png")
        el(app, "moreVoice").tap()
        XCTAssertTrue(app.navigationBars["Listen"].waitForExistence(timeout: 5))
        for _ in 0..<6 where !el(app, "settingsVersionRow").isHittable { app.swipeUp() }
        wait(0.8)
        try shot("5-voice-settings-version.png")
        app.navigationBars["Listen"].buttons["Done"].tap()
        wait(1)
        app.buttons["listenPlayPause"].tap()
        wait(2)
        app.buttons["readerClose"].tap()
        wait(1.5)
        try shot("6-browse-mini-player.png")
    }

    func testCaptureScrubBubble() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedDemoArticle", "-uiTesting", "-openLibrary", "-resetBookmarks",
                               "-selectEngine", "apple", "-scrubBubbleDemo", "-seedDemoParagraphs", "12"]
        app.launch()
        let row = app.cells.staticTexts["Demo Listen Article"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.buttons["readerClose"].waitForExistence(timeout: 5))
        wait(2.5)
        try shot("7-scrub-bubble-fine.png")
    }
}
