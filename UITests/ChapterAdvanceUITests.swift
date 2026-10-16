import XCTest

/// A book carries on from chapter to chapter (`-seedDemoBook -chainDemoChapters`: the demo book
/// plays from chapter 1 at launch; Apple voice, offline). Now Playing follows it into the next
/// chapter, and a Reader opened on an earlier chapter stays on that chapter. A folder you made
/// plays the same way, page to page in its order, from its row's ▶.
final class ChapterAdvanceUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testNowPlayingFollowsTheBookIntoItsNextChapterAndAReaderStaysOnItsOwn() throws {
        let app = launch(UITestSetup(["-browseTestPages", "-seedDemoBook", "-chainDemoChapters"], rate: 2))

        let bar = find(app, "nowPlayingBarOpen")
        XCTAssertTrue(bar.waitForExistence(timeout: 15), "the demo book plays at launch")
        XCTAssertTrue(bar.label.contains("Chapter 1: The Harbor"), "the title page is skipped: \(bar.label)")
        bar.tap()
        let card = find(app, "nowPlayingTitleCard")
        XCTAssertTrue(card.waitForExistence(timeout: 5), "Now Playing")
        XCTAssertTrue(eventually(5) { card.label.contains("Chapter 1: The Harbor") }, card.label)
        XCTAssertTrue(paragraph(app, "The harbor woke").waitForExistence(timeout: 10), "chapter 1's text")

        // The last paragraph of chapter 1, then let it end.
        for _ in 0..<5 { app.buttons["Next paragraph"].tap() }
        XCTAssertTrue(eventually(40) { card.label.contains("Chapter 2: The Lighthouse") },
                      "the header moves on to chapter 2: \(card.label)")
        XCTAssertTrue(paragraph(app, "The lighthouse stood").waitForExistence(timeout: 10), "chapter 2's first paragraph")
        XCTAssertTrue(eventually(5) { !self.paragraph(app, "The harbor woke").exists }, "chapter 1's text is gone")
        XCTAssertTrue(eventually(5) { app.buttons["listenPlayPause"].label == "Pause" }, "still playing")

        // A Reader on chapter 1, opened from its page in the browser while chapter 2 plays.
        app.buttons["Close Now Playing"].tap()
        XCTAssertTrue(eventually(5) { !card.exists }, "Now Playing closed")
        let field = app.textFields["addressField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("reader-test://pages/book-1\n")
        XCTAssertTrue(find(app, "addressListen").waitForExistence(timeout: 15), "chapter 1's page is readable")
        find(app, "addressReader").tap()

        let back = app.buttons["readerClose"]
        XCTAssertTrue(back.waitForExistence(timeout: 10), "the Reader opens")
        XCTAssertEqual(back.label, "Back to Browser", "a Reader, not Now Playing")
        XCTAssertTrue(paragraph(app, "The harbor woke").waitForExistence(timeout: 10), "on chapter 1")
        let listen = app.buttons["listenPlayPause"]
        XCTAssertTrue(listen.waitForExistence(timeout: 5))
        XCTAssertEqual(listen.label, "Listen Again", "it shows Listen, for chapter 1, heard to its end")

        idle(3) // chapter 2 plays on
        XCTAssertTrue(back.exists, "the Reader stays")
        XCTAssertTrue(paragraph(app, "The harbor woke").exists, "on chapter 1")
        XCTAssertFalse(paragraph(app, "The lighthouse stood").exists, "it doesn't follow the audio")
        XCTAssertEqual(listen.label, "Listen Again", "still Listen")
        let readerBar = find(app, "nowPlayingBarOpen")
        XCTAssertTrue(readerBar.exists && !readerBar.label.contains("Chapter 1"),
                      "the bar has what you hear, a later chapter: \(readerBar.label)")
        find(app, "nowPlayingBarPlayPause").tap()
    }

    /// Demo Finance's ▶ (`-seedDemoFolders`: Seven-Day Yield, Money Market Funds, Index Funds, in
    /// that order): its first page plays, Now Playing says it plays from the folder, and when the
    /// page ends the second one plays.
    func testAFoldersPlayPlaysItsFirstPageThenItsSecond() throws {
        let app = launchLibrary()
        let cell = libraryCell(app, "Demo Finance")
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        cell.buttons["Play"].tap()
        let bar = find(app, "nowPlayingBarOpen")
        XCTAssertTrue(bar.waitForExistence(timeout: 10), "the bar shows what you hear")
        XCTAssertTrue(eventually(10) { bar.label.contains("Seven-Day Yield") }, "page 1: \(bar.label)")
        XCTAssertTrue(eventually(5) { (self.libraryRow(app, "Demo Finance").value as? String)?.contains("Playing") == true },
                      "the folder's row says it plays")

        bar.tap()
        let card = find(app, "nowPlayingTitleCard")
        XCTAssertTrue(card.waitForExistence(timeout: 5), "Now Playing")
        XCTAssertEqual(playingFrom(app), "Playing from Demo Finance")
        // Its last paragraph, then let it end.
        for _ in 0..<5 { app.buttons["Next paragraph"].tap() }
        XCTAssertTrue(eventually(40) { card.label.contains("Money Market Funds") }, "page 2: \(card.label)")
        XCTAssertTrue(eventually(5) { app.buttons["listenPlayPause"].label == "Pause" }, "still playing")
        app.buttons["listenPlayPause"].tap()
    }

    /// The demo book's paragraph starting with `prefix`, on the reading page shown.
    private func paragraph(_ app: XCUIApplication, _ prefix: String) -> XCUIElement {
        app.webViews.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }
}
