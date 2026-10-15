import XCTest

/// A sheet pulls down from its text too (docs/NAVIGATION.md): a drag that begins with the text at
/// its top and goes down moves the sheet, and released far enough it closes like the back pill or
/// ⌄. A drag that begins mid-article only scrolls, even once the text reaches its top.
final class SheetPullFromTextUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launchLongDemo() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-seedDemoArticle", "-seedDemoParagraphs", "40", "-openLibrary",
                               "-selectEngine", "apple", "-reader.rateMultiplier", "1"]
        app.launch()
        return app
    }

    /// A slow finger drag on the text, from 45% of the way down the screen, held before lifting
    /// (no fling).
    private func dragText(_ app: XCUIApplication, by dy: CGFloat) {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: dy)),
                   withVelocity: .slow, thenHoldForDuration: 0.2)
        idle(1)
    }

    private func waitForArticleText(_ app: XCUIApplication) {
        let text = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Extra paragraph 12'")).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 15), "article text loaded")
        idle(0.5)
    }

    func testPullingTheReadersTextDownFromItsTopClosesItButNotFromMidArticle() throws {
        let app = launchLongDemo()
        let row = app.cells.staticTexts["Demo Listen Article"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let close = app.buttons["readerClose"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        waitForArticleText(app)
        let resting = close.frame

        // Mid-article: scroll in, then drag back down further than that. The text reaches its
        // top and bounces; the sheet stays.
        dragText(app, by: -260)
        dragText(app, by: 420)
        XCTAssertTrue(close.exists, "a drag that began mid-article doesn't close the Reader")
        XCTAssertEqual(close.frame.minY, resting.minY, accuracy: 1, "the sheet is back at rest")

        // At the top: a short pull springs back.
        dragText(app, by: 50)
        XCTAssertTrue(close.exists, "a short pull springs back")
        XCTAssertEqual(close.frame.minY, resting.minY, accuracy: 1, "the sheet is back at rest")

        // At the top: a long pull closes it, like the back pill.
        dragText(app, by: 300)
        XCTAssertTrue(eventually(5) { !close.exists }, "the pull from the text closed the Reader")
        XCTAssertTrue(eventually(5) { row.isHittable }, "back on the Library")
    }

    func testPullingNowPlayingsTextDownFromItsTopShrinksItIntoTheBar() throws {
        let app = launchLongDemo()
        let row = app.cells.staticTexts["Demo Listen Article"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let listen = app.buttons["listenPlayPause"]
        XCTAssertTrue(listen.waitForExistence(timeout: 10))
        XCTAssertTrue(eventually(10) { listen.isEnabled }, "listen document ready")
        listen.tap()
        let from = find(app, "nowPlayingHeader")
        XCTAssertTrue(from.waitForExistence(timeout: 5), "Listen turns the Reader into Now Playing")
        XCTAssertTrue(eventually(8) { listen.label == "Pause" }, "playing")
        waitForArticleText(app)

        // A short pull from the top springs back and leaves it following the audio.
        dragText(app, by: 50)
        XCTAssertTrue(from.exists, "a short pull springs back")
        XCTAssertFalse(find(app, "nowPlayingJumpToAudio").exists, "a pull alone doesn't stop following")

        dragText(app, by: 300)
        XCTAssertTrue(eventually(5) { !from.exists }, "the pull from the text shrank Now Playing")
        let barPlay = app.buttons["nowPlayingBarPlayPause"]
        XCTAssertTrue(barPlay.waitForExistence(timeout: 5), "into the bar")
        XCTAssertEqual(barPlay.label, "Pause", "still playing")
    }
}
