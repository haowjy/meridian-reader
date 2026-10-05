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
        XCTAssertTrue(find(app, "nowPlayingFrom").waitForExistence(timeout: 5), "Now Playing")
        XCTAssertTrue(eventually(8) { app.buttons["listenPlayPause"].label == "Pause" }, "playing")
        XCTAssertFalse(find(app, "nowPlayingBar").exists)

        // 📄 on the playing page opens Now Playing, not a Reader.
        app.buttons["readerClose"].tap()
        XCTAssertTrue(eventually(5) { !self.find(app, "nowPlayingFrom").exists })
        XCTAssertTrue(find(app, "nowPlayingBarOpen").label.contains("Second page"))
        find(app, "addressReader").tap()
        XCTAssertTrue(find(app, "nowPlayingFrom").waitForExistence(timeout: 10), "the playing page opens as Now Playing")
        XCTAssertFalse(app.buttons["Back to Browser"].exists, "no Reader of the playing page")
        app.buttons["listenPlayPause"].tap()
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
