import XCTest

/// Now Playing: the bar opens it over every surface; ⌄ and the pull down shrink it back to the
/// same screen. Its header names where it plays from, its text follows the audio until you scroll,
/// and at the end it stays with ▶.
final class NowPlayingUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testOpensOverTheBrowserAndPullsBackDown() throws {
        let app = launchTestPages()
        openTestPage(app, "Next page")
        listenHere(app)

        find(app, "nowPlayingBarOpen").tap()
        let from = find(app, "nowPlayingFrom")
        XCTAssertTrue(from.waitForExistence(timeout: 5), "Now Playing")
        XCTAssertEqual(from.label, "Playing from pages", "the header names the site")
        XCTAssertFalse(find(app, "nowPlayingBar").exists, "no bar on Now Playing")

        pullDown(app, from: "nowPlayingFrom")
        XCTAssertTrue(eventually(5) { !from.exists }, "the pull down shrinks it")
        XCTAssertTrue(find(app, "nowPlayingBar").waitForExistence(timeout: 5), "back into the bar")
        XCTAssertTrue(app.textFields["addressField"].exists, "on the browser, as it was")
        XCTAssertTrue(app.staticTexts["Second page"].exists, "same page")

        find(app, "nowPlayingBarOpen").tap()
        XCTAssertTrue(from.waitForExistence(timeout: 5))
        app.buttons["readerClose"].tap() // ⌄
        XCTAssertTrue(eventually(5) { !from.exists }, "⌄ shrinks it")
        find(app, "nowPlayingBarPlayPause").tap()
    }

    func testOpensOverTheLibraryAndOverAReader() throws {
        let app = launchTestPages(["-seedDemoArticle"])
        openTestPage(app, "Next page")
        listenHere(app)

        // Over a Reader sheet of another page.
        backToPageOne(app)
        openTestPage(app, "Third page")
        find(app, "addressReader").tap()
        let back = app.buttons["readerClose"]
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        XCTAssertEqual(back.label, "Back to Browser")
        find(app, "nowPlayingBarOpen").tap()
        XCTAssertTrue(find(app, "nowPlayingFrom").waitForExistence(timeout: 5))
        // The Reader stays under Now Playing (and in the UI-test tree), so ⌄ by its label.
        app.buttons["Close Now Playing"].tap()
        XCTAssertTrue(eventually(5) { !self.find(app, "nowPlayingFrom").exists })
        XCTAssertEqual(app.buttons["readerClose"].label, "Back to Browser", "the Reader is still there")
        app.buttons["readerClose"].tap()
        XCTAssertTrue(eventually(5) { !app.buttons["readerClose"].exists })

        // Over the Library, which stays as it was.
        app.buttons["browseLibrary"].tap()
        XCTAssertTrue(app.navigationBars["Saved"].waitForExistence(timeout: 5))
        let bar = find(app, "nowPlayingBarOpen")
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "the bar shows on the Library")
        bar.tap()
        XCTAssertTrue(find(app, "nowPlayingFrom").waitForExistence(timeout: 5))
        pullDown(app, from: "nowPlayingFrom")
        XCTAssertTrue(eventually(5) { !self.find(app, "nowPlayingFrom").exists })
        XCTAssertTrue(app.navigationBars["Saved"].exists, "back on the Library")
        XCTAssertTrue(app.cells.staticTexts["Demo Listen Article"].exists, "its list as it was")
        find(app, "nowPlayingBarPlayPause").tap()
    }

    func testScrollingAwayOffersBackToAudio() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-seedDemoArticle", "-seedDemoParagraphs", "40", "-openLibrary",
                               "-selectEngine", "apple", "-reader.rateMultiplier", "1"]
        app.launch()
        let row = app.cells.staticTexts["Demo Listen Article"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let listen = app.buttons["listenPlayPause"]
        XCTAssertTrue(listen.waitForExistence(timeout: 10))
        listen.tap()
        XCTAssertTrue(find(app, "nowPlayingFrom").waitForExistence(timeout: 5), "Listen turns the Reader into Now Playing")
        XCTAssertEqual(find(app, "nowPlayingFrom").label, "Playing from example.com")

        let back = find(app, "nowPlayingBackToAudio")
        XCTAssertFalse(back.exists, "following the audio")
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -260)),
                   withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertTrue(back.waitForExistence(timeout: 3), "scrolling away offers Back to audio")
        back.tap()
        XCTAssertTrue(eventually(3) { !back.exists }, "tapping it follows the audio again")
        app.buttons["listenPlayPause"].tap()
    }

    func testAtTheEndNowPlayingStaysWithPlay() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-seedDemoArticle", "-openLibrary", "-selectEngine", "apple",
                               "-reader.rateMultiplier", "2"]
        app.launch()
        let row = app.cells.staticTexts["Demo Listen Article"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let play = app.buttons["listenPlayPause"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        play.tap()
        XCTAssertTrue(find(app, "nowPlayingFrom").waitForExistence(timeout: 5))
        // The last paragraph, then let it finish.
        app.buttons["Next paragraph"].tap()
        app.buttons["Next paragraph"].tap()
        let finished = find(app, "nowPlayingFinished")
        XCTAssertTrue(finished.waitForExistence(timeout: 45), "✓ Finished")
        XCTAssertTrue(find(app, "nowPlayingFrom").exists, "Now Playing stays on the page")
        XCTAssertEqual(play.label, "Play", "with ▶")

        app.buttons["readerClose"].tap()
        let bar = find(app, "nowPlayingBarOpen")
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "the bar stays after the end")
        XCTAssertTrue(bar.label.contains("Finished"), bar.label)
        find(app, "nowPlayingBarPlayPause").tap()
        XCTAssertTrue(eventually(5) { self.find(app, "nowPlayingBarPlayPause").label == "Pause" }, "▶ plays it again")
        find(app, "nowPlayingBarPlayPause").tap()
    }
}
