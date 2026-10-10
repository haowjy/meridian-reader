import XCTest

/// Favorites is a folder: ☆ puts a test page on the start page grid; Change Folder into a
/// Favorites subfolder makes it a folder tile holding the page; the Favorites sheet makes
/// folders and sorts; *Library (no folder)* takes a favorite out of Favorites; a link page in the
/// Library loads in the browser; ☆ on a page filed in another folder asks to move it. Offline: the test pages; the demo seed
/// empties the Library first, so no earlier test's page or folder changes what ☆ does.
final class FavoritesUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func star(_ app: XCUIApplication) {
        app.buttons["browseMore"].tap()
        tapMenuRow(app, "moreFavorite")
    }

    /// ⋯ → Sort › `title`, in the Favorites sheet.
    private func sortFavorites(_ app: XCUIApplication, _ title: String) {
        app.buttons["favoritesMore"].tap()
        let sort = find(app, "moreSort")
        XCTAssertTrue(sort.waitForExistence(timeout: 3), "⋯ → Sort, in the sheet")
        idle(0.6)
        sort.tap()
        let choice = app.buttons[title].firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 3))
        choice.tap()
        idle(0.8)
    }

    private func startPage(_ app: XCUIApplication) {
        app.buttons["browseMore"].tap()
        tapMenuRow(app, "moreNewSearch")
        XCTAssertTrue(find(app, "browseStartPage").waitForExistence(timeout: 5))
    }

    func testStarPutsThePageOnTheStartPageGrid() throws {
        let app = launchTestPages(["-seedDemoArticle"])
        openTestPage(app, "Next page")
        star(app)
        XCTAssertTrue(find(app, "toast").waitForExistence(timeout: 5), "Added to Favorites")
        startPage(app)
        let tile = app.buttons.matching(identifier: "favoriteTile").firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        XCTAssertEqual(tile.label, "Second page")
    }

    func testChangeFolderIntoAFavoritesSubfolderMakesAFolderTile() throws {
        let app = launchTestPages(["-seedDemoArticle"])
        XCTAssertTrue(app.links["Next page"].waitForExistence(timeout: 10))
        app.buttons["browseLibrary"].tap()
        openFolder(app, "Favorites")
        app.buttons["libraryMore"].tap()
        tapMenuRow(app, "moreNewFolder")
        createFolder(app, named: "Serials")
        XCTAssertTrue(libraryRow(app, "Serials").waitForExistence(timeout: 5))
        app.buttons["libraryBrowser"].tap()

        openTestPage(app, "Next page")
        star(app)
        let change = app.buttons["toastAction"]
        XCTAssertTrue(change.waitForExistence(timeout: 5), "Change Folder")
        change.tap()
        pickInMoveTree(app, "Serials")

        startPage(app)
        let folderTile = app.buttons.matching(identifier: "favoriteFolderTile").firstMatch
        XCTAssertTrue(folderTile.waitForExistence(timeout: 5), "a folder tile")
        XCTAssertEqual(folderTile.label, "Serials")
        XCTAssertFalse(app.buttons.matching(identifier: "favoriteTile").firstMatch.exists, "the page left the grid")
        folderTile.tap()
        XCTAssertTrue(app.navigationBars["Serials"].waitForExistence(timeout: 5), "the folder, in the Favorites sheet")
        XCTAssertTrue(libraryRow(app, "Second page").waitForExistence(timeout: 5), "the page is inside it")
    }

    /// The Favorites sheet has the folder screen's own controls: New Folder (＋, and ⋯ → New
    /// Folder Inside, at the top and in a subfolder) and ⋯ → Sort.
    func testTheFavoritesSheetMakesFoldersInsideAndSorts() throws {
        let app = launchTestPages(["-seedDemoArticle"])
        openTestPage(app, "Next page")
        star(app)
        XCTAssertTrue(eventually(10) { !self.find(app, "toast").exists })
        backToPageOne(app)
        openTestPage(app, "Third page")
        star(app)
        XCTAssertTrue(eventually(10) { !self.find(app, "toast").exists })

        app.buttons["browseMore"].tap()
        tapMenuRow(app, "moreFavorites")
        XCTAssertTrue(app.navigationBars["Favorites"].waitForExistence(timeout: 5), "the Favorites sheet")
        let second = libraryRow(app, "Second page"), third = libraryRow(app, "Third page")
        XCTAssertTrue(third.waitForExistence(timeout: 5))
        XCTAssertLessThan(second.frame.minY, third.frame.minY, "Manual (the reset's sort): in the order added")

        sortFavorites(app, "Newest")
        XCTAssertTrue(eventually(5) { third.frame.minY < second.frame.minY }, "Newest: the last one added first")
        sortFavorites(app, "Manual")
        XCTAssertTrue(eventually(5) { second.frame.minY < third.frame.minY }, "Manual again")

        app.buttons["favoritesMore"].tap()
        tapMenuRow(app, "moreNewFolder")
        createFolder(app, named: "Shelf")
        XCTAssertTrue(libraryRow(app, "Shelf").waitForExistence(timeout: 5), "New Folder Inside Favorites")
        openFolder(app, "Shelf")
        app.buttons["favoritesMore"].tap()
        tapMenuRow(app, "moreNewFolder")
        createFolder(app, named: "Inner")
        XCTAssertTrue(libraryRow(app, "Inner").waitForExistence(timeout: 5), "and inside its subfolder")
        app.buttons["favoritesNewFolder"].tap()
        createFolder(app, named: "Second Inner")
        XCTAssertTrue(libraryRow(app, "Second Inner").waitForExistence(timeout: 5), "＋ makes one in the folder on screen")
        XCTAssertTrue(app.navigationBars["Shelf"].exists)
    }

    /// The browser's ⋯ → Save to Library… → *Library (no folder)* on a page in Favorites: it is
    /// saved, and out of Favorites.
    func testSavingAFavoriteToNoFolderFromTheBrowserTakesItOutOfFavorites() throws {
        let app = launchTestPages(["-seedDemoArticle"])
        openTestPage(app, "Next page")
        star(app)
        XCTAssertTrue(eventually(10) { !self.find(app, "toast").exists })
        app.buttons["browseMore"].tap()
        tapMenuRow(app, "moreSave")
        pickInMoveTree(app, topLevel: true)
        // (The browser's ⋯ says Saved for web pages only; the Library shows it.)
        app.buttons["browseLibrary"].tap()
        XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 5))
        XCTAssertTrue(libraryRow(app, "Second page").waitForExistence(timeout: 15), "saved, under Pages (no folder)")
        openFolder(app, "Favorites")
        XCTAssertFalse(libraryRow(app, "Second page").exists, "and no longer in Favorites")
    }

    /// The Reader's 🔖 long-press → *Library (no folder)* on a page in Favorites: the same.
    func testSavingAFavoriteToNoFolderFromTheReaderTakesItOutOfFavorites() throws {
        let app = launchTestPages(["-seedDemoArticle"])
        openTestPage(app, "Next page")
        star(app)
        XCTAssertTrue(eventually(10) { !self.find(app, "toast").exists })
        find(app, "addressReader").tap()
        let bookmark = app.buttons["readerBookmark"]
        XCTAssertTrue(bookmark.waitForExistence(timeout: 10))
        bookmark.press(forDuration: 1.0)
        pickInMoveTree(app, topLevel: true)
        XCTAssertTrue(eventually(5) { bookmark.value as? String == "Saved" }, "saved")
        app.buttons["readerMore"].tap()
        XCTAssertTrue(eventually(5) { self.find(app, "moreFavorite").label == "Add to Favorites" }, "and no longer a favorite")
    }

    func testALinkPageInTheLibraryLoadsInTheBrowser() throws {
        let app = launchTestPages(["-seedDemoArticle"])
        openTestPage(app, "Third page")
        star(app)
        XCTAssertTrue(eventually(10) { !self.find(app, "toast").exists }, "the toast goes by itself")
        backToPageOne(app)
        app.buttons["browseLibrary"].tap()
        openFolder(app, "Favorites")
        let link = libraryRow(app, "Third page")
        XCTAssertTrue(link.waitForExistence(timeout: 5), "the link page")
        link.tap()
        XCTAssertTrue(app.staticTexts["Third page"].waitForExistence(timeout: 10), "loaded in the browser")
        XCTAssertEqual(app.textFields["addressField"].value as? String, "pages/three")
    }

    func testStarOnAPageFiledElsewhereAsksToMoveIt() throws {
        let app = launchTestPages(["-seedDemoArticle", "-seedDemoFolders"])
        openTestPage(app, "Next page")
        find(app, "addressReader").tap()
        let bookmark = app.buttons["readerBookmark"]
        XCTAssertTrue(bookmark.waitForExistence(timeout: 10))
        bookmark.press(forDuration: 1.0)
        pickInMoveTree(app, "Demo Finance")
        XCTAssertTrue(eventually(5) { bookmark.value as? String == "Saved" })
        closeReader(app)

        star(app)
        let move = app.buttons["promptConfirm"].firstMatch
        XCTAssertTrue(move.waitForExistence(timeout: 5), "Move it to Favorites?")
        move.tap()
        app.buttons["browseMore"].tap()
        XCTAssertTrue(eventually(5) { self.find(app, "moreFavorite").label == "Remove from Favorites" }, "now a favorite")
    }
}
