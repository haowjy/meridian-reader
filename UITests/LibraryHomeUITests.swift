import XCTest

/// The Library's D20 surface: a mixed list, independent Everything/Favorites tabs, search across
/// folders and pages, large rows with Download/Play, and the folder header. Existing playback and
/// browser return behavior remain intact. Offline, Apple voice.
final class LibraryHomeUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testSeededSectionsAndARowPlaysWithThePlayingTint() throws {
        let app = launchLibrary()
        for folder in ["The Demo Book", "Demo Finance"] {
            XCTAssertTrue(libraryRow(app, folder).waitForExistence(timeout: 5), "folder row \(folder)")
        }
        XCTAssertFalse(app.navigationBars.firstMatch.exists, "no navigation bar: the title is in the list")
        XCTAssertTrue(find(app, "libraryTitle").exists)
        XCTAssertTrue(find(app, "libraryTabs").exists, "Everything and Favorites filters")
        let page = libraryRow(app, "Demo Listen Article")
        XCTAssertTrue(page.waitForExistence(timeout: 5), "Pages: the demo article")

        let cell = libraryCell(app, "Demo Listen Article")
        let header = find(app, "libraryTitle").frame
        let finance = libraryCell(app, "Demo Finance").frame
        let before = try XCTUnwrap(ScreenColor.median(in: XCUIScreen.main.screenshot(), region: cell.frame))
        cell.buttons["Play"].tap()
        let bar = app.buttons["nowPlayingBarPlayPause"]
        XCTAssertTrue(bar.waitForExistence(timeout: 10), "the bar shows what you hear")
        XCTAssertTrue(eventually(10) { bar.label == "Pause" }, "playing")
        idle(0.8)
        XCTAssertEqual(find(app, "libraryTitle").frame, header, "nothing on the home moves when playback starts")
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
        XCTAssertTrue((book.value as? String)?.hasPrefix("Chapter 2: The Lighthouse, ") == true, "its place, got \(book.value ?? "nil")")
        XCTAssertTrue((book.value as? String)?.hasSuffix(" left") == true, "and what's left, got \(book.value ?? "nil")")

        let cell = libraryCell(app, "The Demo Book")
        let play = cell.buttons["Play"]
        XCTAssertTrue(play.exists, "a book row has its own ▶")
        XCTAssertTrue(cell.buttons["Download"].exists, "the cover row exposes its download state")
        XCTAssertEqual(play.frame.midX, cell.buttons["Download"].frame.midX, accuracy: 1, "download and play share a control column")
        let header = find(app, "libraryTitle").frame
        play.tap()
        let bar = app.buttons["nowPlayingBarPlayPause"]
        XCTAssertTrue(bar.waitForExistence(timeout: 10), "the bar shows what you hear")
        XCTAssertTrue(eventually(10) { bar.label == "Pause" }, "playing")
        XCTAssertTrue(find(app, "nowPlayingBarOpen").label.contains("Chapter 2"), "from its place: \(find(app, "nowPlayingBarOpen").label)")
        XCTAssertTrue(eventually(5) { (book.value as? String)?.contains("Playing") == true },
                      "the row says so, got \(book.value ?? "nil")")
        XCTAssertFalse(find(app, "folderScreen").exists, "playing never navigates")
        XCTAssertEqual(find(app, "libraryTitle").frame, header, "the home stays put")
        XCTAssertEqual(bar.frame.midX, app.buttons["libraryMore"].frame.midX, accuracy: 1, "the now-playing action stays aligned to the toolbar slot")
        bar.tap()

        book.tap()
        XCTAssertTrue(find(app, "folderScreen").waitForExistence(timeout: 5), "a tap on the row opens the book")
    }

    /// A page played without saving shows at the top of Pages, "Not saved", with *Save* in its
    /// menu; saved, it stays in Pages without the mark.
    func testAPagePlayedWithoutSavingShowsNotSavedAndSaveKeepsIt() throws {
        let app = launchLibrary(["-seedPlayedPages", "1"])
        let row = libraryRow(app, "Played Page 1")
        XCTAssertTrue(row.waitForExistence(timeout: 5), "in Pages")
        XCTAssertTrue((row.value as? String)?.contains("Not saved") == true, "marked, got \(row.value ?? "nil")")
        XCTAssertTrue(libraryCell(app, "Played Page 1").exists)

        row.press(forDuration: 1.0)
        let save = app.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 3), "Save in its menu")
        XCTAssertFalse(app.buttons["Remove from Library"].exists, "it isn't in the Library to remove")
        save.tap()
        XCTAssertTrue(eventually(5) { (row.value as? String)?.contains("Not saved") == false },
                      "saved: no mark, got \(row.value ?? "nil")")
        XCTAssertTrue(row.exists, "still in Pages")
    }

    /// Everything/Favorites filters the same Library list; Favorites does not navigate to a folder.
    func testFavoritesTabShowsStarredItemsWithoutOpeningASpecialFolder() throws {
        let app = launchLibrary()
        XCTAssertTrue(libraryRow(app, "Demo Finance").waitForExistence(timeout: 5))
        libraryRow(app, "Demo Finance").press(forDuration: 1.0)
        let addFavorite = app.buttons["Add to Favorites"]
        XCTAssertTrue(addFavorite.waitForExistence(timeout: 5))
        addFavorite.tap()
        let favorites = app.buttons["Favorites"]
        XCTAssertTrue(favorites.waitForExistence(timeout: 3))
        favorites.tap()
        XCTAssertTrue(libraryRow(app, "Demo Finance").waitForExistence(timeout: 5))
        XCTAssertFalse(libraryRow(app, "The Demo Book").exists)
        XCTAssertFalse(app.navigationBars["Favorites"].exists)
    }

    func testSearchFindsAPageInANestedFolderAndFiltersIt() throws {
        let app = launchLibrary(["-browseTestPages"])
        let field = app.textFields["librarySearchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("Coupon")
        XCTAssertTrue(libraryRow(app, "Coupon Basics").waitForExistence(timeout: 5), "in Demo Finance › Bonds")
        app.buttons["Clear search"].tap()
        field.typeText("not-a-match")
        XCTAssertFalse(libraryRow(app, "Coupon Basics").exists, "search filters the same list")
    }

    func testGlobeThereAndBackKeepsThePageAndTheFolder() throws {
        let app = launchTestPages()
        openTestPage(app, "Next page")
        app.buttons["browseLibrary"].tap()
        XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 5))
        openFolder(app, "Demo Finance")

        app.buttons["libraryBrowser"].tap()
        XCTAssertTrue(app.staticTexts["Second page"].waitForExistence(timeout: 5), "the page as it was")
        XCTAssertEqual(app.textFields["addressField"].value as? String, "pages/two")

        app.buttons["browseLibrary"].tap()
        XCTAssertTrue(app.navigationBars["Demo Finance"].waitForExistence(timeout: 5), "back at the same folder")
    }

    // MARK: - Mixed list and folder rows

    func testFolderRowsOpenTheirExistingContents() throws {
        let app = launchLibrary()
        XCTAssertTrue(libraryRow(app, "Demo Finance").waitForExistence(timeout: 5))
        openFolder(app, "Demo Finance")
        XCTAssertTrue(libraryRow(app, "Seven-Day Yield").waitForExistence(timeout: 5))
        XCTAssertTrue(libraryCell(app, "Seven-Day Yield").buttons["Download"].exists)
    }

    func testEverythingUsesOneMixedListForFoldersAndPages() throws {
        let app = launchLibrary(["-seedLoosePages", "2"])
        XCTAssertTrue(find(app, "libraryTabs").exists)
        XCTAssertTrue(libraryRow(app, "Demo Finance").waitForExistence(timeout: 5))
        find(app, "libraryHome").swipeUp()
        for title in ["Demo Listen Article", "Loose Page 1", "Loose Page 2"] {
            XCTAssertTrue(libraryRow(app, title).waitForExistence(timeout: 5), title)
        }
    }

    func testBookFolderUsesTheSamePageRowsAsOtherFolders() throws {
        let app = launchLibrary()
        XCTAssertTrue(libraryRow(app, "The Demo Book").waitForExistence(timeout: 5))
        openFolder(app, "The Demo Book")
        XCTAssertTrue(libraryRow(app, "Chapter 1: The Harbor").waitForExistence(timeout: 5))
        XCTAssertTrue(libraryCell(app, "Chapter 1: The Harbor").buttons["Download"].exists)
    }
}
