import XCTest

/// Folders at any depth: a folder made inside a folder, a page filed there from the Reader's 🔖 in
/// two taps (long-press, a folder), Delete Folder Only moving the contents up (and never offered
/// with a book), the Move tree's New Folder Inside, and Edit moving several pages at once.
/// Offline: the demo folders and the test pages.
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

    /// Edit → a plain folder and a book → Remove: no *Delete Folder Only* (the book can't keep
    /// its chapters without it); the choices name the book. Keeping folder contents moves the
    /// folder's page up and deletes the book.
    func testRemovingAFolderAndABookTogetherNeverOffersFolderOnly() throws {
        let app = launchLibrary()
        openFolder(app, "The Demo Book")
        app.buttons["libraryMore"].tap()
        tapMenuRow(app, "moreMove")
        pickInMoveTree(app, "Demo Finance")
        XCTAssertTrue(app.navigationBars["The Demo Book"].waitForExistence(timeout: 5), "the book, in Demo Finance")
        app.navigationBars["The Demo Book"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Demo Finance"].waitForExistence(timeout: 5))

        app.buttons["folderEdit"].tap()
        libraryRow(app, "Bonds").tap()
        libraryRow(app, "The Demo Book").tap()
        app.buttons["editRemove"].tap()
        let keep = app.buttons["deleteBooksKeepFolderContents"].firstMatch
        XCTAssertTrue(keep.waitForExistence(timeout: 3), "the delete question")
        XCTAssertFalse(app.buttons["deleteFolderOnly"].exists, "no Delete Folder Only")
        XCTAssertEqual(keep.label, "Delete Book, Keep Folder Contents")
        XCTAssertEqual(app.buttons["deleteFolderAndContents"].firstMatch.label, "Delete Everything")
        XCTAssertTrue(app.staticTexts["“The Demo Book” is deleted with its chapters and downloads either way. The folder holds 1 page."]
            .exists, "says the book goes either way")
        keep.tap()
        XCTAssertTrue(eventually(5) { !self.libraryRow(app, "Bonds").exists }, "Bonds is gone")
        XCTAssertFalse(libraryRow(app, "The Demo Book").exists, "so is the book")
        XCTAssertTrue(libraryRow(app, "Coupon Basics").waitForExistence(timeout: 5), "Bonds' page moved up")
    }

    /// In the Move tree, a folder's long-press → *New Folder Inside* makes the folder in it, and
    /// what is being moved goes there.
    func testTheMoveTreeMakesANewFolderInsideAFolder() throws {
        let app = launchLibrary()
        openFolder(app, "Demo Finance")
        libraryRow(app, "Index Funds").press(forDuration: 1.0)
        let move = app.buttons["Move to…"]
        XCTAssertTrue(move.waitForExistence(timeout: 3), "the row's menu")
        move.tap()
        XCTAssertTrue(find(app, "moveTree").waitForExistence(timeout: 5))
        // At the medium detent Bonds is the last row, cut off by the sheet's bottom edge, where
        // a long-press lands as a tap (it picked Bonds) instead of opening the menu. Open the
        // sheet to full height so the row is wholly on screen first.
        find(app, "moveTree").swipeUp()
        let bonds = moveTreeFolder(app, "Bonds")
        XCTAssertTrue(eventually(3) { bonds.isHittable && bonds.frame.maxY < app.frame.maxY - 80 }, "Bonds on screen")
        bonds.press(forDuration: 1.0)
        let inside = app.buttons["moveNewFolderInside"].firstMatch
        XCTAssertTrue(inside.waitForExistence(timeout: 3), "New Folder Inside")
        inside.tap()
        createFolder(app, named: "Short Term")
        XCTAssertTrue(eventually(5) { !self.libraryRow(app, "Index Funds").exists }, "moved out")
        openFolder(app, "Bonds")
        openFolder(app, "Short Term")
        XCTAssertTrue(libraryRow(app, "Index Funds").waitForExistence(timeout: 5), "in the new folder, inside Bonds")
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
