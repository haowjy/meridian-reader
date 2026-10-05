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
        XCTAssertTrue(find(app, "nowPlayingBar").waitForExistence(timeout: 5), "back on the browser, with its bar")

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
        let app = launchLongDemo()
        openNowPlayingFromTheLibrary(app)
        XCTAssertEqual(find(app, "nowPlayingFrom").label, "Playing from example.com")
        assertBackToAudioReturnsToTheSpokenParagraph(app)
    }

    /// A plain-text article (no reading HTML) reads on the same page: it follows the audio, offers
    /// Back to audio, and Back to audio brings the spoken paragraph back.
    func testPlainTextArticleReadsTheSameWay() throws {
        let app = launchLongDemo(["-seedDemoPlainText"])
        openNowPlayingFromTheLibrary(app)
        XCTAssertTrue(paragraph(app, 0).waitForExistence(timeout: 5), "the paragraphs on the reading page")
        assertBackToAudioReturnsToTheSpokenParagraph(app)
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

    // MARK: - Helpers

    /// The demo article, 40 paragraphs long, in the Library, Apple voice at 1×.
    private func launchLongDemo(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-seedDemoArticle", "-seedDemoParagraphs", "40", "-openLibrary",
                               "-selectEngine", "apple", "-reader.rateMultiplier", "1"] + extra
        app.launch()
        return app
    }

    private func openNowPlayingFromTheLibrary(_ app: XCUIApplication) {
        let row = app.cells.staticTexts["Demo Listen Article"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let listen = app.buttons["listenPlayPause"]
        XCTAssertTrue(listen.waitForExistence(timeout: 10))
        listen.tap()
        XCTAssertTrue(find(app, "nowPlayingFrom").waitForExistence(timeout: 5), "Listen turns the Reader into Now Playing")
    }

    /// Skips to paragraph 7 and pauses there, scrolls it away, then Back to audio: paragraph 7 is
    /// back in the middle of the text.
    private func assertBackToAudioReturnsToTheSpokenParagraph(_ app: XCUIApplication) {
        let back = find(app, "nowPlayingBackToAudio")
        XCTAssertFalse(back.exists, "following the audio")
        let play = app.buttons["listenPlayPause"]
        XCTAssertTrue(eventually(8) { play.label == "Pause" }, "playing")
        for _ in 0..<6 { app.buttons["Next paragraph"].tap() }
        play.tap()
        XCTAssertTrue(eventually(5) { play.label == "Play" }, "paused")
        XCTAssertTrue(eventually(3) { (self.find(app, "readerScrubOffset").value as? String)?.hasPrefix("p=6 ") == true },
                      "paused on paragraph 7: \(find(app, "readerScrubOffset").value ?? "")")
        let spoken = paragraph(app, 6)
        XCTAssertTrue(eventually(5) { spoken.exists && self.isInMiddle(app, spoken) }, "following: paragraph 7 in view")

        for _ in 0..<3 { dragText(app, by: -260) }
        XCTAssertTrue(back.waitForExistence(timeout: 3), "scrolling away offers Back to audio")
        XCTAssertFalse(isOnScreen(app, spoken), "paragraph 7 scrolled out of view")

        back.tap()
        XCTAssertTrue(eventually(3) { !back.exists }, "following again")
        XCTAssertTrue(eventually(3) { self.isInMiddle(app, spoken) }, "Back to audio brings paragraph 7 into view")
    }

    /// Paragraph `index` of the demo article on the reading page.
    private func paragraph(_ app: XCUIApplication, _ index: Int) -> XCUIElement {
        let opening = ["First paragraph", "Second paragraph", "Third paragraph"]
        let prefix = index < opening.count ? opening[index] : "Extra paragraph \(index + 1) "
        return app.webViews.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    private func isOnScreen(_ app: XCUIApplication, _ element: XCUIElement) -> Bool {
        element.exists && app.windows.firstMatch.frame.intersects(element.frame)
    }

    /// In the reading area: below the header, above the controls.
    private func isInMiddle(_ app: XCUIApplication, _ element: XCUIElement) -> Bool {
        guard element.exists else { return false }
        let window = app.windows.firstMatch.frame
        let y = element.frame.midY
        return y > window.minY + window.height * 0.15 && y < window.minY + window.height * 0.7
    }

    private func dragText(_ app: XCUIApplication, by dy: CGFloat) {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: dy)),
                   withVelocity: .slow, thenHoldForDuration: 0.1)
    }
}
