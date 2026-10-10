import XCTest

/// The Library home: its sections, a row's ▶ (the row tints while the bar shows the page), a
/// Continue card (opens at its spot; its ▶ resumes there), search across the tree (a page in a
/// nested folder; *Search the web*), and 🌐 there and back keeping both the page and the
/// Library's place. Offline, Apple voice.
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

        let cell = libraryCell(app, "Demo Listen Article")
        let before = try XCTUnwrap(ScreenColor.median(in: XCUIScreen.main.screenshot(), region: cell.frame))
        cell.buttons["Play"].tap()
        let bar = app.buttons["nowPlayingBarPlayPause"]
        XCTAssertTrue(bar.waitForExistence(timeout: 10), "the bar shows what you hear")
        XCTAssertTrue(eventually(10) { bar.label == "Pause" }, "playing")
        XCTAssertTrue(eventually(5) { (page.value as? String)?.contains("Playing") == true },
                      "the row says it is playing, got \(page.value ?? "nil")")
        XCTAssertTrue(cell.buttons["Pause"].exists, "its ▶ shows ⏸")
        // The tint itself: the row's background turns the playing green (`Palette.playingTint`).
        // Read above the bar, which now covers the list's bottom: scroll the row up first.
        find(app, "libraryHome").swipeUp()
        idle(0.8)
        var visible = cell.frame
        let barTop = find(app, "nowPlayingBar").frame.minY
        if barTop < visible.maxY { visible.size.height = max(0, barTop - visible.minY) }
        XCTAssertGreaterThan(visible.height, 20, "the row shows above the bar: \(cell.frame)")
        let tinted = try XCTUnwrap(ScreenColor.median(in: XCUIScreen.main.screenshot(), region: visible))
        bar.tap()
        XCTAssertGreaterThan(ScreenColor.distance(before, tinted), 0.03, "the row's background changed: \(before) → \(tinted)")
        XCTAssertGreaterThan(tinted[1], tinted[0] + 0.02, "to a green tint: \(tinted)")
        XCTAssertLessThan(before[1], before[0] + 0.01, "from the plain row colour: \(before)")
    }

    /// A Continue card opens the page in the Reader at its spot, and the card's ▶ resumes it
    /// from that paragraph (the saved spot is paragraph 2 of 3).
    func testAContinueCardOpensAtItsSpotAndItsPlayResumesThere() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-seedDemoArticle", "-seedDemoProgress", "1", "-resetBookmarks",
                               "-selectEngine", "apple", "-reader.rateMultiplier", "1", "-openLibrary"]
        app.launch()
        let card = find(app, "continueCard")
        XCTAssertTrue(card.waitForExistence(timeout: 10), "Continue: the part-way article")
        XCTAssertEqual(card.label, "Demo Listen Article")

        // The card's body opens it; the Reader offers to resume.
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.7)).tap()
        let close = app.buttons["readerClose"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), "the Reader")
        XCTAssertEqual(close.label, "Back to Library")
        let listen = app.buttons["listenPlayPause"]
        XCTAssertTrue(listen.waitForExistence(timeout: 5))
        XCTAssertTrue(listen.label.hasPrefix("Resume"), "offers to resume: \(listen.label)")
        closeReader(app)

        // The card's ▶ (top right) resumes it there: pause at once, then Now Playing's scrubber.
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.15)).tap()
        let bar = app.buttons["nowPlayingBarPlayPause"]
        XCTAssertTrue(bar.waitForExistence(timeout: 10), "playing from the card")
        XCTAssertTrue(eventually(10) { bar.label == "Pause" }, "playing")
        bar.tap()
        XCTAssertTrue(eventually(5) { bar.label == "Resume" || bar.label == "Play" }, "paused")
        XCTAssertFalse(app.buttons["readerClose"].exists, "playing never navigates")
        XCTAssertTrue(eventually(5) { (card.value as? String)?.contains("Paused") == true }, "the card shows it, got \(card.value ?? "nil")")
        find(app, "nowPlayingBarOpen").tap()
        let scrubber = find(app, "readerScrubber")
        XCTAssertTrue(scrubber.waitForExistence(timeout: 5), "Now Playing")
        XCTAssertEqual(scrubber.value as? String, "Paragraph 2 of 3", "resumed at the saved paragraph")
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
