import XCTest

/// Screenshots of the Safari-style morph ⋯ panel (grows out of the button, covers it, no arrow)
/// into `.probe/navE/`: closed / mid-animation / open, for the browser toolbar ⋯ and the reader
/// listen bar ⋯, plus the start page. Runs with a slowed (3 s) morph so a mid frame can be caught.
/// Uses the network, so it only runs with `TEST_RUNNER_READER_NAVE_SHOTS=1`.
final class NavEScreenshotTests: XCTestCase {
    private let dir = URL(fileURLWithPath: "/Users/jimmyyao/Developer/Reader/.probe/navE")
    /// `-slowMenuAnimation` = 3 s ease-in-out.
    private let morph: TimeInterval = 3

    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["READER_NAVE_SHOTS"] == "1" else {
            throw XCTSkip("Set TEST_RUNNER_READER_NAVE_SHOTS=1 to capture screenshots.")
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

    private func dismiss(_ app: XCUIApplication) {
        let d = el(app, "moreMenuDismiss")
        if d.waitForExistence(timeout: 2) { d.tap() }
        else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap() }
        wait(morph + 0.6)
    }

    /// closed → tap → mid (≈40 % in) → open.
    private func captureSequence(_ app: XCUIApplication, button: String, prefix: String) throws {
        try shot("\(prefix)-closed.png")
        app.buttons[button].tap()
        wait(0.9)
        try shot("\(prefix)-mid-animation.png")
        wait(morph)
        XCTAssertTrue(el(app, "moreMenuPanel").exists)
        try shot("\(prefix)-open.png")
    }

    func testCaptureMorphMenus() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-selectEngine", "apple", "-seedBookmarks", "-slowMenuAnimation"]
        app.launch()
        wait(6) // bookmark icons

        // Start page: Reader disabled.
        app.buttons["browseMore"].tap()
        wait(morph + 0.6)
        XCTAssertFalse(el(app, "moreReaderToggle").isEnabled)
        try shot("start-open.png")
        dismiss(app)

        // Readable web page.
        let field = app.textFields["addressField"]
        field.tap()
        wait(0.6)
        field.typeText("en.wikipedia.org/wiki/Speech_synthesis\n")
        XCTAssertTrue(el(app, "addressReader").waitForExistence(timeout: 20), "readable page")
        wait(2)
        try captureSequence(app, button: "browseMore", prefix: "browse")
        XCTAssertTrue(el(app, "moreReaderToggle").isEnabled)
        XCTAssertFalse(el(app, "moreReaderToggle").isSelected)

        // ⋯ → Reader: reader mode; its listen bar ends in ⋯.
        el(app, "moreReaderToggle").tap()
        XCTAssertTrue(app.buttons["readerClose"].waitForExistence(timeout: 20))
        wait(morph + 1)
        try captureSequence(app, button: "readerMore", prefix: "reader")
        XCTAssertTrue(el(app, "moreWebsite").exists, "reader mode: Website in the Reader slot (Nav H)")
    }
}
