import XCTest

/// Screenshots for design review, not assertions about layout (the other UI tests do that).
/// Skipped unless a directory is given in xcodebuild's environment:
///
///     TEST_RUNNER_READER_SCREENSHOTS_DIR=/tmp/reader-shots \
///         xcodebuild test … -only-testing:ReaderUITests/ScreenshotCaptureTests
///
/// Each PNG goes to `<dir>/<test>/<name>.png` and is also attached to the test result. The
/// offline captures use the `reader-test://` pages; `testBrowserSurfaces` and `testBrowseBar`
/// need the network (favicons, a Wikipedia page, Google suggestions), `testBufferedFill` needs the
/// Kokoro model installed in the Simulator.
final class ScreenshotCaptureTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        guard let path = ProcessInfo.processInfo.environment["READER_SCREENSHOTS_DIR"], !path.isEmpty else {
            throw XCTSkip("Set TEST_RUNNER_READER_SCREENSHOTS_DIR=<dir> to capture screenshots.")
        }
        let test = name.split(separator: " ").last.map { String($0.dropLast()) } ?? "capture"
        dir = URL(fileURLWithPath: path).appendingPathComponent(test)
        continueAfterFailure = true
    }

    private func shot(_ name: String) throws {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try screenshot.pngRepresentation.write(to: dir.appendingPathComponent(name + ".png"))
    }

    private func wait(_ s: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-selectEngine", "apple"] + arguments
        app.launch()
        return app
    }

    /// Offline page two (an article): the page with its reader icon showing.
    private func openTestArticlePage(_ app: XCUIApplication) {
        let link = app.links["Next page"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.tap()
        XCTAssertTrue(el(app, "addressReader").waitForExistence(timeout: 5))
        wait(1)
    }

    private func dismissMenu(_ app: XCUIApplication, settle: TimeInterval = 0.8) {
        let dismiss = el(app, "moreMenuDismiss")
        if dismiss.waitForExistence(timeout: 2) {
            dismiss.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        }
        wait(settle)
    }

    // MARK: - Offline

    /// Toolbars and ⋯ menus on a page and in its reader (developer options off), the reader
    /// scrolled mid-article, Voice settings down to the version row, and the mini player.
    func testMenusOnPageAndInReader() throws {
        let app = launch(["-resetBookmarks", "-browseTestPages", "-reader.developerOptions", "NO"])
        openTestArticlePage(app)
        try shot("1-browse-toolbar")
        app.buttons["browseMore"].tap()
        wait(1.5)
        try shot("2-browse-menu")
        dismissMenu(app)

        el(app, "addressReader").tap()
        XCTAssertTrue(app.buttons["readerClose"].waitForExistence(timeout: 10))
        wait(1.5)
        try shot("3-reader-toolbar")
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -300)),
                   withVelocity: .slow, thenHoldForDuration: 0.1)
        wait(1.2)
        try shot("4-reader-scrolled")
        app.buttons["readerMore"].tap()
        wait(1.5)
        try shot("5-reader-menu")

        el(app, "moreVoice").tap()
        XCTAssertTrue(app.navigationBars["Listen"].waitForExistence(timeout: 5))
        wait(1)
        try shot("6-voice-settings")
        for _ in 0..<6 where !el(app, "settingsVersionRow").isHittable { app.swipeUp() }
        wait(0.8)
        try shot("7-voice-settings-version")
        app.navigationBars["Listen"].buttons["Done"].tap()
        wait(1)

        app.buttons["listenPlayPause"].tap()
        wait(2)
        app.buttons["readerClose"].tap()
        wait(1.5)
        try shot("8-browse-mini-player")
        app.buttons["miniPlayerPlayPause"].tap()
    }

    /// The ⋯ morph closed / mid-animation / open, slowed to 3 s (`-slowMenuAnimation`), on the
    /// start page (Reader disabled), on a page, and in the reader.
    func testMenuMorph() throws {
        let morph: TimeInterval = 3
        let app = launch(["-resetBookmarks", "-browseTestPages", "-slowMenuAnimation"])
        func sequence(button: String, prefix: String) throws {
            try shot("\(prefix)-closed")
            app.buttons[button].tap()
            wait(0.9)
            try shot("\(prefix)-mid-animation")
            wait(morph)
            XCTAssertTrue(el(app, "moreMenuPanel").exists)
            try shot("\(prefix)-open")
        }

        XCTAssertTrue(app.links["Next page"].waitForExistence(timeout: 10))
        app.buttons["browseMore"].tap()
        wait(morph + 0.6)
        XCTAssertFalse(el(app, "moreReaderToggle").isEnabled, "page one isn't readable")
        try shot("non-article-open")
        dismissMenu(app, settle: morph + 0.6)

        openTestArticlePage(app)
        try sequence(button: "browseMore", prefix: "browse")
        el(app, "moreReaderToggle").tap()
        XCTAssertTrue(app.buttons["readerClose"].waitForExistence(timeout: 10))
        wait(morph + 1)
        try sequence(button: "readerMore", prefix: "reader")
    }

    /// The scrub bubble frozen mid fine-scrub (`-scrubBubbleDemo`).
    func testScrubBubble() throws {
        let app = launch(["-seedDemoArticle", "-seedDemoParagraphs", "12", "-openLibrary", "-resetBookmarks",
                          "-scrubBubbleDemo"])
        let row = app.cells.staticTexts["Demo Listen Article"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.buttons["readerClose"].waitForExistence(timeout: 5))
        wait(2.5)
        try shot("scrub-bubble-fine")
    }

    // MARK: - Network or installed models

    /// Start page with bookmarks, the ⋯ menu, Bookmarks, Library and its reader, the mini player,
    /// a web page with its reader icon and the reader over it. Uses whatever is saved.
    func testBrowserSurfaces() throws {
        let app = launch(["-seedBookmarks"])
        wait(8) // bookmark icons load from the network
        try shot("start")

        app.buttons["browseMore"].tap()
        wait(1.2)
        try shot("menu")
        el(app, "moreBookmarks").tap()
        XCTAssertTrue(app.navigationBars["Bookmarks"].waitForExistence(timeout: 5))
        wait(1)
        try shot("bookmarks")
        app.navigationBars["Bookmarks"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.99)))
        wait(1)

        app.buttons["browseLibrary"].tap()
        XCTAssertTrue(app.navigationBars["Saved"].waitForExistence(timeout: 5))
        wait(1.2)
        try shot("library")
        let firstRow = app.cells.element(boundBy: 0)
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
        firstRow.staticTexts.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["readerClose"].waitForExistence(timeout: 10))
        wait(2)
        try shot("library-reader")

        let play = app.buttons["listenPlayPause"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()
        wait(3)
        app.buttons["readerClose"].tap()
        wait(1)
        app.navigationBars["Saved"].swipeDown(velocity: .fast)
        wait(1.5)
        XCTAssertTrue(el(app, "miniPlayer").waitForExistence(timeout: 5))
        try shot("start-mini-player")
        app.buttons["miniPlayerPlayPause"].tap()
        wait(0.5)

        let field = app.textFields["addressField"]
        field.tap()
        wait(0.6)
        field.typeText("en.wikipedia.org/wiki/Speech_synthesis\n")
        XCTAssertTrue(el(app, "addressReader").waitForExistence(timeout: 20), "readable page → reader icon")
        wait(1)
        try shot("page-reader-icon")
        el(app, "addressReader").tap()
        XCTAssertTrue(app.buttons["readerClose"].waitForExistence(timeout: 20))
        wait(2)
        try shot("page-reader")
    }

    /// The address bar idle on a page, editing with Recent Searches, editing with Google
    /// suggestions (this test turns them on: no `-uiTesting`), and the ⋯ menu.
    func testBrowseBar() throws {
        let app = XCUIApplication()
        app.launch()
        let field = app.textFields["addressField"]
        func open(_ text: String) {
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            wait(0.6) // the page address is selected on focus, so typing replaces it
            field.typeText(text + "\n")
            wait(6)
        }
        open("text to speech") // a search → Recent Searches
        open("en.wikipedia.org/wiki/Speech_synthesis")
        try shot("idle")
        field.tap()
        wait(1.2)
        try shot("editing")
        field.typeText("speech")
        wait(2.5)
        try shot("editing-suggestions")
        app.buttons["addressCancel"].tap()
        wait(1)
        app.buttons["browseMore"].tap()
        wait(1.2)
        try shot("menu")
    }

    /// Kokoro rendering ahead of the playhead: the scrubber's lighter buffered fill.
    func testBufferedFill() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-selectEngine", "local.kokoro", "-openLibrary"]
        app.launch()
        addTeardownBlock {
            let reset = XCUIApplication()
            reset.launchArguments = ["-uiTesting", "-selectEngine", "apple"]
            reset.launch()
            reset.terminate()
        }
        wait(20) // Kokoro load on the Simulator
        let firstRow = app.cells.element(boundBy: 0)
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
        firstRow.staticTexts.element(boundBy: 0).tap()
        let play = app.buttons["listenPlayPause"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        play.tap()
        wait(30) // play + render ahead
        play.tap()
        wait(4)
        try shot("reader-buffered-fill")
    }
}
