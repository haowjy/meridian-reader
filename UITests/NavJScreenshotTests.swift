import XCTest

/// Nav J screenshots into `.probe/navJ/`: menu closed / open for Browse and the reader, showing
/// the Website/Reader icon slightly up and left of ⋯ (Safari feel).
/// Only runs with `TEST_RUNNER_READER_NAVJ_SHOTS=1`.
final class NavJScreenshotTests: XCTestCase {
    private let dir = URL(fileURLWithPath: "/Users/jimmyyao/Developer/Reader/.probe/navJ")

    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["READER_NAVJ_SHOTS"] == "1" else {
            throw XCTSkip("Set TEST_RUNNER_READER_NAVJ_SHOTS=1 to capture screenshots.")
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

    func testCaptureMenuClosedAndOpen() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetBookmarks", "-browseTestPages", "-selectEngine", "apple",
                               "-reader.developerOptions", "NO"]
        app.launch()
        let link = app.links["Next page"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.tap()
        XCTAssertTrue(el(app, "addressReader").waitForExistence(timeout: 5))
        wait(1)
        try shot("browse-menu-closed.png")
        app.buttons["browseMore"].tap()
        wait(1.5)
        try shot("browse-menu-open.png")
        el(app, "moreMenuDismiss").tap()
        wait(0.8)
        el(app, "addressReader").tap()
        XCTAssertTrue(app.buttons["readerClose"].waitForExistence(timeout: 10))
        wait(1.2)
        try shot("reader-menu-closed.png")
        app.buttons["readerMore"].tap()
        wait(1.5)
        try shot("reader-menu-open.png")
    }
}
