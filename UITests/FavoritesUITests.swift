import XCTest

/// Favorites is a folder: ☆ puts a test page on the start page grid; Change Folder into a
/// Favorites subfolder makes it a folder tile; a link page in the Library loads in the browser;
/// ☆ on a page filed in another folder asks to move it. Offline: the test pages; the demo seed
/// empties the Library first, so no earlier test's page or folder changes what ☆ does.
final class FavoritesUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func star(_ app: XCUIApplication) {
        app.buttons["browseMore"].tap()
        tapMenuRow(app, "moreFavorite")
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
        XCTAssertFalse(app.buttons.matching(identifier: "favoriteTile").firstMatch.exists, "the page is inside it")
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
