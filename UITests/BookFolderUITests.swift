import XCTest

/// The demo book's screen: front matter dimmed and skipped, a chapter tap opens its Reader,
/// Continue plays the current chapter and turns into the playing state, and no Edit. Offline,
/// Apple voice.
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
}
