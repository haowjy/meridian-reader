import XCTest

/// The demo book's screen: front matter dimmed and skipped, a chapter tap opens its Reader,
/// Continue plays the current chapter (chapter 1 for a fresh book; the place, at its paragraph,
/// for a book part-way) and turns into the playing state, and no Edit. Offline, Apple voice.
final class BookFolderUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testBookScreen() throws {
        let app = launchLibrary()
        openFolder(app, "The Demo Book")
        XCTAssertTrue(find(app, "bookScreen").exists)
        XCTAssertFalse(app.buttons["folderEdit"].exists, "no Edit: the order is the book's")

        let titlePage = libraryRow(app, "Title Page")
        XCTAssertTrue(titlePage.waitForExistence(timeout: 5))
        XCTAssertTrue((titlePage.value as? String)?.contains("Skipped") == true, "front matter: skipped")
        XCTAssertFalse(libraryCell(app, "Title Page").buttons["Play"].exists, "and no ▶")
        // Dimmed: its title stands out from the row less than a chapter's does.
        let chapter = libraryRow(app, "Chapter 1: The Harbor")
        XCTAssertTrue(chapter.waitForExistence(timeout: 5))
        let shot = XCUIScreen.main.screenshot()
        let dimmed = try XCTUnwrap(ScreenColor.textContrast(in: shot, region: titlePage.frame))
        let normal = try XCTUnwrap(ScreenColor.textContrast(in: shot, region: chapter.frame))
        XCTAssertLessThan(dimmed, normal * 0.75, "the title page is dimmed: \(dimmed):1 against a chapter's \(normal):1")

        libraryRow(app, "Chapter 2: The Lighthouse").tap()
        let close = app.buttons["readerClose"]
        XCTAssertTrue(close.waitForExistence(timeout: 10), "the chapter's Reader")
        XCTAssertEqual(close.label, "Back to Library")
        close.tap()
        XCTAssertTrue(eventually(5) { !close.exists })

        let play = app.buttons["bookContinue"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        XCTAssertEqual(play.label, "Play from Chapter 1")
        play.tap()
        let bar = app.buttons["nowPlayingBarPlayPause"]
        XCTAssertTrue(bar.waitForExistence(timeout: 10))
        XCTAssertTrue(eventually(10) { bar.label == "Pause" }, "playing")
        XCTAssertTrue(eventually(5) { play.label == "Playing · Ch 1" }, "got \(play.label)")
        XCTAssertEqual(play.value as? String, "Pause", "the book's button is the playing state")
        play.tap()
        XCTAssertTrue(eventually(5) { bar.label == "Resume" || bar.label == "Play" }, "paused from the book")
    }

    /// Part-way through the book (its place on chapter 2, at the third paragraph; chapter 1
    /// finished), Continue plays chapter 2 from that paragraph, not the book from its start.
    func testContinueResumesTheBookAtItsPlace() throws {
        let app = launchLibrary(["-seedDemoBookPlace", "2"])
        openFolder(app, "The Demo Book")
        let play = app.buttons["bookContinue"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        XCTAssertTrue(play.label.hasPrefix("Continue") && play.label.contains("Ch 2"), "got \(play.label)")
        play.tap()
        let bar = app.buttons["nowPlayingBarPlayPause"]
        XCTAssertTrue(bar.waitForExistence(timeout: 10))
        XCTAssertTrue(eventually(10) { bar.label == "Pause" }, "playing")
        bar.tap()
        XCTAssertTrue(eventually(5) { bar.label == "Resume" || bar.label == "Play" }, "paused")
        XCTAssertTrue(eventually(5) { play.label.contains("Ch 2") }, "the book's button: \(play.label)")

        find(app, "nowPlayingBarOpen").tap()
        XCTAssertTrue(app.staticTexts["Chapter 2: The Lighthouse"].waitForExistence(timeout: 5), "Now Playing: chapter 2")
        let scrubber = find(app, "readerScrubber")
        XCTAssertTrue(scrubber.waitForExistence(timeout: 5))
        XCTAssertEqual((scrubber.value as? String)?.hasPrefix("Paragraph 3 of"), true,
                       "from its place, got \(scrubber.value ?? "nil")")
    }
}
