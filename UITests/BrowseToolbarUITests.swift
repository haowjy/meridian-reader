import XCTest

/// Browser bottom bar: no tab bar, toolbar ‹ › ⋯ (⋯ = Safari-style popover with Bookmarks / Saved /
/// History), the address-field reader icon (readable pages only), site bookmarks, and edit mode
/// that cancels via ✕ or a pull-down (restoring the page address).
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

    /// Nav H: with the menu open, the bottom-right button's icon (Reader / Website) sits exactly
    /// where the ⋯ glyph was. `moreMenuFocus` (-uiTesting only) is that icon's measured center.
    private func assertMenuAligned(_ app: XCUIApplication, more moreFrame: CGRect, button id: String,
                                   file: StaticString = #filePath, line: UInt = #line) {
        let focus = element(app, "moreMenuFocus")
        XCTAssertTrue(focus.waitForExistence(timeout: 3), "focus marker", file: file, line: line)
        RunLoop.current.run(until: Date().addingTimeInterval(1.0)) // morph finished
        let f = center(focus.frame), m = center(moreFrame)
        XCTAssertEqual(f.x, m.x, accuracy: 1, "icon x == ⋯ x", file: file, line: line)
        XCTAssertEqual(f.y, m.y, accuracy: 1, "icon y == ⋯ y", file: file, line: line)
        XCTAssertEqual(element(app, id).frame.midX, m.x, accuracy: 1, "\(id) centered on ⋯", file: file, line: line)
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
        XCTAssertFalse(element(app, "browseSaved").exists, "Saved moved into ⋯ (Safari-style)")
        XCTAssertFalse(element(app, "browseReader").exists, "Reader moved into the address field / ⋯")
        XCTAssertTrue(element(app, "addressMic").exists, "mic in the address field")
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

        // Five-slot grid (Nav I): Search in the middle slot (3 of 5), ⋯ in slot 5.
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
        XCTAssertTrue(element(app, "addressCancel").exists)
        element(app, "addressCancel").tap()
        XCTAssertTrue(waitFor("hasKeyboardFocus == false", field))
        XCTAssertTrue(back.isEnabled, "still on the same page")

        // ⋯ popover: action rows, then the big Saved / History buttons.
        let browseMoreFrame = app.buttons["browseMore"].frame
        app.buttons["browseMore"].tap()
        assertMenuAligned(app, more: browseMoreFrame, button: "moreReaderToggle")
        for id in ["moreNewSearch", "moreSave", "moreBookmark", "moreShare", "moreReload",
                   "moreVoice", "moreDebug", "moreBookmarks", "moreLibrary", "moreHistory", "moreReaderToggle"] {
            XCTAssertTrue(element(app, id).waitForExistence(timeout: 3), "⋯ has \(id)")
        }
        XCTAssertFalse(element(app, "moreReader").exists, "the Open in Reader row is gone (bottom-right toggle)")
        XCTAssertTrue(element(app, "moreMenuPanel").exists, "Safari-style panel (no popover arrow)")
        element(app, "moreReload").tap()
        XCTAssertTrue(waitFor("exists == false", element(app, "moreReload")), "popover closes")

        // Saved → the library sheet; swipe down returns to the same page.
        app.buttons["browseMore"].tap()
        element(app, "moreLibrary").tap()
        XCTAssertTrue(app.navigationBars["Saved"].waitForExistence(timeout: 5), "library sheet")
        app.navigationBars["Saved"].swipeDown(velocity: .fast)
        XCTAssertTrue(waitFor("exists == false", app.navigationBars["Saved"]), "swipe down dismisses")
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
        // …where ⋯ sits in the listen bar's bottom-right (no gear) and shows the same popover.
        XCTAssertFalse(app.buttons["listenQuickSettings"].exists, "gear replaced by ⋯")
        let readerMore = app.buttons["readerMore"]
        XCTAssertTrue(readerMore.waitForExistence(timeout: 5))
        // Nav G: the reader's bottom chrome is the browser's; ⋯ sits in exactly the same cell.
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
        for id in ["moreVoice", "moreSave", "moreBookmark", "moreShare", "moreDebug",
                   "moreBookmarks", "moreLibrary", "moreHistory"] {
            XCTAssertTrue(element(app, id).exists, "reader ⋯ has \(id)")
        }
        XCTAssertFalse(element(app, "moreNewSearch").exists, "browser-only rows stay out of the reader menu")
        XCTAssertFalse(element(app, "moreReload").exists)

        // Voice settings (what the gear held) opens as a sheet.
        element(app, "moreVoice").tap()
        XCTAssertTrue(app.navigationBars["Listen"].waitForExistence(timeout: 5), "voice settings sheet")
        app.navigationBars["Listen"].buttons["Done"].tap()
        XCTAssertTrue(waitFor("exists == false", app.navigationBars["Listen"]))

        // Bookmark the site from the reader (wait for the morph to finish growing before tapping
        // a row: mid-animation the rows are still scaled toward the ⋯ button).
        readerMore.tap()
        XCTAssertTrue(website.waitForExistence(timeout: 3))
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        element(app, "moreBookmark").tap()
        XCTAssertTrue(waitFor("exists == false", website), "popover closes")
        readerMore.tap()
        XCTAssertTrue(waitFor("label == 'Remove Bookmark'", element(app, "moreBookmark")), "bookmarked from the reader")

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
        XCTAssertFalse(app.navigationBars["Saved"].exists, "library sheet closed first")
    }

    /// Nav H: open a saved article directly, play, ⋯ → Website: the library closes, the browser
    /// loads the article's page, and the voice keeps going (mini player).
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
        XCTAssertTrue(waitFor("exists == false", app.navigationBars["Saved"], timeout: 8), "library closed")
        let field = app.textFields["addressField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(waitFor("value CONTAINS 'example.com/demo'", field, timeout: 8), "the article's page is loading")
        let mini = app.buttons["miniPlayerPlayPause"]
        XCTAssertTrue(mini.waitForExistence(timeout: 5), "mini player shows")
        XCTAssertEqual(mini.label, "Pause", "the voice keeps playing")
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        XCTAssertEqual(mini.label, "Pause", "…and is still playing")
        mini.tap()
    }

    func testBookmarkShowsOnStartPageAndDeletes() throws {
        let app = launch(testPage: true)
        XCTAssertTrue(app.links["Next page"].waitForExistence(timeout: 10))
        app.buttons["browseMore"].tap()
        let bookmark = element(app, "moreBookmark")
        XCTAssertTrue(bookmark.waitForExistence(timeout: 3))
        XCTAssertEqual(bookmark.label, "Bookmark")
        bookmark.tap()
        XCTAssertTrue(waitFor("exists == false", bookmark), "popover closes")

        app.buttons["browseMore"].tap()
        XCTAssertTrue(waitFor("label == 'Remove Bookmark'", element(app, "moreBookmark")), "now bookmarked")
        element(app, "moreNewSearch").tap() // → start page

        let tile = app.buttons.matching(identifier: "bookmarkTile").firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 5), "bookmark grid on the start page")
        XCTAssertEqual(tile.label, "First page")

        // Bookmarks list from the grid's Show All.
        element(app, "startBookmarksShowAll").tap()
        XCTAssertTrue(app.navigationBars["Bookmarks"].waitForExistence(timeout: 5))
        let bar = app.navigationBars["Bookmarks"]
        bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.99)))
        XCTAssertTrue(waitFor("exists == false", app.navigationBars["Bookmarks"]))

        // Long-press → Delete.
        tile.press(forDuration: 1.0)
        let delete = app.buttons["Delete"]
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

    func testSwipeDownCancelsEditing() throws {
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

        XCTAssertTrue(waitFor("exists == false", app.keyboards.firstMatch), "pull-down dismissed editing")
        XCTAssertEqual(field.value as? String, "pages/one", "previous address restored")
        XCTAssertTrue(app.buttons["browseBack"].waitForExistence(timeout: 3))
    }

    func testSwipeDownCancelsOnStartPage() throws {
        let app = launch(testPage: false)
        let field = app.textFields["addressField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        field.typeText("abc")
        element(app, "addressEditBackdrop").swipeDown()
        XCTAssertTrue(waitFor("exists == false", app.keyboards.firstMatch))
        XCTAssertNotEqual(field.value as? String, "abc", "typed text discarded")
    }
}
