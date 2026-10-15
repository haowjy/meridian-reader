import XCTest

/// The Reader sheet: reading a page while another one plays. Its back pill names what is under it,
/// the Now Playing bar sits above its toolbar, Listen makes the page what you hear and turns it
/// into Now Playing, and the Reader of the playing page is Now Playing.
final class ReaderSheetUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testReaderOverTheBrowserWithAnotherPagePlaying() throws {
        let app = launchTestPages()
        openTestPage(app, "Third page")
        listenHere(app)
        backToPageOne(app)
        openTestPage(app, "Next page")

        find(app, "addressReader").tap()
        let back = app.buttons["readerClose"]
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        XCTAssertEqual(back.label, "Back to Browser")
        let listen = app.buttons["listenPlayPause"]
        XCTAssertTrue(listen.label.hasPrefix("Listen"), listen.label)
        XCTAssertFalse(app.buttons["listenSpeed"].exists, "no speed in the Reader")
        XCTAssertFalse(app.buttons["Previous paragraph"].exists, "no skips in the Reader")
        XCTAssertFalse(app.buttons["Next paragraph"].exists)

        let bar = find(app, "nowPlayingBar")
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "the bar shows what you hear")
        XCTAssertTrue(find(app, "nowPlayingBarOpen").label.contains("Third page"))
        XCTAssertLessThanOrEqual(bar.frame.maxY, listen.frame.minY, "above the Reader's toolbar")

        // Listen: this page is what you hear, and the Reader is now Now Playing.
        listen.tap()
        XCTAssertTrue(find(app, "nowPlayingHeader").waitForExistence(timeout: 5), "Now Playing")
        XCTAssertTrue(eventually(8) { app.buttons["listenPlayPause"].label == "Pause" }, "playing")
        XCTAssertFalse(find(app, "nowPlayingBar").exists)

        // 📄 on the playing page opens Now Playing, not a Reader.
        app.buttons["readerClose"].tap()
        XCTAssertTrue(eventually(5) { !self.find(app, "nowPlayingHeader").exists })
        XCTAssertTrue(find(app, "nowPlayingBarOpen").label.contains("Second page"))
        find(app, "addressReader").tap()
        XCTAssertTrue(find(app, "nowPlayingHeader").waitForExistence(timeout: 10), "the playing page opens as Now Playing")
        XCTAssertFalse(app.buttons["Back to Browser"].exists, "no Reader of the playing page")
        app.buttons["listenPlayPause"].tap()
    }

    /// A plain-text article (no reading HTML) reads on the same HTML reading page in the Reader.
    /// With ☝︎ on its paragraphs are buttons, "Paragraph N", and one plays from that paragraph.
    func testPlainTextReaderReadsOnTheReadingPageAndJumpsByParagraph() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-seedDemoArticle", "-seedDemoPlainText", "-openLibrary",
                               "-selectEngine", "apple"]
        app.launch()
        let row = app.cells.staticTexts["Demo Listen Article"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.buttons["readerClose"].waitForExistence(timeout: 5), "the Reader")
        let second = app.webViews.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Second paragraph'")).firstMatch
        XCTAssertTrue(second.waitForExistence(timeout: 5), "the paragraphs are on the reading page")
        XCTAssertFalse(app.descendants(matching: .any)["listenParagraph-0"].exists, "not a native paragraph list")
        XCTAssertFalse(app.webViews.buttons["Paragraph 2"].exists, "reading: text, not buttons")

        app.buttons["listenJump"].tap()
        let jump = app.webViews.buttons["Paragraph 2"]
        XCTAssertTrue(jump.waitForExistence(timeout: 3), "☝︎: each paragraph is a button")
        XCTAssertTrue(app.webViews.buttons["Paragraph 1"].exists)
        app.buttons["listenJumpCancel"].tap()
        XCTAssertTrue(eventually(3) { !jump.exists && second.exists }, "☝︎ off: text again")
        let hint = app.descendants(matching: .any)["listenJumpHint"]
        XCTAssertTrue(eventually(3) { !hint.exists }, "the hint has gone")
        // A ☝︎ tap during the hint's exit (~0.4 s after Cancel) is lost on the Simulator; let it settle.
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))

        app.buttons["listenJump"].tap()
        XCTAssertTrue(eventually(3) { app.buttons["listenJump"].label == "Cancel listen from a paragraph" }, "☝︎ on")
        XCTAssertTrue(jump.waitForExistence(timeout: 3))
        jump.tap()
        XCTAssertTrue(find(app, "nowPlayingHeader").waitForExistence(timeout: 5), "listening turns it into Now Playing")
        let play = app.buttons["listenPlayPause"]
        XCTAssertTrue(eventually(8) { play.label == "Pause" }, "playing")
        play.tap()
        XCTAssertTrue(eventually(5) { play.label == "Play" })
        XCTAssertTrue(eventually(3) { (self.find(app, "readerScrubOffset").value as? String)?.hasPrefix("p=1 ") == true },
                      "from paragraph 2: \(find(app, "readerScrubOffset").value ?? "")")
    }

    func testReaderOverTheLibrary() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-seedDemoArticle", "-openLibrary", "-selectEngine", "apple"]
        app.launch()
        let row = app.cells.staticTexts["Demo Listen Article"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let back = app.buttons["readerClose"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertEqual(back.label, "Back to Library")
        back.tap()
        XCTAssertTrue(eventually(5) { !back.exists })
        XCTAssertTrue(eventually(3) { row.isHittable }, "back on the Library list once the sheet has gone")
    }
}
