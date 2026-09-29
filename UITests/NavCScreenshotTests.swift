import XCTest

/// Screenshots of the tab-less browser (start page, ⋯ popover, library sheet, readers, mini player,
/// scrubber buffered fill) into `.probe/navC/`. Uses real saved data + the network, so it only runs
/// with `TEST_RUNNER_READER_NAVC_SHOTS=1`.
final class NavCScreenshotTests: XCTestCase {
    private let dir = URL(fileURLWithPath: "/Users/jimmyyao/Developer/Reader/.probe/navC")

    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["READER_NAVC_SHOTS"] == "1" else {
            throw XCTSkip("Set TEST_RUNNER_READER_NAVC_SHOTS=1 to capture screenshots.")
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

    private func openLibrary(_ app: XCUIApplication) {
        app.buttons["browseMore"].tap()
        wait(0.8)
        el(app, "moreLibrary").tap()
        XCTAssertTrue(app.navigationBars["Saved"].waitForExistence(timeout: 5))
        wait(1)
    }

    func testCaptureBrowser() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-selectEngine", "apple", "-seedBookmarks"]
        app.launch()
        wait(8) // bookmark icons load from the network
        try shot("start.png")

        app.buttons["browseMore"].tap()
        wait(1.2)
        try shot("more-popover.png")
        el(app, "moreBookmarks").tap()
        XCTAssertTrue(app.navigationBars["Bookmarks"].waitForExistence(timeout: 5))
        wait(1)
        try shot("bookmarks.png")
        let bar = app.navigationBars["Bookmarks"]
        bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.99)))
        wait(1)

        app.buttons["browseMore"].tap()
        wait(0.8)
        el(app, "moreLibrary").tap()
        XCTAssertTrue(app.navigationBars["Saved"].waitForExistence(timeout: 5))
        wait(1.2)
        try shot("library.png")

        // Reader from the library (‹, pushed in the sheet).
        let firstRow = app.cells.element(boundBy: 0)
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
        firstRow.staticTexts.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["readerClose"].waitForExistence(timeout: 10))
        wait(2)
        try shot("reader-library.png")

        // Play, go back, dismiss the sheet → mini player on the start page.
        let play = app.buttons["listenPlayPause"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()
        wait(3)
        app.buttons["readerClose"].tap()
        wait(1)
        app.navigationBars["Saved"].swipeDown(velocity: .fast)
        wait(1.5)
        XCTAssertTrue(el(app, "miniPlayer").waitForExistence(timeout: 5))
        try shot("start-mini-player.png")
        app.buttons["miniPlayerPlayPause"].tap() // pause
        wait(0.5)

        // Reader from a web page (✕ over the browser).
        let field = app.textFields["addressField"]
        field.tap()
        wait(0.6)
        field.typeText("en.wikipedia.org/wiki/Speech_synthesis\n")
        XCTAssertTrue(el(app, "addressReader").waitForExistence(timeout: 20), "readable page → reader icon")
        wait(1)
        try shot("browse-page-reader-icon.png")
        el(app, "addressReader").tap()
        XCTAssertTrue(app.buttons["readerClose"].waitForExistence(timeout: 20))
        wait(2)
        try shot("reader-browse.png")
    }

    /// Kokoro renders ahead of the playhead → the scrubber's lighter buffered fill.
    func testCaptureBufferedFill() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-selectEngine", "local.kokoro"]
        app.launch()
        addTeardownBlock {
            let reset = XCUIApplication()
            reset.launchArguments = ["-selectEngine", "apple", "-uiTesting"]
            reset.launch()
            reset.terminate()
        }
        wait(20) // Kokoro host load on the Simulator
        openLibrary(app)
        let firstRow = app.cells.element(boundBy: 0)
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
        firstRow.staticTexts.element(boundBy: 0).tap()
        let play = app.buttons["listenPlayPause"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        play.tap()
        wait(30) // play + render ahead
        play.tap() // pause
        wait(4)
        try shot("reader-buffered-fill.png")
    }
}
