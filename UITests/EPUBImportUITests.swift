import XCTest

/// A book imported from an EPUB file plays (`-importTestEPUB -playTestEPUB`: the synthetic EPUB
/// goes through the real import into the Library's top level, then plays as a book's Play does;
/// Apple voice, offline). It starts at chapter 1, not the title page, and its text is what the
/// import made of the file: the line loose in a `<div>` is there, the footnote isn't.
///
/// Starting from a folder's screen, with the import landing on the new book inside that folder,
/// waits for the Library screens (step 4).
final class EPUBImportUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testAnImportedBookPlaysChapterOneNotItsTitlePage() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetBookmarks", "-importTestEPUB", "-playTestEPUB",
                               "-selectEngine", "apple", "-reader.rateMultiplier", "1"]
        app.launch()

        let bar = find(app, "nowPlayingBarOpen")
        XCTAssertTrue(bar.waitForExistence(timeout: 30), "the imported book plays")
        XCTAssertTrue(bar.label.contains("Chapter 1: The Harbor"), "chapter 1, not the title page: \(bar.label)")
        XCTAssertTrue(bar.label.contains("The Imported Demo Book"), "from the book: \(bar.label)")
        XCTAssertTrue(eventually(10) { self.find(app, "nowPlayingBarPlayPause").label == "Pause" }, "playing")

        bar.tap()
        let card = find(app, "nowPlayingTitleCard")
        XCTAssertTrue(card.waitForExistence(timeout: 5), "Now Playing")
        XCTAssertTrue(eventually(5) { card.label.contains("Chapter 1: The Harbor") }, card.label)
        XCTAssertTrue(paragraph(app, "This line sits loose in a div").waitForExistence(timeout: 10),
                      "the line loose in a div is on the page (its listen block: TestEPUBHookTests)")
        XCTAssertTrue(paragraph(app, "The harbor woke").exists, "chapter 1's first paragraph")
        XCTAssertFalse(paragraph(app, "A footnote, which is never read").exists, "the footnote isn't")
        XCTAssertFalse(paragraph(app, "Demo Author").exists, "nor the title page")
        let pause = app.buttons["listenPlayPause"]
        XCTAssertEqual(pause.label, "Pause", "still playing")
        pause.tap()
    }

    /// The reading page's paragraph starting with `prefix`.
    private func paragraph(_ app: XCUIApplication, _ prefix: String) -> XCUIElement {
        app.webViews.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }
}
