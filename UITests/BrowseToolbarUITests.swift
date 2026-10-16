import XCTest

/// Browser bottom bar: no tab bar, 📚 before the address field, toolbar `[‹][›][🔖][🕘][⋯]` (⋯ =
/// the morph menu panel with Favorites / History), the address-field reader icon (readable pages only), Favorites,
/// and edit mode that cancels via ✕ or a pull-down (restoring the page address).
final class BrowseToolbarUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// The browser (on the offline test pages, or the start page), developer options on (Debug
    /// rows).
    private func launchBrowser(testPage: Bool) -> XCUIApplication {
        launch(UITestSetup(["-reader.developerOptions", "YES"] + (testPage ? ["-browseTestPages"] : [])))
    }

    /// Tap the dimmed backdrop of the morph menu (Safari-style: tap outside collapses it).
    private func center(_ f: CGRect) -> CGPoint { CGPoint(x: f.midX, y: f.midY) }

    /// With the menu open, the bottom-right button's icon (Reader / Website) sits slightly up and
    /// left of the ⋯ glyph (`MorphMenuUITestOffset`). `moreMenuFocus` (-uiTesting only) is that
    /// icon's measured center.
    private func assertMenuAligned(_ app: XCUIApplication, more moreFrame: CGRect, button id: String,
                                   file: StaticString = #filePath, line: UInt = #line) {
        let focus = find(app, "moreMenuFocus")
        XCTAssertTrue(focus.waitForExistence(timeout: 3), "focus marker", file: file, line: line)
        XCTAssertNotNil(settledFrames([focus, find(app, "moreMenuPanel")]), "morph finished", file: file, line: line)
        let f = center(focus.frame), m = center(moreFrame)
        let x = m.x - MorphMenuUITestOffset.width, y = m.y - MorphMenuUITestOffset.height
        XCTAssertEqual(f.x, x, accuracy: 1, "icon left of ⋯", file: file, line: line)
        XCTAssertEqual(f.y, y, accuracy: 1, "icon above ⋯", file: file, line: line)
        XCTAssertEqual(find(app, id).frame.midX, x, accuracy: 1, "\(id) centered on the focus point", file: file, line: line)
    }

    func testToolbarButtonsAndHistoryState() throws {
        let app = launchBrowser(testPage: true)
        let back = app.buttons["browseBack"]
        let forward = app.buttons["browseForward"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        for id in ["browseForward", "browseMore"] {
            XCTAssertTrue(find(app, id).exists, "\(id) exists")
        }
        XCTAssertFalse(find(app, "browseSaved").exists, "Saved lives in ⋯ (Safari-style)")
        XCTAssertFalse(find(app, "browseReader").exists, "Reader is the address-field icon / ⋯ toggle")
        XCTAssertTrue(find(app, "browseLibrary").exists, "Library↔Browser swap before the field")
        XCTAssertFalse(find(app, "browseSearch").exists, "a new search is a tap on the field")
        XCTAssertFalse(find(app, "addressMic").exists, "mic only while searching, not idle")
        XCTAssertFalse(app.tabBars.firstMatch.isHittable, "no tab bar on Browse")

        let link = app.links["Next page"]
        XCTAssertTrue(link.waitForExistence(timeout: 10), "offline test page loaded")
        XCTAssertFalse(back.isEnabled, "nothing to go back to yet")
        XCTAssertFalse(forward.isEnabled)

        XCTAssertFalse(find(app, "addressReader").exists, "page one isn't an article: no reader icon")

        link.tap()
        XCTAssertTrue(app.staticTexts["Second page"].waitForExistence(timeout: 5), "second page loaded")
        XCTAssertTrue(find(app, "addressReader").waitForExistence(timeout: 5), "article page: reader icon")
        XCTAssertTrue(eventually { back.exists && back.isEnabled }, "back enables after navigating")
        XCTAssertFalse(forward.isEnabled)

        back.tap()
        XCTAssertTrue(eventually { forward.exists && forward.isEnabled }, "forward enables after going back")
        XCTAssertTrue(eventually { back.exists && !back.isEnabled }, "back disables at the start of history")

        forward.tap()
        XCTAssertTrue(eventually { back.exists && back.isEnabled })
        XCTAssertTrue(eventually { forward.exists && !forward.isEnabled })

        // Five-slot grid: 🔖 in the middle slot (3 of 5), 🕘 in slot 4, ⋯ in slot 5.
        let save = app.buttons["browseSave"]
        XCTAssertTrue(save.exists)
        XCTAssertTrue(save.isEnabled, "a page to save")
        let row = app.windows.firstMatch.frame
        XCTAssertEqual(save.frame.midX, row.midX, accuracy: 1, "🔖 centered")
        XCTAssertLessThan(forward.frame.midX, save.frame.minX, "‹ › left of 🔖")
        XCTAssertLessThan(save.frame.maxX - 1, app.buttons["browseHistory"].frame.minX, "🕘 right of 🔖")
        XCTAssertGreaterThan(app.buttons["browseMore"].frame.minX, app.buttons["browseHistory"].frame.maxX - 1, "⋯ last")
        let field = app.textFields["addressField"]
        field.tap()
        XCTAssertTrue(eventually { field.exists && field.hasKeyboardFocus }, "tapping the field searches")
        XCTAssertTrue(find(app, "addressMic").waitForExistence(timeout: 2), "mic while searching")
        XCTAssertTrue(find(app, "addressCancel").exists)
        find(app, "addressCancel").tap()
        XCTAssertTrue(eventually { field.exists && !field.hasKeyboardFocus })
        XCTAssertTrue(back.isEnabled, "still on the same page")

        // ⋯ panel: action rows, then the big Favorites / History / Reader buttons.
        let browseMoreFrame = app.buttons["browseMore"].frame
        app.buttons["browseMore"].tap()
        assertMenuAligned(app, more: browseMoreFrame, button: "moreReaderToggle")
        for id in ["moreNewSearch", "moreSave", "moreFavorite", "moreShare", "moreReload",
                   "moreDownloads", "moreSettings", "moreFavorites", "moreHistory", "moreReaderToggle"] {
            XCTAssertTrue(find(app, id).waitForExistence(timeout: 3), "⋯ has \(id)")
        }
        XCTAssertFalse(find(app, "moreLibrary").exists, "the Library is the band's swap, not a big button")
        XCTAssertFalse(find(app, "moreReader").exists, "the Open in Reader row is gone (bottom-right toggle)")
        XCTAssertTrue(find(app, "moreMenuPanel").exists, "Safari-style panel (no popover arrow)")
        find(app, "moreReload").tap()
        XCTAssertTrue(eventually { !find(app, "moreReload").exists }, "panel closes")

        // 📚 → the library surface (shared chrome); Browser slot returns to the page.
        app.buttons["browseLibrary"].tap()
        XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 5), "library surface")
        XCTAssertTrue(find(app, "libraryBrowser").waitForExistence(timeout: 3), "Browser swap slot")
        find(app, "libraryBrowser").tap()
        XCTAssertTrue(eventually { !app.libraryHome.exists }, "back on the browser")
        XCTAssertTrue(back.isEnabled, "page state kept")

        // 🕘 → the visited pages; tapping one opens it.
        app.buttons["browseHistory"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5), "history sheet")
        let secondVisit = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Second page'")).firstMatch
        if secondVisit.waitForExistence(timeout: 3) {
            secondVisit.tap()
            XCTAssertTrue(eventually { !app.navigationBars["History"].exists })
        } else {
            app.navigationBars["History"].swipeDown(velocity: .fast)
        }
    }

    func testReaderToggleDisabledOnStartPage() throws {
        let app = launchBrowser(testPage: false)
        let more = app.buttons["browseMore"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()
        let toggle = find(app, "moreReaderToggle")
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertFalse(toggle.isEnabled, "new page / start page → Reader disabled")
        XCTAssertFalse(toggle.isSelected)
        XCTAssertTrue(find(app, "moreMenuPanel").exists, "morph panel open")
        closeMenu(app)
    }

    /// The ⋯ panel follows a vertical drag: an upward one springs back (rubber band), a downward
    /// one collapses it back into the button.
    func testMenuPanelSwipeUpSpringsBackAndSwipeDownCollapses() throws {
        let app = launchBrowser(testPage: false)
        let more = app.buttons["browseMore"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()
        let panel = find(app, "moreMenuPanel")
        XCTAssertTrue(panel.waitForExistence(timeout: 3))
        let open = try XCTUnwrap(settledFrames([panel])?.first, "morph finished")

        panel.swipeUp()
        XCTAssertNotNil(settledFrames([panel]), "the panel comes to rest")
        XCTAssertTrue(panel.exists, "an upward drag doesn't close the menu")
        XCTAssertEqual(panel.frame.minY, open.minY, accuracy: 1, "…and the panel springs back")

        panel.swipeDown()
        XCTAssertTrue(eventually { !panel.exists }, "swipe down collapses the menu")
        more.tap()
        XCTAssertTrue(panel.waitForExistence(timeout: 3), "⋯ is back and opens the menu again")
    }

    func testReaderIconAndReaderToggle() throws {
        let app = launchBrowser(testPage: true)
        let link = app.links["Next page"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        // Page one isn't readable: the ⋯ Reader toggle is disabled.
        app.buttons["browseMore"].tap()
        let toggle = find(app, "moreReaderToggle")
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertFalse(toggle.isEnabled, "not readable → disabled")
        closeMenu(app)
        XCTAssertTrue(eventually { !toggle.exists })

        link.tap()
        let icon = find(app, "addressReader")
        XCTAssertTrue(icon.waitForExistence(timeout: 5))
        icon.tap()
        let close = app.buttons["readerClose"]
        XCTAssertTrue(close.waitForExistence(timeout: 10), "reader icon opens the reader")
        XCTAssertEqual(close.label, "Back to Browser", "opened over the page")
        close.tap()
        XCTAssertTrue(eventually { !close.exists })

        // ⋯ → Reader (bottom-right) switches into reader mode…
        let browseMoreFrame = app.buttons["browseMore"].frame
        app.buttons["browseMore"].tap()
        XCTAssertTrue(eventually { toggle.exists && toggle.isEnabled }, "readable → enabled")
        XCTAssertFalse(toggle.isSelected)
        toggle.tap()
        XCTAssertTrue(close.waitForExistence(timeout: 10), "⋯ → Reader opens the reader")

        let website = find(app, "moreWebsite")
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
        for id in ["moreSettings", "moreSave", "moreFavorite", "moreShare",
                   "moreFavorites", "moreHistory"] {
            XCTAssertTrue(find(app, id).exists, "reader ⋯ has \(id)")
        }
        XCTAssertFalse(find(app, "moreNewSearch").exists, "browser-only rows stay out of the reader menu")
        XCTAssertFalse(find(app, "moreReload").exists)

        // Settings opens as a sheet.
        find(app, "moreSettings").tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5), "Settings sheet")
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(eventually { !app.navigationBars["Settings"].exists })

        // Add the page to Favorites from the reader (wait for the morph to finish growing before tapping
        // a row: mid-animation the rows are still scaled toward the ⋯ button).
        readerMore.tap()
        XCTAssertTrue(website.waitForExistence(timeout: 3))
        tapMenuRow(app, "moreFavorite")
        XCTAssertTrue(eventually { !website.exists }, "panel closes")
        readerMore.tap()
        XCTAssertTrue(eventually { find(app, "moreFavorite").exists && find(app, "moreFavorite").label == "Remove from Favorites" }, "a favorite from the reader")

        // Website → back to the web page (already loaded: revealed, not reloaded).
        tapMenuRow(app, "moreWebsite")
        XCTAssertTrue(eventually { !close.exists }, "Website leaves reader mode")
        XCTAssertTrue(app.buttons["browseMore"].waitForExistence(timeout: 5), "web page chrome is back")
        XCTAssertTrue(app.staticTexts["Second page"].exists, "same page")
    }

    func testReaderMenuInLibraryReader() throws {
        let app = launch(["-seedDemoArticle", "-openLibrary"])
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
        XCTAssertTrue(find(app, "moreWebsite").waitForExistence(timeout: 3))
        XCTAssertFalse(find(app, "moreReaderToggle").exists)
        assertMenuAligned(app, more: moreFrame, button: "moreWebsite")

        // ⋯ → History from the library reader: the library closes, History opens.
        closeMenu(app)
        readerMore.tap()
        find(app, "moreHistory").tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 8), "history sheet")
        XCTAssertFalse(app.libraryHome.exists, "library closed first")
    }

    /// The library's ⋯ is its own menu: nothing in it acts on the page hidden under the library.
    func testLibraryMenuLeavesThePageAlone() throws {
        let app = launchBrowser(testPage: true)
        XCTAssertTrue(app.links["Next page"].waitForExistence(timeout: 10))
        app.buttons["browseLibrary"].tap()
        XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 5), "library surface")

        let libraryMore = app.buttons["libraryMore"]
        let moreFrame = libraryMore.frame
        libraryMore.tap()
        assertMenuAligned(app, more: moreFrame, button: "moreBrowser")
        for id in ["moreSettings", "moreNewFolder", "moreFavorites", "moreHistory", "moreBrowser"] {
            XCTAssertTrue(find(app, id).exists, "library ⋯ has \(id)")
        }
        for id in ["moreNewSearch", "moreReload", "moreSave", "moreFavorite", "moreShare", "moreReaderToggle", "moreLibrary"] {
            XCTAssertFalse(find(app, id).exists, "page actions stay out of the library menu: \(id)")
        }

        // History leaves the library first; the page underneath is still there.
        find(app, "moreHistory").tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5), "history sheet")
        XCTAssertFalse(app.libraryHome.exists, "library closed first")
        app.navigationBars["History"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.99)))
        XCTAssertTrue(eventually { !app.navigationBars["History"].exists })
        XCTAssertTrue(app.links["Next page"].exists, "same page")

        // Browser (big button) returns to the page as it was.
        app.buttons["browseLibrary"].tap()
        XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 5))
        libraryMore.tap()
        tapMenuRow(app, "moreBrowser")
        XCTAssertTrue(eventually { !app.libraryHome.exists }, "library left")
        XCTAssertTrue(app.links["Next page"].exists, "page kept")
        XCTAssertEqual(app.textFields["addressField"].value as? String, "pages/one")
    }

    /// Open a saved article, Listen (the Reader turns into Now Playing), ⋯ → Website: Now Playing and
    /// the library close, the browser loads the article's page, and the voice keeps going (the bar).
    func testSavedArticleWebsiteOpensPageAndKeepsPlaying() throws {
        let app = launch(["-seedDemoArticle", "-openLibrary"])
        let row = app.cells.staticTexts["Demo Listen Article"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let close = app.buttons["readerClose"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))

        let play = app.buttons["listenPlayPause"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()
        XCTAssertTrue(eventually(8) { play.exists && play.label == "Pause" }, "playing")

        app.buttons["nowPlayingMore"].tap()
        tapMenuRow(app, "moreWebsite")

        // Listen turned the Reader into Now Playing; Website takes it down.
        XCTAssertTrue(eventually(8) { !app.buttons["nowPlayingClose"].exists }, "Now Playing closed")
        XCTAssertTrue(eventually(8) { !app.libraryHome.exists }, "library closed")
        let field = app.textFields["addressField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(eventually(8) { field.exists && (field.value as? String)?.contains("example.com/demo") == true }, "the article's page is loading")
        let mini = app.buttons["nowPlayingBarPlayPause"]
        XCTAssertTrue(mini.waitForExistence(timeout: 5), "the Now Playing bar shows")
        XCTAssertEqual(mini.label, "Pause", "the voice keeps playing")
        idle(1.5) // the load doesn't stop it
        XCTAssertEqual(mini.label, "Pause", "…and is still playing")
        mini.tap()
    }

    func testFavoriteShowsOnStartPageAndDeletes() throws {
        let app = launchBrowser(testPage: true)
        XCTAssertTrue(app.links["Next page"].waitForExistence(timeout: 10))
        app.buttons["browseMore"].tap()
        let favorite = find(app, "moreFavorite")
        XCTAssertTrue(favorite.waitForExistence(timeout: 3))
        XCTAssertEqual(favorite.label, "Add to Favorites")
        favorite.tap()
        XCTAssertTrue(eventually { !favorite.exists }, "panel closes")

        app.buttons["browseMore"].tap()
        XCTAssertTrue(eventually { find(app, "moreFavorite").exists && find(app, "moreFavorite").label == "Remove from Favorites" }, "now a favorite")
        find(app, "moreNewSearch").tap() // → start page

        let tile = app.buttons.matching(identifier: "favoriteTile").firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 5), "Favorites grid on the start page")
        XCTAssertEqual(tile.label, "First page")

        // Show All opens the Library's Favorites tab.
        find(app, "startFavoritesShowAll").tap()
        XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Favorites"].isSelected)
        app.buttons["libraryBrowser"].tap()
        XCTAssertTrue(find(app, "browseStartPage").waitForExistence(timeout: 5))

        // Long-press → Remove from Favorites on the start page.
        tile.press(forDuration: 1.0)
        let delete = app.buttons["Remove from Favorites"]
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        delete.tap()
        XCTAssertTrue(eventually { !tile.exists }, "deleted")
    }

    func testCancelButtonRestoresAddress() throws {
        let app = launchBrowser(testPage: true)
        let field = app.textFields["addressField"]
        XCTAssertTrue(app.links["Next page"].waitForExistence(timeout: 10))
        XCTAssertTrue(eventually { field.exists && field.value as? String == "pages/one" }, "shows the page address")

        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let cancel = app.buttons["addressCancel"]
        XCTAssertTrue(cancel.exists, "✕ while editing")
        XCTAssertFalse(app.buttons["browseBack"].exists, "toolbar steps aside while typing")
        field.typeText("something else")

        cancel.tap()
        XCTAssertTrue(eventually { !app.keyboards.firstMatch.exists }, "keyboard dismissed")
        XCTAssertEqual(field.value as? String, "pages/one", "previous address restored")
        XCTAssertFalse(cancel.exists)
        XCTAssertTrue(app.buttons["browseBack"].waitForExistence(timeout: 3), "toolbar back")
    }

    func testSwipeDownLowersKeyboardKeepsSearch() throws {
        let app = launchBrowser(testPage: true)
        let field = app.textFields["addressField"]
        XCTAssertTrue(app.links["Next page"].waitForExistence(timeout: 10))
        XCTAssertTrue(eventually { field.exists && field.value as? String == "pages/one" })

        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        field.typeText("zzq")
        let backdrop = find(app, "addressEditBackdrop")
        XCTAssertTrue(backdrop.waitForExistence(timeout: 3))
        backdrop.swipeDown()

        // Safari: swipe-down dismisses the keyboard but stays in search mode.
        XCTAssertTrue(eventually { !app.keyboards.firstMatch.exists }, "pull-down dismissed keyboard")
        XCTAssertEqual(field.value as? String, "zzq", "typed text kept")
        let cancel = app.buttons["addressCancel"]
        XCTAssertTrue(cancel.exists, "✕ still shown")
        XCTAssertFalse(app.buttons["browseBack"].exists, "toolbar still stepped aside")

        cancel.tap()
        XCTAssertEqual(field.value as? String, "pages/one", "✕ restores address")
        XCTAssertTrue(app.buttons["browseBack"].waitForExistence(timeout: 3))
    }

    func testSwipeDownLowersKeyboardOnStartPage() throws {
        let app = launchBrowser(testPage: false)
        let field = app.textFields["addressField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        field.typeText("abc")
        find(app, "addressEditBackdrop").swipeDown()
        XCTAssertTrue(eventually { !app.keyboards.firstMatch.exists })
        XCTAssertEqual(field.value as? String, "abc", "typed text kept while still searching")
        XCTAssertTrue(app.buttons["addressCancel"].exists, "✕ still shown")
        app.buttons["addressCancel"].tap()
        XCTAssertNotEqual(field.value as? String, "abc", "✕ exits search")
    }
}
