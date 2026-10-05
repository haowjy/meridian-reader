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
        XCTAssertEqual(find(app, "nowPlayingFrom").label, "Playing from Library", "a saved page plays from the Library")
        assertBackToAudioReturnsToTheSpokenParagraph(app)

        find(app, "nowPlayingFrom").tap()
        XCTAssertTrue(eventually(5) { !self.find(app, "nowPlayingFrom").exists }, "Now Playing closes")
        XCTAssertTrue(app.navigationBars["Saved"].waitForExistence(timeout: 5), "on the Library")
    }

    /// A plain-text article (no reading HTML) reads on the same page: it follows the audio, offers
    /// Back to audio, and Back to audio brings the spoken paragraph back.
    func testPlainTextArticleReadsTheSameWay() throws {
        let app = launchLongDemo(["-seedDemoPlainText"])
        openNowPlayingFromTheLibrary(app)
        XCTAssertTrue(paragraph(app, 0).waitForExistence(timeout: 5), "the paragraphs on the reading page")
        assertBackToAudioReturnsToTheSpokenParagraph(app)
    }

    /// The title card says what is playing (title, site or Library, time left) and scrolls with
    /// the text; the big round button plays and pauses.
    func testTheTitleCardShowsWhatIsPlayingAndScrollsWithTheText() throws {
        let app = launchLongDemo()
        openNowPlayingFromTheLibrary(app)
        let card = find(app, "nowPlayingTitleCard")
        XCTAssertTrue(card.waitForExistence(timeout: 5), "the title card")
        XCTAssertTrue(card.label.contains("Demo Listen Article"), card.label)
        XCTAssertTrue(card.label.contains("min left"), card.label)
        let play = app.buttons["listenPlayPause"]
        XCTAssertTrue(eventually(8) { play.label == "Pause" }, "playing")
        XCTAssertGreaterThanOrEqual(play.frame.width, 64, "the big round ⏸")
        play.tap()
        XCTAssertTrue(eventually(5) { play.label == "Play" }, "it pauses")

        let top = card.frame.minY
        dragText(app, by: -200)
        XCTAssertTrue(eventually(3) { !card.exists || card.frame.minY < top - 100 }, "it scrolls up with the text")
    }

    /// Listen in the Reader (D2): Now Playing opens with the text exactly where the Reader had it,
    /// though Now Playing's header is taller than the Reader's and the title card replaces the
    /// title. Within 1 pt: the two pages lay out the same text at the same width, the offset is
    /// set exactly, and what's left is rounding of the frames the accessibility tree reports.
    func testListenKeepsTheReadersScrollPosition() throws {
        assertListenKeepsTheLine(launchLongDemo())
    }

    /// The same at the largest text size, where the two headers differ the most.
    func testListenKeepsTheReadersScrollPositionAtTheLargestTextSize() throws {
        // A paragraph is over 1,000 pt tall there: the second one is far enough down.
        assertListenKeepsTheLine(launchLongDemo(Self.largestText), paragraph: 1)
    }

    /// The same for a plain-text article (no reading HTML: its paragraphs, on the same page).
    func testListenKeepsTheReadersScrollPositionForPlainText() throws {
        assertListenKeepsTheLine(launchLongDemo(["-seedDemoPlainText"]))
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

    private static let largestText = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]

    /// Scrolls the first line of paragraph `index` to the middle of the Reader, then Listen: in
    /// Now Playing that line is where it was on screen, to the point.
    private func assertListenKeepsTheLine(_ app: XCUIApplication, paragraph index: Int = 8,
                                          file: StaticString = #filePath, line: UInt = #line) {
        let row = app.cells.staticTexts["Demo Listen Article"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), file: file, line: line)
        row.tap()
        let listen = app.buttons["listenPlayPause"]
        XCTAssertTrue(listen.waitForExistence(timeout: 10), file: file, line: line)
        let target = paragraph(app, index)
        XCTAssertTrue(target.waitForExistence(timeout: 5), file: file, line: line)
        let middle = app.windows.firstMatch.frame.height * 0.4
        for _ in 0..<20 where !topIsInMiddle(app, target) {
            dragText(app, by: max(-300, min(300, middle - target.frame.minY)))
        }
        let name = "paragraph \(index + 1)"
        XCTAssertTrue(topIsInMiddle(app, target), "\(name) scrolled into the middle of the Reader", file: file, line: line)
        let before = settledTop(of: target)

        listen.tap() // plays paragraph 1; the text stays where it is
        XCTAssertTrue(find(app, "nowPlayingFrom").waitForExistence(timeout: 5), "Now Playing", file: file, line: line)
        let play = app.buttons["listenPlayPause"]
        XCTAssertTrue(eventually(8) { play.label == "Pause" }, file: file, line: line)
        play.tap() // paused on paragraph 1, so following has nothing new to move to
        XCTAssertTrue(eventually(5) { play.label == "Play" }, file: file, line: line)
        let after = paragraph(app, index)
        XCTAssertTrue(eventually(5) { after.exists && self.topIsInMiddle(app, after) },
                      "\(name) is still in view, not the top of the page: before \(before), after \(after.frame), "
                        + "first \(paragraph(app, 0).frame), web views \(app.webViews.count)", file: file, line: line)
        XCTAssertEqual(settledTop(of: after), before, accuracy: 1, "at the Reader's scroll position", file: file, line: line)
        XCTAssertFalse(isInMiddle(app, paragraph(app, 0)), "not scrolled to the spoken paragraph", file: file, line: line)
    }

    /// The element's first line is in the reading area: below the header, above the controls.
    private func topIsInMiddle(_ app: XCUIApplication, _ element: XCUIElement) -> Bool {
        guard element.exists else { return false }
        let window = app.windows.firstMatch.frame
        let y = element.frame.minY
        return y > window.minY + window.height * 0.25 && y < window.minY + window.height * 0.6
    }

    /// The element's top once it has stopped moving (a drag's deceleration, a sheet settling).
    private func settledTop(of element: XCUIElement) -> CGFloat {
        var last = element.frame.minY
        for _ in 0..<20 {
            idle(0.25)
            let now = element.frame.minY
            if abs(now - last) < 0.01 { return now }
            last = now
        }
        return last
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
