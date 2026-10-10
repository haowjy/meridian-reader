import XCTest

/// The Library home: its sections, a row's ▶ (the row tints while the bar shows the page, and
/// nothing on the home moves), a book row's place and ▶ (resumes it without opening it), a page
/// played without saving ("Not saved", *Save*), ★ in slot 2, search across the tree (a page in a
/// nested folder; *Search the web*), and 🌐 there and back keeping both the page and the
/// Library's place. Offline, Apple voice.
final class LibraryHomeUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testSeededSectionsAndARowPlaysWithThePlayingTint() throws {
        let app = launchLibrary()
        for folder in ["Favorites", "The Demo Book", "Demo Finance"] {
            XCTAssertTrue(libraryRow(app, folder).waitForExistence(timeout: 5), "folder row \(folder)")
        }
        XCTAssertFalse(app.navigationBars.firstMatch.exists, "no navigation bar: the title is in the list")
        XCTAssertTrue(find(app, "libraryTitle").exists)
        XCTAssertFalse(app.staticTexts["Continue"].exists, "no Continue section")
        let page = libraryRow(app, "Demo Listen Article")
        XCTAssertTrue(page.waitForExistence(timeout: 5), "Pages: the demo article")

        let cell = libraryCell(app, "Demo Listen Article")
        let header = find(app, "libraryPagesHeader").frame
        let finance = libraryCell(app, "Demo Finance").frame
        let before = try XCTUnwrap(ScreenColor.median(in: XCUIScreen.main.screenshot(), region: cell.frame))
        cell.buttons["Play"].tap()
        let bar = app.buttons["nowPlayingBarPlayPause"]
        XCTAssertTrue(bar.waitForExistence(timeout: 10), "the bar shows what you hear")
        XCTAssertTrue(eventually(10) { bar.label == "Pause" }, "playing")
        idle(0.8)
        XCTAssertEqual(find(app, "libraryPagesHeader").frame, header, "nothing on the home moves when playback starts")
        XCTAssertEqual(libraryCell(app, "Demo Finance").frame, finance)
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

    /// A book row shows its place and time left; its ▶ resumes it there and never opens it (the
    /// row tints, the home stays put); a tap on the row opens the book.
    func testABookRowShowsItsPlaceAndItsPlayResumesItWithoutOpeningIt() throws {
        let app = launchLibrary(["-seedDemoBookPlace", "2"])
        let book = libraryRow(app, "The Demo Book")
        XCTAssertTrue(book.waitForExistence(timeout: 5))
        XCTAssertTrue((book.value as? String)?.hasPrefix("Ch 2, ") == true, "its place, got \(book.value ?? "nil")")
        XCTAssertTrue((book.value as? String)?.hasSuffix(" left") == true, "and what's left, got \(book.value ?? "nil")")

        let cell = libraryCell(app, "The Demo Book")
        let play = cell.buttons["Play"]
        XCTAssertTrue(play.exists, "a book row has its own ▶")
        // One column: the row's ▶ is centred over ⋯, as the bar's ⏸ is.
        XCTAssertEqual(play.frame.midX, app.buttons["libraryMore"].frame.midX, accuracy: 1, "▶ over ⋯")
        let header = find(app, "libraryPagesHeader").frame
        play.tap()
        let bar = app.buttons["nowPlayingBarPlayPause"]
        XCTAssertTrue(bar.waitForExistence(timeout: 10), "the bar shows what you hear")
        XCTAssertTrue(eventually(10) { bar.label == "Pause" }, "playing")
        XCTAssertTrue(find(app, "nowPlayingBarOpen").label.contains("Chapter 2"), "from its place: \(find(app, "nowPlayingBarOpen").label)")
        XCTAssertTrue(eventually(5) { (book.value as? String)?.contains("Playing") == true },
                      "the row says so, got \(book.value ?? "nil")")
        XCTAssertFalse(find(app, "bookScreen").exists, "playing never navigates")
        XCTAssertEqual(find(app, "libraryPagesHeader").frame, header, "the home stays put")
        XCTAssertEqual(bar.frame.midX, cell.buttons["Pause"].frame.midX, accuracy: 1, "the bar's ⏸ and the row's share a column")
        bar.tap()

        book.tap()
        XCTAssertTrue(find(app, "bookScreen").waitForExistence(timeout: 5), "a tap on the row opens the book")
    }

    /// A page played without saving shows at the top of Pages, "Not saved", with *Save* in its
    /// menu; saved, it stays in Pages without the mark.
    func testAPagePlayedWithoutSavingShowsNotSavedAndSaveKeepsIt() throws {
        let app = launchLibrary(["-seedPlayedPages", "1"])
        let row = libraryRow(app, "Played Page 1")
        XCTAssertTrue(row.waitForExistence(timeout: 5), "in Pages")
        XCTAssertTrue((row.value as? String)?.contains("Not saved") == true, "marked, got \(row.value ?? "nil")")
        let header = find(app, "libraryPagesHeader").frame
        XCTAssertLessThan(header.maxY, libraryCell(app, "Played Page 1").frame.minY + 1)
        XCTAssertLessThan(libraryCell(app, "Played Page 1").frame.minY, libraryCell(app, "Demo Listen Article").frame.minY,
                          "on top of Pages")

        row.press(forDuration: 1.0)
        let save = app.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 3), "Save in its menu")
        XCTAssertFalse(app.buttons["Remove from Library"].exists, "it isn't in the Library to remove")
        save.tap()
        XCTAssertTrue(eventually(5) { (row.value as? String)?.contains("Not saved") == false },
                      "saved: no mark, got \(row.value ?? "nil")")
        XCTAssertTrue(row.exists, "still in Pages")
    }

    /// ★ in slot 2 pushes Favorites, from the home and from a folder.
    func testStarInSlotTwoPushesFavorites() throws {
        let app = launchLibrary()
        let star = app.buttons["libraryFavorites"]
        XCTAssertTrue(star.exists)
        star.tap()
        XCTAssertTrue(app.navigationBars["Favorites"].waitForExistence(timeout: 5), "Favorites, pushed")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 5), "‹ comes back home")
        openFolder(app, "Demo Finance")
        star.tap()
        XCTAssertTrue(app.navigationBars["Favorites"].waitForExistence(timeout: 5), "from a folder too")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Demo Finance"].waitForExistence(timeout: 5), "and ‹ goes back to the folder")
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
        XCTAssertFalse(app.libraryHome.exists)
    }

    func testGlobeThereAndBackKeepsThePageAndTheFolder() throws {
        let app = launchTestPages()
        openTestPage(app, "Next page")
        app.buttons["browseLibrary"].tap()
        XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 5))
        openFolder(app, "Favorites")

        app.buttons["libraryBrowser"].tap()
        XCTAssertTrue(app.staticTexts["Second page"].waitForExistence(timeout: 5), "the page as it was")
        XCTAssertEqual(app.textFields["addressField"].value as? String, "pages/two")

        app.buttons["browseLibrary"].tap()
        XCTAssertTrue(app.navigationBars["Favorites"].waitForExistence(timeout: 5), "back at the same folder")
    }
}
