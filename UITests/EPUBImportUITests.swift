import XCTest

/// Importing a book (offline, Apple voice). `-importTestEPUB` makes *Import Book…* take the
/// synthetic EPUB (`TestEPUB`) instead of the Files picker, which a UI test can't drive; from
/// there it is the real import sheet and import.
/// - From a folder's screen, the import lands on the new book inside that folder, and the book's
///   Play starts chapter 1, not the title page.
/// - Importing it again asks *Replace* or *Cancel* (decision D13).
/// - An `.epub` link on a page downloads into the same sheet, which asks before importing.
/// - `-playTestEPUB` (import at launch, then play): the chapter's text is what the import made
///   of the file: the line loose in a `<div>` is there, the footnote isn't.
final class EPUBImportUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private let title = "The Imported Demo Book"

    func testImportFromAFolderLandsOnTheNewBookThereAndPlaysChapterOne() throws {
        let app = launchLibrary(["-importTestEPUB"])
        openFolder(app, "Demo Finance")
        app.buttons["libraryMore"].tap()
        tapMenuRow(app, "moreImportBook")

        // The import sheet shows while it works: under a second for this book, so it isn't waited for.
        let book = app.navigationBars[title]
        XCTAssertTrue(book.waitForExistence(timeout: 30), "lands on the new book")
        XCTAssertTrue(find(app, "folderScreen").exists, "the book's screen")
        XCTAssertFalse(find(app, "importSheet").exists, "the sheet has gone")
        XCTAssertTrue(book.buttons["Demo Finance"].exists, "inside Demo Finance (its back button)")
        XCTAssertTrue(libraryRow(app, "Title Page").exists, "the title page is a chapter")
        XCTAssertEqual(libraryRow(app, "Title Page").value as? String, "Skipped in playback")

        let play = app.buttons["folderContinue"]
        XCTAssertEqual(play.label, "Play")
        play.tap()
        let bar = find(app, "nowPlayingBarOpen")
        XCTAssertTrue(bar.waitForExistence(timeout: 15), "it plays")
        XCTAssertTrue(bar.label.contains("Chapter 1: The Harbor"), "chapter 1, not the title page: \(bar.label)")
        XCTAssertTrue(eventually(10) { self.find(app, "nowPlayingBarPlayPause").label == "Pause" }, "playing")
        find(app, "nowPlayingBarPlayPause").tap()

        book.buttons["Demo Finance"].tap()
        XCTAssertTrue(libraryRow(app, title).waitForExistence(timeout: 5), "the book is a row in Demo Finance")
    }

    func testImportingABookAlreadyInTheLibraryAsksReplaceOrCancel() throws {
        let app = launchLibrary(["-importTestEPUB"])
        importFromTheHome(app)
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 30), "imported once")
        app.navigationBars[title].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 5))

        importFromTheHome(app)
        let ask = app.alerts["“\(title)” is already in the Library"]
        XCTAssertTrue(ask.waitForExistence(timeout: 30), "D13: Replace or Cancel")
        XCTAssertTrue(ask.buttons["Replace"].firstMatch.exists)
        ask.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(eventually(5) { !self.find(app, "importSheet").exists }, "Cancel closes the sheet")
        XCTAssertTrue(app.libraryHome.exists, "and stays on the Library")
        XCTAssertEqual(app.cells.staticTexts.matching(NSPredicate(format: "label == %@", title)).count, 1,
                       "one book")

        importFromTheHome(app)
        XCTAssertTrue(ask.waitForExistence(timeout: 30), "asked again")
        ask.buttons["Replace"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 30), "Replace lands on the book")
        XCTAssertTrue(libraryRow(app, "Chapter 1: The Harbor").exists, "its chapters")
    }

    func testAnEPUBLinkOpensTheImportSheetWhichAsksFirst() throws {
        let app = launchTestPages(["-seedDemoFolders", "-importTestEPUB"])
        let link = app.links["Download a book"]
        XCTAssertTrue(link.waitForExistence(timeout: 10), "page one links to a book")
        link.tap()

        let sheet = find(app, "importSheet")
        XCTAssertTrue(sheet.waitForExistence(timeout: 15), "the download goes to the import sheet")
        XCTAssertTrue(app.links["Next page"].exists, "the browser stays on its page")
        let start = app.buttons["importStart"]
        XCTAssertTrue(start.waitForExistence(timeout: 3), "it asks first: Import")
        XCTAssertTrue(find(app, "importHeader").exists, "the book's header")
        let change = app.buttons["importChange"]
        XCTAssertTrue(change.label.contains("Library"), change.label)

        change.tap()
        XCTAssertTrue(find(app, "importAddToTree").waitForExistence(timeout: 5), "Change: the Move tree, in the sheet")
        moveTreeFolder(app, "Demo Finance").tap()
        XCTAssertTrue(eventually(5) { change.label.contains("Demo Finance") }, change.label)

        start.tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 30), "lands on the book, in the Library")
        XCTAssertTrue(app.navigationBars[title].buttons["Demo Finance"].exists, "inside Demo Finance")
    }

    /// ＋ → *Import Book…* on the screen shown.
    private func importFromTheHome(_ app: XCUIApplication) {
        app.buttons["libraryAdd"].tap()
        let item = app.buttons["libraryImportBook"]
        XCTAssertTrue(item.waitForExistence(timeout: 3), "＋ → Import Book…")
        item.tap()
    }

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
