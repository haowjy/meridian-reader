import XCTest

/// Screenshots of the unified ⋯ popover (start page with Reader disabled, readable web page, inside
/// reader mode with Reader selected), the voice settings sheet, and the reader listen bar, into
/// `.probe/navD/`. Uses the network, so it only runs with `TEST_RUNNER_READER_NAVD_SHOTS=1`.
final class NavDScreenshotTests: XCTestCase {
    private let dir = URL(fileURLWithPath: "/Users/jimmyyao/Developer/Reader/.probe/navD")

    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["READER_NAVD_SHOTS"] == "1" else {
            throw XCTSkip("Set TEST_RUNNER_READER_NAVD_SHOTS=1 to capture screenshots.")
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

    private func dismissPopover(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        wait(0.8)
    }

    func testCaptureMenus() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-selectEngine", "apple", "-seedBookmarks"]
        app.launch()
        wait(6) // bookmark icons

        // Start page: Reader disabled.
        app.buttons["browseMore"].tap()
        wait(1.2)
        XCTAssertFalse(el(app, "moreReaderToggle").isEnabled)
        try shot("popover-start-page.png")
        dismissPopover(app)

        // Readable web page.
        let field = app.textFields["addressField"]
        field.tap()
        wait(0.6)
        field.typeText("en.wikipedia.org/wiki/Speech_synthesis\n")
        XCTAssertTrue(el(app, "addressReader").waitForExistence(timeout: 20), "readable page")
        wait(1.5)
        app.buttons["browseMore"].tap()
        wait(1.2)
        XCTAssertTrue(el(app, "moreReaderToggle").isEnabled)
        try shot("popover-web-page.png")

        // ⋯ → Reader: reader mode; its listen bar ends in ⋯.
        el(app, "moreReaderToggle").tap()
        XCTAssertTrue(app.buttons["readerClose"].waitForExistence(timeout: 20))
        wait(2.5)
        try shot("reader-listen-bar.png")

        app.buttons["readerMore"].tap()
        wait(1.2)
        XCTAssertTrue(el(app, "moreWebsite").exists, "reader mode: Website in the Reader slot (Nav H)")
        try shot("popover-reader-mode.png")

        el(app, "moreVoice").tap()
        XCTAssertTrue(app.navigationBars["Listen"].waitForExistence(timeout: 5))
        wait(1.2)
        try shot("voice-settings.png")
    }
}
