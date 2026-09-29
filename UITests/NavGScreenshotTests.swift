import XCTest

/// Nav G screenshots into `.probe/navG/`: the same Wikipedia article in the browser and in the
/// reader (bottom chrome side by side), the library reader and the reader ⋯ menu. Uses the
/// network, so it only runs with `TEST_RUNNER_READER_NAVG_SHOTS=1`.
final class NavGScreenshotTests: XCTestCase {
    private let dir = URL(fileURLWithPath: "/Users/jimmyyao/Developer/Reader/.probe/navG")

    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["READER_NAVG_SHOTS"] == "1" else {
            throw XCTSkip("Set TEST_RUNNER_READER_NAVG_SHOTS=1 to capture screenshots.")
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

    func testCaptureBrowseAndReader() throws {
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
        let browseMore = app.buttons["browseMore"].frame
        try shot("browse-full.png")
        el(app, "addressReader").tap()
        XCTAssertTrue(app.buttons["readerClose"].waitForExistence(timeout: 20))
        wait(2.5)
        try shot("reader-full.png")
        let readerMore = app.buttons["readerMore"].frame
        XCTAssertEqual(readerMore.midX, browseMore.midX, accuracy: 1)
        XCTAssertEqual(readerMore.midY, browseMore.midY, accuracy: 1)
        try "browseMore \(browseMore)\nreaderMore \(readerMore)\n"
            .write(to: dir.appendingPathComponent("more-frames.txt"), atomically: true, encoding: .utf8)
        app.buttons["readerMore"].tap()
        wait(1.2)
        XCTAssertTrue(el(app, "moreMenuPanel").exists)
        try shot("menu-open.png")
    }

    func testCaptureLibraryReader() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedDemoArticle", "-seedDemoParagraphs", "40", "-openLibrary",
                               "-uiTesting", "-selectEngine", "apple"]
        app.launch()
        let row = app.cells.staticTexts["Demo Listen Article"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.buttons["readerClose"].waitForExistence(timeout: 5))
        wait(2)
        try shot("library-reader.png")
    }
}
