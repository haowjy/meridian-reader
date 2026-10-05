import XCTest

/// Folders at any depth: a folder made inside a folder, a page filed there from the Reader's 🔖 in
/// two taps (long-press, a folder), Delete Folder Only moving the contents up, and Edit moving
/// several pages at once. Offline: the demo folders and the test pages.
final class FolderUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testMakeAFolderInsideAFolderAndFileAPageThereFromTheReader() throws {
        let app = launchLibrary(["-browseTestPages"])
        openFolder(app, "Demo Finance")
        app.buttons["libraryMore"].tap()
        tapMenuRow(app, "moreNewFolder")
        createFolder(app, named: "Notes")
        XCTAssertTrue(libraryRow(app, "Notes").waitForExistence(timeout: 5), "Notes inside Demo Finance")

        app.buttons["libraryBrowser"].tap()
        openTestPage(app, "Next page")
        find(app, "addressReader").tap()
        let bookmark = app.buttons["readerBookmark"]
        XCTAssertTrue(bookmark.waitForExistence(timeout: 10))
        bookmark.press(forDuration: 1.0) // tap 1: Save to Folder…
        pickInMoveTree(app, "Notes") // tap 2
        XCTAssertTrue(eventually(5) { bookmark.value as? String == "Saved" }, "saved")

        closeReader(app)
        app.buttons["browseLibrary"].tap()
        XCTAssertTrue(app.navigationBars["Demo Finance"].waitForExistence(timeout: 5), "the Library where it was")
        openFolder(app, "Notes")
        XCTAssertTrue(libraryRow(app, "Second page").waitForExistence(timeout: 5), "filed in Notes")
    }

    func testDeleteFolderOnlyMovesItsContentsUp() throws {
        let app = launchLibrary()
        openFolder(app, "Demo Finance")
        XCTAssertFalse(libraryRow(app, "Coupon Basics").exists, "inside Bonds for now")
        libraryRow(app, "Bonds").press(forDuration: 1.0)
        let delete = app.buttons["Delete…"]
        XCTAssertTrue(delete.waitForExistence(timeout: 3), "the row's menu")
        delete.tap()
        let folderOnly = app.buttons["deleteFolderOnly"].firstMatch
        XCTAssertTrue(folderOnly.waitForExistence(timeout: 3), "Delete Folder Only / and Contents")
        XCTAssertTrue(app.buttons["deleteFolderAndContents"].firstMatch.exists)
        folderOnly.tap()
        XCTAssertTrue(eventually(5) { !self.libraryRow(app, "Bonds").exists }, "Bonds is gone")
        XCTAssertTrue(libraryRow(app, "Coupon Basics").waitForExistence(timeout: 5), "its page moved up")
    }

    func testEditMovesSeveralPages() throws {
        let app = launchLibrary()
        openFolder(app, "Demo Finance")
        app.buttons["folderEdit"].tap()
        libraryRow(app, "Seven-Day Yield").tap()
        libraryRow(app, "Index Funds").tap()
        app.buttons["editMove"].tap()
        pickInMoveTree(app, "Taxes")
        app.buttons["folderEdit"].tap()
        XCTAssertTrue(eventually(5) { !self.libraryRow(app, "Seven-Day Yield").exists }, "moved out")
        XCTAssertFalse(libraryRow(app, "Index Funds").exists)
        XCTAssertTrue(libraryRow(app, "Money Market Funds").exists, "the unselected page stays")
        openFolder(app, "Taxes")
        XCTAssertTrue(libraryRow(app, "Seven-Day Yield").waitForExistence(timeout: 5))
        XCTAssertTrue(libraryRow(app, "Index Funds").exists)
    }
}
