import XCTest

/// Browser bottom bar: no tab bar, toolbar `[‹][›][Search][Library][⋯]` (⋯ = the morph menu panel
/// with Favorites / History), the address-field reader icon (readable pages only), Favorites,
/// and edit mode that cancels via ✕ or a pull-down (restoring the page address).
final class BrowseToolbarUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(testPage: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        // Developer options on (Debug rows), whatever an earlier test stored.
        app.launchArguments = ["-uiTesting", "-resetBookmarks", "-reader.developerOptions", "YES",
                               "-reader.rateMultiplier", "1"]
            + (testPage ? ["-browseTestPages"] : [])
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func waitFor(_ predicate: String, _ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let exp = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        return XCTWaiter().wait(for: [exp], timeout: timeout) == .completed
    }

    /// Tap the dimmed backdrop of the morph menu (Safari-style: tap outside collapses it).
    private func center(_ f: CGRect) -> CGPoint { CGPoint(x: f.midX, y: f.midY) }

    /// With the menu open, the bottom-right button's icon (Reader / Website) sits slightly up and
    /// left of the ⋯ glyph (`MorphMenuUITestOffset`). `moreMenuFocus` (-uiTesting only) is that
    /// icon's measured center.
    private func assertMenuAligned(_ app: XCUIApplication, more moreFrame: CGRect, button id: String,
                                   file: StaticString = #filePath, line: UInt = #line) {
        let focus = element(app, "moreMenuFocus")
        XCTAssertTrue(focus.waitForExistence(timeout: 3), "focus marker", file: file, line: line)
        RunLoop.current.run(until: Date().addingTimeInterval(1.0)) // morph finished
        let f = center(focus.frame), m = center(moreFrame)
        let x = m.x - MorphMenuUITestOffset.width, y = m.y - MorphMenuUITestOffset.height
        XCTAssertEqual(f.x, x, accuracy: 1, "icon left of ⋯", file: file, line: line)
        XCTAssertEqual(f.y, y, accuracy: 1, "icon above ⋯", file: file, line: line)
        XCTAssertEqual(element(app, id).frame.midX, x, accuracy: 1, "\(id) centered on the focus point", file: file, line: line)
    }

    private func dismissMenu(_ app: XCUIApplication) {
        let dismiss = element(app, "moreMenuDismiss")
        if dismiss.waitForExistence(timeout: 2) {
            dismiss.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        }
    }

    func testToolbarButtonsAndHistoryState() throws {
        let app = launch(testPage: true)
        let back = app.buttons["browseBack"]
        let forward = app.buttons["browseForward"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        for id in ["browseForward", "browseMore"] {
            XCTAssertTrue(element(app, id).exists, "\(id) exists")
        }
        XCTAssertFalse(element(app, "browseSaved").exists, "Saved lives in ⋯ (Safari-style)")
        XCTAssertFalse(element(app, "browseReader").exists, "Reader is the address-field icon / ⋯ toggle")
        XCTAssertTrue(element(app, "browseLibrary").exists, "Library↔Browser slot beside ⋯")
        XCTAssertFalse(element(app, "addressMic").exists, "mic only while searching, not idle")
        XCTAssertFalse(app.tabBars.firstMatch.isHittable, "no tab bar on Browse")

        let link = app.links["Next page"]
        XCTAssertTrue(link.waitForExistence(timeout: 10), "offline test page loaded")
        XCTAssertFalse(back.isEnabled, "nothing to go back to yet")
        XCTAssertFalse(forward.isEnabled)

        XCTAssertFalse(element(app, "addressReader").exists, "page one isn't an article: no reader icon")

        link.tap()
        XCTAssertTrue(app.staticTexts["Second page"].waitForExistence(timeout: 5), "second page loaded")
        XCTAssertTrue(element(app, "addressReader").waitForExistence(timeout: 5), "article page: reader icon")
        XCTAssertTrue(waitFor("isEnabled == true", back), "back enables after navigating")
        XCTAssertFalse(forward.isEnabled)

        back.tap()
        XCTAssertTrue(waitFor("isEnabled == true", forward), "forward enables after going back")
        XCTAssertTrue(waitFor("isEnabled == false", back), "back disables at the start of history")

        forward.tap()
        XCTAssertTrue(waitFor("isEnabled == true", back))
        XCTAssertTrue(waitFor("isEnabled == false", forward))

        // Five-slot grid: Search in the middle slot (3 of 5), ⋯ in slot 5.
        let search = app.buttons["browseSearch"]
        XCTAssertTrue(search.exists)
        let row = app.windows.firstMatch.frame
        XCTAssertEqual(search.frame.midX, row.midX, accuracy: 1, "Search centered")
        XCTAssertLessThan(forward.frame.midX, search.frame.minX, "‹ › left of Search")
        XCTAssertGreaterThan(app.buttons["browseMore"].frame.minX, search.frame.maxX - 1, "⋯ right of Search")
        search.tap()
        let field = app.textFields["addressField"]
        XCTAssertTrue(waitFor("hasKeyboardFocus == true", field), "Search focuses the field")
        XCTAssertTrue(waitFor("value == 'Search or enter address' OR value == ''", field), "empty, for a new search")
        XCTAssertTrue(element(app, "addressMic").waitForExistence(timeout: 2), "mic while searching")
        XCTAssertTrue(element(app, "addressCancel").exists)
        element(app, "addressCancel").tap()
        XCTAssertTrue(waitFor("hasKeyboardFocus == false", field))
        XCTAssertTrue(back.isEnabled, "still on the same page")

        // ⋯ panel: action rows, then the big Favorites / History / Reader buttons.
        let browseMoreFrame = app.buttons["browseMore"].frame
        app.buttons["browseMore"].tap()
        assertMenuAligned(app, more: browseMoreFrame, button: "moreReaderToggle")
        for id in ["moreNewSearch", "moreSave", "moreFavorite", "moreShare", "moreReload",
                   "moreVoice", "moreDebug", "moreFavorites", "moreHistory", "moreReaderToggle"] {
            XCTAssertTrue(element(app, id).waitForExistence(timeout: 3), "⋯ has \(id)")
        }
        XCTAssertFalse(element(app, "moreLibrary").exists, "the Library is slot 4, not a big button")
        XCTAssertFalse(element(app, "moreReader").exists, "the Open in Reader row is gone (bottom-right toggle)")
        XCTAssertTrue(element(app, "moreMenuPanel").exists, "Safari-style panel (no popover arrow)")
        element(app, "moreReload").tap()
        XCTAssertTrue(waitFor("exists == false", element(app, "moreReload")), "panel closes")

        // 📚 → the library surface (shared chrome); Browser slot returns to the page.
        app.buttons["browseLibrary"].tap()
        XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 5), "library surface")
        XCTAssertTrue(element(app, "libraryBrowser").waitForExistence(timeout: 3), "Browser swap slot")
        element(app, "libraryBrowser").tap()
        XCTAssertTrue(waitFor("exists == false", app.libraryHome), "back on the browser")
        XCTAssertTrue(back.isEnabled, "page state kept")

        // History → the visited pages; tapping one opens it.
        app.buttons["browseMore"].tap()
        element(app, "moreHistory").tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5), "history sheet")
        let secondVisit = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Second page'")).firstMatch
        if secondVisit.waitForExistence(timeout: 3) {
            secondVisit.tap()
            XCTAssertTrue(waitFor("exists == false", app.navigationBars["History"]))
        } else {
            app.navigationBars["History"].swipeDown(velocity: .fast)
        }
    }

    func testReaderToggleDisabledOnStartPage() throws {
        let app = launch(testPage: false)
        let more = app.buttons["browseMore"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()
        let toggle = element(app, "moreReaderToggle")
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertFalse(toggle.isEnabled, "new page / start page → Reader disabled")
        XCTAssertFalse(toggle.isSelected)
        XCTAssertTrue(element(app, "moreMenuPanel").exists, "morph panel open")
        dismissMenu(app)
        XCTAssertTrue(waitFor("exists == false", element(app, "moreMenuPanel")))
    }

    /// The ⋯ panel follows a vertical drag: an upward one springs back (rubber band), a downward
    /// one collapses it back into the button.
    func testMenuPanelSwipeUpSpringsBackAndSwipeDownCollapses() throws {
        let app = launch(testPage: false)
        let more = app.buttons["browseMore"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()
        let panel = element(app, "moreMenuPanel")
        XCTAssertTrue(panel.waitForExistence(timeout: 3))
        RunLoop.current.run(until: Date().addingTimeInterval(1.0)) // morph finished
        let open = panel.frame

        panel.swipeUp()
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        XCTAssertTrue(panel.exists, "an upward drag doesn't close the menu")
        XCTAssertEqual(panel.frame.minY, open.minY, accuracy: 1, "…and the panel springs back")

        panel.swipeDown()
        XCTAssertTrue(waitFor("exists == false", panel), "swipe down collapses the menu")
        more.tap()
        XCTAssertTrue(panel.waitForExistence(timeout: 3), "⋯ is back and opens the menu again")
    }

    func testReaderIconAndReaderToggle() throws {
        let app = launch(testPage: true)
        let link = app.links["Next page"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        // Page one isn't readable: the ⋯ Reader toggle is disabled.
        app.buttons["browseMore"].tap()
        let toggle = element(app, "moreReaderToggle")
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertFalse(toggle.isEnabled, "not readable → disabled")
        dismissMenu(app)
        XCTAssertTrue(waitFor("exists == false", toggle))

        link.tap()
        let icon = element(app, "addressReader")
        XCTAssertTrue(icon.waitForExistence(timeout: 5))
        icon.tap()
        let close = app.buttons["readerClose"]
        XCTAssertTrue(close.waitForExistence(timeout: 10), "reader icon opens the reader")
        XCTAssertEqual(close.label, "Back to Browser", "opened over the page")
        close.tap()
        XCTAssertTrue(waitFor("exists == false", close))

        // ⋯ → Reader (bottom-right) switches into reader mode…
        let browseMoreFrame = app.buttons["browseMore"].frame
        app.buttons["browseMore"].tap()
        XCTAssertTrue(waitFor("isEnabled == true", toggle), "readable → enabled")
        XCTAssertFalse(toggle.isSelected)
        toggle.tap()
        XCTAssertTrue(close.waitForExistence(timeout: 10), "⋯ → Reader opens the reader")

        let website = element(app, "moreWebsite")
        // …where ⋯ sits in the Reader's bottom-right (no gear) and shows the same panel.
        XCTAssertFalse(app.buttons["listenQuickSettings"].exists, "no gear: voice settings live in ⋯")
        let readerMore = app.buttons["readerMore"]
        XCTAssertTrue(readerMore.waitForExistence(timeout: 5))
        // The Reader's bottom row is on the browser's grid; ⋯ sits in exactly the same cell.
        let rf = readerMore.frame
        XCTAssertEqual(rf.midX, browseMoreFrame.midX, accuracy: 1, "⋯ at the same x as the browser's")
        XCTAssertEqual(rf.midY, browseMoreFrame.midY, accuracy: 1, "⋯ at the same y as the browser's")
        XCTAssertEqual(rf.width, browseMoreFrame.width, accuracy: 1)
        XCTAssertEqual(rf.height, browseMoreFrame.height, accuracy: 1)
        readerMore.tap()
        // In reader mode the bottom-right button is Website (reader off → the page), not Reader.
        XCTAssertTrue(website.waitForExistence(timeout: 3))
        XCTAssertTrue(website.isEnabled)
        XCTAssertFalse(toggle.exists, "no Reader toggle inside the reader")
        assertMenuAligned(app, more: rf, button: "moreWebsite")
        for id in ["moreVoice", "moreSave", "moreFavorite", "moreShare", "moreDebug",
                   "moreFavorites", "moreHistory"] {
            XCTAssertTrue(element(app, id).exists, "reader ⋯ has \(id)")
        }
        XCTAssertFalse(element(app, "moreNewSearch").exists, "browser-only rows stay out of the reader menu")
        XCTAssertFalse(element(app, "moreReload").exists)

        // Voice settings (what the gear held) opens as a sheet.
        element(app, "moreVoice").tap()
        XCTAssertTrue(app.navigationBars["Listen"].waitForExistence(timeout: 5), "voice settings sheet")
        app.navigationBars["Listen"].buttons["Done"].tap()
        XCTAssertTrue(waitFor("exists == false", app.navigationBars["Listen"]))

        // Add the page to Favorites from the reader (wait for the morph to finish growing before tapping
        // a row: mid-animation the rows are still scaled toward the ⋯ button).
        readerMore.tap()
        XCTAssertTrue(website.waitForExistence(timeout: 3))
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        element(app, "moreFavorite").tap()
        XCTAssertTrue(waitFor("exists == false", website), "panel closes")
        readerMore.tap()
        XCTAssertTrue(waitFor("label == 'Remove from Favorites'", element(app, "moreFavorite")), "a favorite from the reader")

        // Website → back to the web page (already loaded: revealed, not reloaded).
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        website.tap()
        XCTAssertTrue(waitFor("exists == false", close), "Website leaves reader mode")
        XCTAssertTrue(app.buttons["browseMore"].waitForExistence(timeout: 5), "web page chrome is back")
        XCTAssertTrue(app.staticTexts["Second page"].exists, "same page")
    }

    func testReaderMenuInLibraryReader() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedDemoArticle", "-uiTesting", "-openLibrary", "-resetBookmarks", "-reader.rateMultiplier", "1"]
        app.launch()
        let row = app.cells.staticTexts["Demo Listen Article"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let close = app.buttons["readerClose"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))

        // The menu's bottom-right button is Website, its icon exactly where ⋯ was.
        let readerMore = app.buttons["readerMore"]
        XCTAssertTrue(readerMore.waitForExistence(timeout: 5))
        let moreFrame = readerMore.frame
        readerMore.tap()
        XCTAssertTrue(element(app, "moreWebsite").waitForExistence(timeout: 3))
        XCTAssertFalse(element(app, "moreReaderToggle").exists)
        assertMenuAligned(app, more: moreFrame, button: "moreWebsite")

        // ⋯ → History from the library reader: the library closes, History opens.
        element(app, "moreMenuDismiss").tap()
        XCTAssertTrue(waitFor("exists == false", element(app, "moreMenuPanel")))
        readerMore.tap()
        element(app, "moreHistory").tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 8), "history sheet")
        XCTAssertFalse(app.libraryHome.exists, "library closed first")
    }

    /// The library's ⋯ is its own menu: nothing in it acts on the page hidden under the library.
    func testLibraryMenuLeavesThePageAlone() throws {
        let app = launch(testPage: true)
        XCTAssertTrue(app.links["Next page"].waitForExistence(timeout: 10))
        app.buttons["browseLibrary"].tap()
        XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 5), "library surface")

        let libraryMore = app.buttons["libraryMore"]
        let moreFrame = libraryMore.frame
        libraryMore.tap()
        assertMenuAligned(app, more: moreFrame, button: "moreBrowser")
        for id in ["moreVoice", "moreNewFolder", "moreFavorites", "moreHistory", "moreBrowser"] {
            XCTAssertTrue(element(app, id).exists, "library ⋯ has \(id)")
        }
        for id in ["moreNewSearch", "moreReload", "moreSave", "moreFavorite", "moreShare", "moreReaderToggle", "moreLibrary"] {
            XCTAssertFalse(element(app, id).exists, "page actions stay out of the library menu: \(id)")
        }

        // History leaves the library first; the page underneath is still there.
        element(app, "moreHistory").tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5), "history sheet")
        XCTAssertFalse(app.libraryHome.exists, "library closed first")
        app.navigationBars["History"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.99)))
        XCTAssertTrue(waitFor("exists == false", app.navigationBars["History"]))
        XCTAssertTrue(app.links["Next page"].exists, "same page")

        // Browser (big button) returns to the page as it was.
        app.buttons["browseLibrary"].tap()
        XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 5))
        libraryMore.tap()
        XCTAssertTrue(element(app, "moreBrowser").waitForExistence(timeout: 3))
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        element(app, "moreBrowser").tap()
        XCTAssertTrue(waitFor("exists == false", app.libraryHome), "library left")
        XCTAssertTrue(app.links["Next page"].exists, "page kept")
        XCTAssertEqual(app.textFields["addressField"].value as? String, "pages/one")
    }

    /// Open a saved article, Listen (the Reader turns into Now Playing), ⋯ → Website: Now Playing and
    /// the library close, the browser loads the article's page, and the voice keeps going (the bar).
    func testSavedArticleWebsiteOpensPageAndKeepsPlaying() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedDemoArticle", "-uiTesting", "-openLibrary", "-resetBookmarks", "-reader.rateMultiplier", "1",
                               "-selectEngine", "apple"]
        app.launch()
        let row = app.cells.staticTexts["Demo Listen Article"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let close = app.buttons["readerClose"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))

        let play = app.buttons["listenPlayPause"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()
        XCTAssertTrue(waitFor("label == 'Pause'", play, timeout: 8), "playing")

        app.buttons["readerMore"].tap()
        let website = element(app, "moreWebsite")
        XCTAssertTrue(website.waitForExistence(timeout: 3))
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        website.tap()

        XCTAssertTrue(waitFor("exists == false", close, timeout: 8), "reader closed")
        XCTAssertTrue(waitFor("exists == false", app.libraryHome, timeout: 8), "library closed")
        let field = app.textFields["addressField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(waitFor("value CONTAINS 'example.com/demo'", field, timeout: 8), "the article's page is loading")
        let mini = app.buttons["nowPlayingBarPlayPause"]
        XCTAssertTrue(mini.waitForExistence(timeout: 5), "the Now Playing bar shows")
        XCTAssertEqual(mini.label, "Pause", "the voice keeps playing")
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        XCTAssertEqual(mini.label, "Pause", "…and is still playing")
        mini.tap()
    }

    func testFavoriteShowsOnStartPageAndDeletes() throws {
        let app = launch(testPage: true)
        XCTAssertTrue(app.links["Next page"].waitForExistence(timeout: 10))
        app.buttons["browseMore"].tap()
        let favorite = element(app, "moreFavorite")
        XCTAssertTrue(favorite.waitForExistence(timeout: 3))
        XCTAssertEqual(favorite.label, "Add to Favorites")
        favorite.tap()
        XCTAssertTrue(waitFor("exists == false", favorite), "panel closes")

        app.buttons["browseMore"].tap()
        XCTAssertTrue(waitFor("label == 'Remove from Favorites'", element(app, "moreFavorite")), "now a favorite")
        element(app, "moreNewSearch").tap() // → start page

        let tile = app.buttons.matching(identifier: "favoriteTile").firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 5), "Favorites grid on the start page")
        XCTAssertEqual(tile.label, "First page")

        // The Favorites sheet from the grid's Show All.
        element(app, "startFavoritesShowAll").tap()
        XCTAssertTrue(app.navigationBars["Favorites"].waitForExistence(timeout: 5))
        let bar = app.navigationBars["Favorites"]
        bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.99)))
        XCTAssertTrue(waitFor("exists == false", app.navigationBars["Favorites"]))

        // Long-press → Remove from Favorites.
        tile.press(forDuration: 1.0)
        let delete = app.buttons["Remove from Favorites"]
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        delete.tap()
        XCTAssertTrue(waitFor("exists == false", tile), "deleted")
    }

    func testCancelButtonRestoresAddress() throws {
        let app = launch(testPage: true)
        let field = app.textFields["addressField"]
        XCTAssertTrue(app.links["Next page"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitFor("value == 'pages/one'", field), "shows the page address")

        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let cancel = app.buttons["addressCancel"]
        XCTAssertTrue(cancel.exists, "✕ while editing")
        XCTAssertFalse(app.buttons["browseBack"].exists, "toolbar steps aside while typing")
        field.typeText("something else")

        cancel.tap()
        XCTAssertTrue(waitFor("exists == false", app.keyboards.firstMatch), "keyboard dismissed")
        XCTAssertEqual(field.value as? String, "pages/one", "previous address restored")
        XCTAssertFalse(cancel.exists)
        XCTAssertTrue(app.buttons["browseBack"].waitForExistence(timeout: 3), "toolbar back")
    }

    func testSwipeDownLowersKeyboardKeepsSearch() throws {
        let app = launch(testPage: true)
        let field = app.textFields["addressField"]
        XCTAssertTrue(app.links["Next page"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitFor("value == 'pages/one'", field))

        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        field.typeText("zzq")
        let backdrop = element(app, "addressEditBackdrop")
        XCTAssertTrue(backdrop.waitForExistence(timeout: 3))
        backdrop.swipeDown()

        // Safari: swipe-down dismisses the keyboard but stays in search mode.
        XCTAssertTrue(waitFor("exists == false", app.keyboards.firstMatch), "pull-down dismissed keyboard")
        XCTAssertEqual(field.value as? String, "zzq", "typed text kept")
        let cancel = app.buttons["addressCancel"]
        XCTAssertTrue(cancel.exists, "✕ still shown")
        XCTAssertFalse(app.buttons["browseBack"].exists, "toolbar still stepped aside")

        cancel.tap()
        XCTAssertEqual(field.value as? String, "pages/one", "✕ restores address")
        XCTAssertTrue(app.buttons["browseBack"].waitForExistence(timeout: 3))
    }

    func testSwipeDownLowersKeyboardOnStartPage() throws {
        let app = launch(testPage: false)
        let field = app.textFields["addressField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        field.typeText("abc")
        element(app, "addressEditBackdrop").swipeDown()
        XCTAssertTrue(waitFor("exists == false", app.keyboards.firstMatch))
        XCTAssertEqual(field.value as? String, "abc", "typed text kept while still searching")
        XCTAssertTrue(app.buttons["addressCancel"].exists, "✕ still shown")
        app.buttons["addressCancel"].tap()
        XCTAssertNotEqual(field.value as? String, "abc", "✕ exits search")
    }
}
