import XCTest

/// Screenshots of the Browse bar (idle, editing with Recent Searches, editing with suggestions,
/// ⋯ menu) into `.probe/browse-bar/`. Uses the network, so it only runs with
/// `TEST_RUNNER_READER_BROWSE_SHOTS=1`.
final class BrowseBarScreenshotTests: XCTestCase {
    private let dir = URL(fileURLWithPath: "/Users/jimmyyao/Developer/Reader/.probe/browse-bar")

    private func shot(_ name: String) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: dir.appendingPathComponent(name))
    }

    private func wait(_ s: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }

    private func open(_ app: XCUIApplication, _ text: String) {
        let field = app.textFields["addressField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        wait(0.6) // the page address is selected on focus, so typing replaces it
        field.typeText(text + "\n")
        wait(6)
    }

    func testCaptureBrowseBar() throws {
        guard ProcessInfo.processInfo.environment["READER_BROWSE_SHOTS"] == "1" else {
            throw XCTSkip("Set TEST_RUNNER_READER_BROWSE_SHOTS=1 to capture Browse screenshots.")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        open(app, "text to speech")                        // a search → Recent Searches
        open(app, "en.wikipedia.org/wiki/Speech_synthesis") // a page
        try shot("browse-idle.png")

        let field = app.textFields["addressField"]
        field.tap()
        wait(1.2)
        try shot("browse-editing.png")

        field.typeText("speech")
        wait(2.5)
        try shot("browse-editing-suggestions.png")

        app.buttons["addressCancel"].tap()
        wait(1)
        app.buttons["browseMore"].tap()
        wait(1.2)
        try shot("browse-more-menu.png")
    }
}
