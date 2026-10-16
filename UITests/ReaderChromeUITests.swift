import XCTest

/// Reader sheet chrome (docs/NAVIGATION.md): like the browser's search bar / toolbar, its header
/// (grabber, back pill) and its bottom row (the Now Playing bar, 🔖, Listen, ⋯) never hide — not
/// on scroll, not on a tap — and there is no progress line. The text sits between them, so its
/// first and last lines clear both. A pull down on the header closes it, like the back pill.
final class ReaderChromeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
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
        idle(0.8)
    }

    /// A short finger scroll back up (not all the way to the top).
    private func scrollUpALittle(_ app: XCUIApplication) {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: 90)),
                   withVelocity: .slow, thenHoldForDuration: 0.1)
        idle(0.8)
    }

    private func tapText(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        idle(0.8)
    }

    /// Several fast flicks up: the end of the 40-paragraph article.
    private func scrollToEnd(_ app: XCUIApplication) {
        for _ in 0..<12 { app.swipeUp(velocity: .fast) }
        idle(2)
    }

    /// Visible article paragraphs (web static texts of the demo's "Extra paragraph N").
    private func paragraphFrames(_ app: XCUIApplication) -> [CGRect] {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Extra paragraph'"))
            .allElementsBoundByIndex.map(\.frame).filter { !$0.isEmpty }
    }

    func testBrowseReaderChromeStaysPutWhileScrollingAndTapping() throws {
        let app = launch(["-seedDemoArticle", "-seedDemoParagraphs", "40", "-openDemoInBrowseReader"])
        let close = app.buttons["readerClose"]
        let listen = app.buttons["listenPlayPause"]
        let more = app.buttons["readerMore"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        waitForLongDemoText(app)
        let closeFrame = close.frame, listenFrame = listen.frame

        // Scrolling down: nothing moves or hides, no progress line.
        scrollDown(app)
        scrollDown(app)
        idle(0.8)
        XCTAssertTrue(shown(app, close) && shown(app, listen), "bars stay while scrolling down")
        XCTAssertEqual(close.frame, closeFrame, "header didn't move")
        XCTAssertEqual(listen.frame, listenFrame, "bottom row didn't move")
        XCTAssertFalse(find(app, "readerProgressLine").exists, "no progress line")

        // A tap on the text doesn't toggle anything.
        tapText(app)
        XCTAssertTrue(shown(app, close) && shown(app, listen), "tap on the text leaves the bars")
        tapText(app)
        XCTAssertTrue(shown(app, close) && shown(app, listen))

        // Scrolled to the end, the last line sits above the bottom row.
        scrollToEnd(app)
        XCTAssertEqual(listen.frame, listenFrame, "still in place at the end")
        let lastBottom = paragraphFrames(app).map(\.maxY).max() ?? 0
        let barTop = listen.frame.minY - 8 // band top padding
        XCTAssertGreaterThan(lastBottom, barTop - 250, "the last paragraph is on screen")
        XCTAssertLessThanOrEqual(lastBottom, barTop, "the last line clears the bottom row")

        // ⋯ menu open / closed keeps the Reader.
        touch(more)
        XCTAssertTrue(find(app, "moreMenuPanel").waitForExistence(timeout: 3))
        closeMenu(app)
        XCTAssertTrue(shown(app, close))

        // ☝︎ then a tap on the text: that paragraph plays, and the Reader is now Now Playing.
        touch(app.buttons["listenJump"])
        XCTAssertTrue(find(app, "listenJumpHint").waitForExistence(timeout: 3))
        tapText(app)
        XCTAssertTrue(find(app, "nowPlayingHeader").waitForExistence(timeout: 5), "listening turns it into Now Playing")
        let play = app.buttons["listenPlayPause"]
        XCTAssertTrue(eventually(8) { play.label == "Pause" }, "jump tap started playback")
        touch(play)
        touch(app.buttons["nowPlayingClose"])
        XCTAssertTrue(eventually(3) { !find(app, "nowPlayingHeader").exists }, "the close pill closes Now Playing")
        XCTAssertFalse(app.buttons["Back to Browser"].exists, "the Reader turned into Now Playing; none is left")
    }

    func testBrowseReaderFirstLineClearsTheHeader() throws {
        let app = launch(["-seedDemoArticle", "-seedDemoParagraphs", "40", "-openDemoInBrowseReader"])
        let close = app.buttons["readerClose"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        waitForLongDemoText(app)
        XCTAssertNotNil(settledFrames([close]), "the sheet has risen")
        let texts = app.webViews.staticTexts.allElementsBoundByIndex.map(\.frame).filter { !$0.isEmpty && $0.maxY > 0 }
        let firstTop = texts.map(\.minY).min() ?? 0
        XCTAssertGreaterThanOrEqual(firstTop, close.frame.maxY, "first line starts below the back pill")
    }

    /// With another page playing, the Now Playing bar sits above the Reader's bottom row, and the
    /// text's last line clears the bar too.
    func testLastLineClearsAnotherPagesBar() throws {
        let app = launchTestPages(["-seedDemoArticle", "-seedDemoParagraphs", "40"])
        openTestPage(app, "Next page")
        listenHere(app)
        find(app, "addressListen").tap() // paused: the bar stays, quietly
        XCTAssertTrue(eventually(5) { self.find(app, "addressListen").label != "Pause" })

        app.buttons["browseLibrary"].tap()
        let row = app.cells.staticTexts["Demo Listen Article"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.buttons["readerClose"].waitForExistence(timeout: 5))
        let bar = find(app, "nowPlayingBar")
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "the other page's bar over the Reader's bottom row")
        let listen = app.buttons["listenPlayPause"]
        XCTAssertLessThan(bar.frame.maxY, listen.frame.minY, "the bar is above the bottom row")
        waitForLongDemoText(app)

        scrollToEnd(app)
        let lastBottom = paragraphFrames(app).map(\.maxY).max() ?? 0
        XCTAssertGreaterThan(lastBottom, bar.frame.minY - 250, "the last paragraph is on screen")
        XCTAssertLessThanOrEqual(lastBottom, bar.frame.minY, "the last line clears the bar")
    }

    func testLibraryReaderChromeStaysAndPullDownCloses() throws {
        let app = launchLongDemo()

        let row = app.cells.staticTexts["Demo Listen Article"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let close = app.buttons["readerClose"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertEqual(close.label, "Back to Library")
        waitForLongDemoText(app)

        scrollDown(app)
        idle(0.8)
        XCTAssertTrue(shown(app, close) && shown(app, app.buttons["listenPlayPause"]), "bars stay")
        XCTAssertFalse(find(app, "readerProgressLine").exists)

        // A pull down on the header closes it, like the back pill.
        let start = close.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: 140, dy: 0))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 420)),
                    withVelocity: .default, thenHoldForDuration: 0)
        XCTAssertTrue(eventually(5) { !close.exists }, "pulled down")
        XCTAssertTrue(eventually(5) { row.isHittable }, "back on the Saved list")
    }
}
