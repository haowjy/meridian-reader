import XCTest

/// Nav H screenshots into `.probe/navH/`: the reader mid-article (bars stay), the ⋯ menu closed /
/// open (Website icon where ⋯ was) and the Browse toolbar with the centered Saved button. Uses the
/// network, so it only runs with `TEST_RUNNER_READER_NAVH_SHOTS=1`.
final class NavHScreenshotTests: XCTestCase {
    private let dir = URL(fileURLWithPath: "/Users/jimmyyao/Developer/Reader/.probe/navH")

    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["READER_NAVH_SHOTS"] == "1" else {
            throw XCTSkip("Set TEST_RUNNER_READER_NAVH_SHOTS=1 to capture screenshots.")
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

    func testCapture() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-selectEngine", "apple"]
        app.launch()
        let field = app.textFields["addressField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        wait(0.6)
        field.typeText("en.wikipedia.org/wiki/Speech_synthesis\n")
        XCTAssertTrue(el(app, "addressReader").waitForExistence(timeout: 20), "readable page")
        wait(2)
        try shot("browse-toolbar.png")
        el(app, "addressReader").tap()
        XCTAssertTrue(app.buttons["readerClose"].waitForExistence(timeout: 20))
        wait(2.5)
        // Mid-article: the bars stay.
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
        for _ in 0..<2 {
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -300)),
                       withVelocity: .slow, thenHoldForDuration: 0.1)
            wait(0.8)
        }
        wait(1)
        try shot("reader.png")
        try shot("menu-closed.png")
        let more = app.buttons["readerMore"].frame
        app.buttons["readerMore"].tap()
        wait(1.5)
        try shot("menu-open.png")
        let focus = el(app, "moreMenuFocus").frame
        try "readerMore \(more) center (\(more.midX), \(more.midY))\nmenu focus \(focus) center (\(focus.midX), \(focus.midY))\n"
            .write(to: dir.appendingPathComponent("alignment.txt"), atomically: true, encoding: .utf8)
    }
}
