import XCTest

/// The Library home: its sections, a row's ▶ (the row tints while the bar shows the page), search
/// across the tree (a page in a nested folder; *Search the web*), and 🌐 there and back keeping
/// both the page and the Library's place. Offline, Apple voice.
final class LibraryHomeUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testSeededSectionsAndARowPlaysWithThePlayingTint() throws {
        let app = launchLibrary()
        for folder in ["Favorites", "The Demo Book", "Demo Finance"] {
            XCTAssertTrue(libraryRow(app, folder).waitForExistence(timeout: 5), "folder row \(folder)")
        }
        XCTAssertEqual(find(app, "continueCard").label, "Seven-Day Yield", "Continue: the part-way page in Demo Finance")
        let page = libraryRow(app, "Demo Listen Article")
        find(app, "libraryHome").swipeUp() // Pages, below Continue and Folders
        XCTAssertTrue(page.waitForExistence(timeout: 5), "Pages: the demo article")

        libraryCell(app, "Demo Listen Article").buttons["Play"].tap()
        let bar = app.buttons["nowPlayingBarPlayPause"]
        XCTAssertTrue(bar.waitForExistence(timeout: 10), "the bar shows what you hear")
        XCTAssertTrue(eventually(10) { bar.label == "Pause" }, "playing")
        XCTAssertTrue(eventually(5) { (page.value as? String)?.contains("Playing") == true },
                      "the row is tinted as playing, got \(page.value ?? "nil")")
        XCTAssertTrue(libraryCell(app, "Demo Listen Article").buttons["Pause"].exists, "its ▶ shows ⏸")
        bar.tap()
    }

    func testSearchFindsAPageInANestedFolderAndSearchesTheWeb() throws {
        let app = launchLibrary(["-browseTestPages"])
        app.buttons["librarySearch"].tap()
        let field = app.textFields["librarySearchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("Coupon")
        XCTAssertTrue(find(app, "librarySearchResults").waitForExistence(timeout: 5))
        XCTAssertTrue(libraryRow(app, "Coupon Basics").waitForExistence(timeout: 5), "in Demo Finance › Bonds")

        app.buttons["Clear search"].firstMatch.tap()
        field.typeText("reader-test://pages/two")
        let web = find(app, "librarySearchWeb")
        XCTAssertTrue(web.waitForExistence(timeout: 5), "the last row searches the web")
        web.tap()
        XCTAssertTrue(app.staticTexts["Second page"].waitForExistence(timeout: 10), "the browser, on the page")
        XCTAssertFalse(app.navigationBars["Library"].exists)
    }

    func testGlobeThereAndBackKeepsThePageAndTheFolder() throws {
        let app = launchTestPages()
        openTestPage(app, "Next page")
        app.buttons["browseLibrary"].tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
        openFolder(app, "Favorites")

        app.buttons["libraryBrowser"].tap()
        XCTAssertTrue(app.staticTexts["Second page"].waitForExistence(timeout: 5), "the page as it was")
        XCTAssertEqual(app.textFields["addressField"].value as? String, "pages/two")

        app.buttons["browseLibrary"].tap()
        XCTAssertTrue(app.navigationBars["Favorites"].waitForExistence(timeout: 5), "back at the same folder")
    }
}
