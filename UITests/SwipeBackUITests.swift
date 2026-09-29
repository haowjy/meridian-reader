import XCTest

/// Navigation rule (docs/NAVIGATION.md): ‹ screens pop with a left-edge swipe, ✕ screens close
/// with a pull-down. Both must behave exactly like tapping the button.
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

    func testEdgeSwipeBackFromSavedReaderReturnsToSavedAndKeepsPlaying() throws {
        let app = XCUIApplication()
        // The library sheet (‹ reader pushes inside it).
        app.launchArguments = ["-seedDemoArticle", "-uiTesting", "-openLibrary"]
        app.launch()

        let row = app.cells.staticTexts["Demo Listen Article"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))

        // Root screen: an edge swipe does nothing and must not wedge the navigation stack.
        edgeSwipe(app)
        XCTAssertTrue(row.isHittable, "still on the Saved list")

        row.tap()
        let close = app.buttons["readerClose"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertEqual(close.label, "Back", "Saved reader shows ‹")
        startPlayback(app)

        edgeSwipe(app)
        XCTAssertTrue(waitFor(5) { !close.exists }, "reader popped")
        XCTAssertTrue(waitFor(5) { row.isHittable }, "Saved list is showing again")
        XCTAssertTrue(app.navigationBars["Saved"].exists, "Saved navigation bar is back")

        // Same as tapping ‹: playback keeps going (the row button shows Pause).
        let rowPause = app.cells.buttons["Pause"]
        XCTAssertTrue(rowPause.waitForExistence(timeout: 3), "audio kept playing after swipe-back")
        rowPause.tap()
        XCTAssertTrue(app.cells.buttons["Play"].waitForExistence(timeout: 3))

        // Stack still healthy: reopen, then the ‹ button still works.
        row.tap()
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(waitFor(5) { row.isHittable }, "‹ tap still pops")
    }

    /// ✕ / pull-down hide the browser's reader; playback keeps going in the mini player, and
    /// tapping the mini player reopens the reader.
    func testPullDownClosesBrowseReaderLikeXAndMiniPlayerReopens() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedDemoArticle", "-openDemoInBrowseReader", "-uiTesting"]
        app.launch()

        let close = app.buttons["readerClose"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertEqual(close.label, "Hide Reader", "Browse reader shows ✕")
        startPlayback(app)

        // Scrolling the article (even downward at the top) must never close the reader.
        let body = app.webViews.firstMatch
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        body.swipeDown()
        wait(0.8)
        XCTAssertTrue(close.exists, "article scroll does not close the reader")
        // A sideways drag on the top bar does not close it either.
        let title = app.staticTexts["readerTitle"]
        XCTAssertTrue(title.exists)
        let titleCenter = title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        titleCenter.press(forDuration: 0.05, thenDragTo: titleCenter.withOffset(CGVector(dx: 120, dy: 10)))
        wait(0.8)
        XCTAssertTrue(close.exists, "horizontal drag does not close the reader")

        // Pull the top bar down → same as ✕.
        titleCenter.press(forDuration: 0.05, thenDragTo: titleCenter.withOffset(CGVector(dx: 0, dy: 320)),
                          withVelocity: .default, thenHoldForDuration: 0)
        XCTAssertTrue(waitFor(5) { !close.exists }, "pull-down closed the reader")
        XCTAssertTrue(app.textFields["addressField"].waitForExistence(timeout: 3), "back on the browser")

        // Audio keeps going: the mini player shows it above the toolbar.
        let mini = app.descendants(matching: .any)["miniPlayer"]
        XCTAssertTrue(mini.waitForExistence(timeout: 5), "mini player after closing the reader")
        let miniPlay = app.buttons["miniPlayerPlayPause"]
        XCTAssertTrue(waitFor(5) { miniPlay.label == "Pause" }, "still playing")
        XCTAssertEqual(app.staticTexts["miniPlayerTitle"].label, "Demo Listen Article")

        // Tap → the reader is back (✕), mini player gone while it's on screen.
        app.descendants(matching: .any)["miniPlayerOpen"].tap()
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertFalse(mini.exists, "no mini player while the reader is on screen")

        // ✕ does the same as the pull-down.
        close.tap()
        XCTAssertTrue(mini.waitForExistence(timeout: 5))
        miniPlay.tap()
        XCTAssertTrue(waitFor(5) { miniPlay.label == "Play" }, "mini player pauses")
    }
}
