import XCTest

/// Favorites are flags on pages and folders. They filter the Library's mixed list without changing
/// tree placement; the browser start page's Show All opens the same Favorites tab.
final class FavoritesUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func star(_ app: XCUIApplication) {
        app.buttons["browseMore"].tap()
        tapMenuRow(app, "moreFavorite")
    }

    private func starRow(_ app: XCUIApplication, _ title: String) {
        libraryRow(app, title).press(forDuration: 1.0)
        let addFavorite = app.buttons["Add to Favorites"]
        XCTAssertTrue(addFavorite.waitForExistence(timeout: 5))
        addFavorite.tap()
    }

    func testStarShowsOnStartPageAndInFavoritesTab() throws {
        let app = launchTestPages(["-seedDemoArticle"])
        openTestPage(app, "Next page")
        star(app)
        XCTAssertTrue(find(app, "toast").waitForExistence(timeout: 5), "Added to Favorites")

        app.buttons["browseLibrary"].tap()
        XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 5))
        let page = libraryRow(app, "Second page")
        XCTAssertTrue(page.waitForExistence(timeout: 5), "the loose page remains in Everything")
        app.buttons["Favorites"].tap()
        XCTAssertTrue(libraryRow(app, "Second page").waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Favorites"].exists, "Favorites is a filter, not a folder screen")

        app.buttons["libraryBrowser"].tap()
        app.buttons["browseMore"].tap()
        tapMenuRow(app, "moreNewSearch")
        let tile = app.buttons.matching(identifier: "favoriteTile").firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 5), "the starred page is also on the start page")
        XCTAssertEqual(tile.label, "Second page")
    }

    func testSearchFindsNestedFavoriteAndShowsItsPath() throws {
        let app = launchLibrary()
        openFolder(app, "Demo Finance")
        openFolder(app, "Bonds")
        starRow(app, "Coupon Basics")
        app.navigationBars["Bonds"].buttons["Demo Finance"].tap()
        app.navigationBars["Demo Finance"].buttons["Library"].tap()
        XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 5))
        let search = app.textFields["librarySearchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Coupon Basics")
        let row = libraryRow(app, "Coupon Basics")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue((row.value as? String)?.contains("Demo Finance › Bonds") == true, "location remains visible")
        app.buttons["Favorites"].tap()
        XCTAssertTrue(libraryRow(app, "Coupon Basics").waitForExistence(timeout: 5))
    }

    func testFavoriteTabShowAllFromStartPage() throws {
        let app = launchTestPages(["-seedDemoArticle"])
        openTestPage(app, "Third page")
        star(app)
        XCTAssertTrue(find(app, "toast").waitForExistence(timeout: 5))
        idle(1)
        app.buttons["browseMore"].tap()
        tapMenuRow(app, "moreNewSearch")
        XCTAssertTrue(find(app, "startFavoritesShowAll").waitForExistence(timeout: 5))
        find(app, "startFavoritesShowAll").tap()
        XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 5))
        XCTAssertTrue(libraryRow(app, "Third page").waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Favorites"].exists)
    }
}
