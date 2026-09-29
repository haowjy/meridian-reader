import XCTest

/// Reader chrome (Nav H, docs/NAVIGATION.md): like the browser's search bar / toolbar, the top row
/// and the bottom controls never hide — not on scroll, not on a tap — and there is no progress
/// line. The text is inset so its first and last lines clear the bars. ‹ swipe-back still pops.
final class ReaderChromeUITests: XCTestCase {
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

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// The bar control is on screen (not slid off the top / bottom edge). Frame-based on purpose:
    /// with the article full-bleed, `isHittable` asks accessibility what's at the button's center,
    /// and the web view's paragraph elements scrolled underneath can answer first (SwiftUI checks
    /// the platform view before its own overlay), so it flips with the scroll position even though
    /// a real touch lands on the button. `touch` checks that part with a real touch.
    private func shown(_ app: XCUIApplication, _ e: XCUIElement) -> Bool {
        guard e.exists else { return false }
        let f = e.frame, w = app.windows.firstMatch.frame
        return !f.isEmpty && f.minY >= w.minY && f.maxY <= w.maxY
    }

    /// A real touch at the control's center (not via the accessibility hit test).
    private func touch(_ e: XCUIElement) {
        e.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// A finger scroll down the article (content moves up).
    private func scrollDown(_ app: XCUIApplication) {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -260)),
                   withVelocity: .slow, thenHoldForDuration: 0.1)
        wait(0.8)
    }

    /// A short finger scroll back up (not all the way to the top).
    private func scrollUpALittle(_ app: XCUIApplication) {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: 90)),
                   withVelocity: .slow, thenHoldForDuration: 0.1)
        wait(0.8)
    }

    /// The long (40-paragraph) article's web content is laid out, so a drag really scrolls it.
    @discardableResult
    private func waitForArticleText(_ app: XCUIApplication, timeout: TimeInterval = 15, require: Bool = true) -> Bool {
        let text = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Extra paragraph 12'")).firstMatch
        let found = text.waitForExistence(timeout: timeout)
        if require { XCTAssertTrue(found, "article text loaded") }
        wait(0.5)
        return found
    }

    private func tapText(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        wait(0.8)
    }

    /// Several fast flicks up: the end of the 40-paragraph article.
    private func scrollToEnd(_ app: XCUIApplication) {
        for _ in 0..<12 { app.swipeUp(velocity: .fast) }
        wait(2)
    }

    /// Visible article paragraphs (web static texts of the demo's "Extra paragraph N").
    private func paragraphFrames(_ app: XCUIApplication) -> [CGRect] {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Extra paragraph'"))
            .allElementsBoundByIndex.map(\.frame).filter { !$0.isEmpty }
    }

    func testBrowseReaderChromeStaysPutWhileScrollingAndTapping() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedDemoArticle", "-seedDemoParagraphs", "40", "-openDemoInBrowseReader",
                               "-uiTesting", "-selectEngine", "apple"]
        app.launch()
        // `-openDemoInBrowseReader` can race the re-seed and open the previous run's short demo
        // row; a second launch always opens the long one.
        XCTAssertTrue(app.buttons["readerClose"].waitForExistence(timeout: 10))
        if !waitForArticleText(app, timeout: 6, require: false) {
            app.terminate()
            app.launch()
        }

        let close = app.buttons["readerClose"]
        let play = app.buttons["listenPlayPause"]
        let scrubber = el(app, "readerScrubber")
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        waitForArticleText(app)
        let closeFrame = close.frame, playFrame = play.frame

        // Scrolling down: nothing moves or hides, no progress line.
        scrollDown(app)
        scrollDown(app)
        wait(0.8)
        XCTAssertTrue(shown(app, close) && shown(app, play), "bars stay while scrolling down")
        XCTAssertEqual(close.frame, closeFrame, "top row didn't move")
        XCTAssertEqual(play.frame, playFrame, "listen row didn't move")
        XCTAssertFalse(el(app, "readerProgressLine").exists, "no progress line")

        // A tap on the text doesn't toggle anything.
        tapText(app)
        XCTAssertTrue(shown(app, close) && shown(app, play), "tap on the text leaves the bars")
        tapText(app)
        XCTAssertTrue(shown(app, close) && shown(app, play))

        // Scrolled to the end, the last line sits above the bottom controls.
        scrollToEnd(app)
        XCTAssertEqual(play.frame, playFrame, "still in place at the end")
        let lastBottom = paragraphFrames(app).map(\.maxY).max() ?? 0
        let barTop = scrubber.frame.minY - 4 - 8 // capsule padding + band top padding
        XCTAssertGreaterThan(lastBottom, barTop - 250, "the last paragraph is on screen")
        XCTAssertLessThanOrEqual(lastBottom, barTop, "the last line clears the bottom bar")

        // The bars really take touches: play, pause.
        touch(play)
        XCTAssertTrue(waitFor(5) { play.label == "Pause" }, "play")
        touch(play)
        XCTAssertTrue(waitFor(5) { play.label == "Play" }, "pause")

        // Jump mode: the tap picks a paragraph (starts playback).
        touch(app.buttons["listenJump"])
        XCTAssertTrue(el(app, "listenJumpHint").waitForExistence(timeout: 3))
        tapText(app)
        XCTAssertTrue(waitFor(8) { play.label == "Pause" }, "jump tap started playback")
        touch(play)

        // ⋯ menu open / closed keeps the reader; ✕ closes it.
        touch(app.buttons["readerMore"])
        XCTAssertTrue(el(app, "moreMenuPanel").waitForExistence(timeout: 3))
        el(app, "moreMenuDismiss").tap()
        XCTAssertTrue(waitFor(3) { !el(app, "moreMenuPanel").exists })
        XCTAssertTrue(shown(app, close))
        touch(close)
        XCTAssertTrue(waitFor(3) { !close.exists }, "✕ closes the reader")
    }

    func testBrowseReaderFirstLineClearsTopRow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedDemoArticle", "-seedDemoParagraphs", "40", "-openDemoInBrowseReader",
                               "-uiTesting", "-selectEngine", "apple"]
        app.launch()
        let close = app.buttons["readerClose"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        wait(2)
        let texts = app.webViews.staticTexts.allElementsBoundByIndex.map(\.frame).filter { !$0.isEmpty && $0.maxY > 0 }
        let firstTop = texts.map(\.minY).min() ?? 0
        XCTAssertGreaterThanOrEqual(firstTop, close.frame.maxY, "first line starts below the top row")
    }

    func testLibraryReaderChromeStaysAndSwipeBackStillPops() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedDemoArticle", "-seedDemoParagraphs", "40", "-openLibrary",
                               "-uiTesting", "-selectEngine", "apple"]
        app.launch()

        let row = app.cells.staticTexts["Demo Listen Article"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let close = app.buttons["readerClose"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertEqual(close.label, "Back")
        waitForArticleText(app)

        scrollDown(app)
        wait(0.8)
        XCTAssertTrue(shown(app, close) && shown(app, app.buttons["listenPlayPause"]), "bars stay")
        XCTAssertFalse(el(app, "readerProgressLine").exists)

        // Edge swipe-back pops. (A synthesized x≈2 edge drag is occasionally not recognised on the
        // Simulator — the known SwipeBackUITests flake — so it gets one more try.)
        func edgeSwipe() {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 2, dy: 0))
            start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)),
                        withVelocity: .default, thenHoldForDuration: 0.05)
        }
        edgeSwipe()
        if !waitFor(4, { row.isHittable }) { edgeSwipe() }
        XCTAssertTrue(waitFor(5) { row.isHittable }, "swipe-back popped to the Saved list")
    }
}
