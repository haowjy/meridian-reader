import XCTest

/// Navigation rule (docs/NAVIGATION.md): ‹ screens pop with a left-edge swipe; sheets (the Reader,
/// Now Playing) close with a pull down on their header (or on their text from its top,
/// `SheetPullFromTextUITests`). Either gesture does exactly what its button does, and closing
/// never stops audio.
final class SwipeBackUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
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

    /// Coordinate drag from x≈2 (left screen edge) to the middle of the screen.
    private func edgeSwipe(_ app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 2, dy: 0))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .default, thenHoldForDuration: 0.05)
        wait(0.8)
    }

    private func startPlayback(_ app: XCUIApplication) {
        let play = app.buttons["listenPlayPause"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        XCTAssertTrue(waitFor(10) { play.isEnabled }, "listen document ready")
        play.tap()
        XCTAssertTrue(waitFor(8) { play.label == "Pause" }, "playback started")
    }

    /// Pulls a sheet down by `header` (an element in its header row), off to the side of it.
    private func pullDown(_ header: XCUIElement) {
        let start = header.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: 140, dy: 0))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 420)),
                    withVelocity: .default, thenHoldForDuration: 0)
        wait(0.8)
    }

    func testPullDownFromLibraryNowPlayingReturnsToSavedAndKeepsPlaying() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedDemoArticle", "-uiTesting", "-openLibrary", "-selectEngine", "apple"]
        app.launch()

        let row = app.cells.staticTexts["Demo Listen Article"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))

        // Root screen: an edge swipe does nothing and must not wedge the navigation stack.
        edgeSwipe(app)
        XCTAssertTrue(row.isHittable, "still on the Library home")

        row.tap()
        let close = app.buttons["readerClose"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertEqual(close.label, "Back to Library", "the Reader's back pill says where it goes")
        startPlayback(app) // Listen: the Reader turns into Now Playing
        let from = app.descendants(matching: .any)["nowPlayingFrom"]
        XCTAssertTrue(from.waitForExistence(timeout: 5))

        pullDown(from)
        XCTAssertTrue(waitFor(5) { !from.exists }, "Now Playing pulled down")
        XCTAssertTrue(waitFor(5) { row.isHittable }, "the Library home is showing again")
        XCTAssertTrue(app.libraryHome.exists, "the Library home is back")

        // Same as ⌄: playback keeps going (the row button shows Pause).
        let rowPause = app.cells.buttons["Pause"]
        XCTAssertTrue(rowPause.waitForExistence(timeout: 3), "audio kept playing after the pull down")
        rowPause.tap()
        // The row's ▶ is the design system's PlayStateButton: paused, what you hear reads "Resume".
        XCTAssertTrue(app.cells.buttons["Resume"].waitForExistence(timeout: 3))

        // The row of the page you hear opens Now Playing; ⌄ closes it the same way.
        row.tap()
        XCTAssertTrue(from.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(waitFor(5) { row.isHittable }, "⌄ closes it too")
    }

    /// A sideways drag on Now Playing's scrubber scrubs; it never closes the sheet.
    func testScrubberDragInNowPlayingDoesNotClose() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedDemoArticle", "-uiTesting", "-openLibrary", "-selectEngine", "apple"]
        app.launch()
        let row = app.cells.staticTexts["Demo Listen Article"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        startPlayback(app)
        let play = app.buttons["listenPlayPause"]
        play.tap()
        XCTAssertTrue(waitFor(5) { play.label == "Play" }, "paused")
        let scrubber = app.descendants(matching: .any)["readerScrubber"]
        XCTAssertTrue(scrubber.waitForExistence(timeout: 5))
        wait(1.0) // sentence map built
        let before = scrubber.value as? String

        scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)))
        wait(0.8)
        XCTAssertTrue(app.descendants(matching: .any)["nowPlayingFrom"].exists, "still on Now Playing")
        XCTAssertFalse(row.isHittable, "the list didn't come back")
        XCTAssertNotEqual(scrubber.value as? String, before, "the drag scrubbed")
    }

    /// The back pill and the pull down close the Reader sheet; playback keeps going in the bar,
    /// and tapping the bar opens Now Playing.
    func testPullDownClosesTheReaderLikeItsBackPillAndTheBarOpensNowPlaying() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-browseTestPages", "-resetBookmarks", "-selectEngine", "apple"]
        app.launch()
        // Something playing: page three from its 🎧.
        let third = app.links["Third page"]
        XCTAssertTrue(third.waitForExistence(timeout: 10))
        third.tap()
        let listen = app.descendants(matching: .any)["addressListen"]
        XCTAssertTrue(listen.waitForExistence(timeout: 10))
        listen.tap()
        XCTAssertTrue(waitFor(8) { listen.label == "Pause" }, "playing")
        app.buttons["browseBack"].tap()
        let next = app.links["Next page"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        next.tap()
        let reader = app.descendants(matching: .any)["addressReader"]
        XCTAssertTrue(reader.waitForExistence(timeout: 10))
        reader.tap()

        let close = app.buttons["readerClose"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        XCTAssertEqual(close.label, "Back to Browser", "opened over the browser")

        // A sideways drag on the header does not close it either.
        let header = close.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: 140, dy: 0))
        header.press(forDuration: 0.05, thenDragTo: header.withOffset(CGVector(dx: 120, dy: 10)))
        wait(0.8)
        XCTAssertTrue(close.exists, "horizontal drag does not close the Reader")

        // Pull the header down → same as the back pill.
        pullDown(close)
        XCTAssertTrue(waitFor(5) { !close.exists }, "pull-down closed the Reader")
        XCTAssertTrue(app.textFields["addressField"].waitForExistence(timeout: 3), "back on the browser")

        // Audio keeps going: the bar shows it above the address field.
        let barPlay = app.buttons["nowPlayingBarPlayPause"]
        XCTAssertTrue(barPlay.waitForExistence(timeout: 5), "the bar after closing the Reader")
        XCTAssertTrue(waitFor(5) { barPlay.label == "Pause" }, "still playing")
        XCTAssertTrue(app.descendants(matching: .any)["nowPlayingBarOpen"].label.contains("Third page"))

        // Tap → Now Playing, no bar while it's on screen; ⌄ shrinks it back.
        app.descendants(matching: .any)["nowPlayingBarOpen"].tap()
        let from = app.descendants(matching: .any)["nowPlayingFrom"]
        XCTAssertTrue(from.waitForExistence(timeout: 5))
        XCTAssertFalse(barPlay.exists, "no bar on Now Playing")
        app.buttons["readerClose"].tap()
        XCTAssertTrue(barPlay.waitForExistence(timeout: 5))
        barPlay.tap()
        XCTAssertTrue(waitFor(5) { barPlay.label == "Resume" }, "the bar pauses")
    }
}
