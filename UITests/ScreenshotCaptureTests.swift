import XCTest

/// Screenshots for design review, not assertions about layout (the other UI tests do that).
/// Skipped unless a directory is given in xcodebuild's environment:
///
///     TEST_RUNNER_READER_SCREENSHOTS_DIR=/tmp/reader-shots \
///         xcodebuild test … -only-testing:MeridianReaderUITests/ScreenshotCaptureTests
///
/// Each PNG goes to `<dir>/<test>/<name>.png` and is also attached to the test result. The
/// offline captures use the `reader-test://` pages and the demo article; `testBrowseBar` needs the
/// network (a Wikipedia page, Google suggestions), `testBufferedFill` needs the Kokoro model
/// installed in the Simulator.
final class ScreenshotCaptureTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        guard let path = ProcessInfo.processInfo.environment["READER_SCREENSHOTS_DIR"], !path.isEmpty else {
            throw XCTSkip("Set TEST_RUNNER_READER_SCREENSHOTS_DIR=<dir> to capture screenshots.")
        }
        let test = name.split(separator: " ").last.map { String($0.dropLast()) } ?? "capture"
        dir = URL(fileURLWithPath: path).appendingPathComponent(test)
        continueAfterFailure = true
    }

    private func shot(_ name: String) throws {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try screenshot.pngRepresentation.write(to: dir.appendingPathComponent(name + ".png"))
    }

    /// Offline page two (an article): the page with its reader icon showing.
    private func openTestArticlePage(_ app: XCUIApplication) {
        let link = app.links["Next page"]
        XCTAssertTrue(link.waitForExistence(timeout: 30))
        link.tap()
        XCTAssertTrue(find(app, "addressReader").waitForExistence(timeout: 5))
        idle(1)
    }

    // MARK: - Offline

    /// Toolbars and ⋯ menus on a page and in its Reader (developer options off), the Reader
    /// scrolled mid-article, Settings down to the version row, and the Now Playing bar.
    func testMenusOnPageAndInReader() throws {
        let app = launch(["-browseTestPages", "-reader.developerOptions", "NO"])
        openTestArticlePage(app)
        try shot("1-browse-toolbar")
        app.buttons["browseMore"].tap()
        idle(1.5)
        try shot("2-browse-menu")
        closeMenu(app)

        find(app, "addressReader").tap()
        XCTAssertTrue(app.buttons["readerClose"].waitForExistence(timeout: 10))
        idle(1.5)
        try shot("3-reader-toolbar")
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -300)),
                   withVelocity: .slow, thenHoldForDuration: 0.1)
        idle(1.2)
        try shot("4-reader-scrolled")
        app.buttons["readerMore"].tap()
        idle(1.5)
        try shot("5-reader-menu")

        find(app, "moreSettings").tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        idle(1)
        try shot("6-settings")
        for _ in 0..<10 where !find(app, "settingsVersionRow").isHittable { app.swipeUp() }
        idle(0.8)
        try shot("7-settings-version")
        app.buttons["settingsDone"].tap()
        idle(1)

        app.buttons["listenPlayPause"].tap() // Listen: the Reader turns into Now Playing
        idle(2)
        app.buttons["nowPlayingClose"].tap() // ⌄
        idle(1.5)
        try shot("8-browse-now-playing-bar")
        app.buttons["nowPlayingBarPlayPause"].tap()
    }

    /// The ⋯ morph closed / mid-animation / open, slowed to 3 s (`-slowMenuAnimation`), on the
    /// start page (Reader disabled), on a page, and in the reader.
    func testMenuMorph() throws {
        let morph: TimeInterval = 3
        let app = launch(["-browseTestPages", "-slowMenuAnimation"])
        func sequence(button: String, prefix: String) throws {
            try shot("\(prefix)-closed")
            app.buttons[button].tap()
            idle(0.9)
            try shot("\(prefix)-mid-animation")
            idle(morph)
            XCTAssertTrue(find(app, "moreMenuPanel").exists)
            try shot("\(prefix)-open")
        }

        XCTAssertTrue(app.links["Next page"].waitForExistence(timeout: 10))
        app.buttons["browseMore"].tap()
        idle(morph + 0.6)
        XCTAssertFalse(find(app, "moreReaderToggle").isEnabled, "page one isn't readable")
        try shot("non-article-open")
        closeMenu(app)

        openTestArticlePage(app)
        try sequence(button: "browseMore", prefix: "browse")
        find(app, "moreReaderToggle").tap()
        XCTAssertTrue(app.buttons["readerClose"].waitForExistence(timeout: 10))
        idle(morph + 1)
        try sequence(button: "readerMore", prefix: "reader")
    }

    /// The Reader sheet and Now Playing side by side (D24: one top bar, 🔖 and ⋯ in the same
    /// slots): the Reader, its ☝︎ on, then Listen: Now Playing paused, its ☝︎ on, the speed list and
    /// the ⋯ menu.
    func testReaderAndNowPlayingSheets() throws {
        let app = launch(["-seedDemoArticle", "-seedDemoParagraphs", "12", "-openLibrary"])
        let row = app.cells.staticTexts["Demo Listen Article"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let play = app.buttons["listenPlayPause"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        idle(1.5)
        try shot("1-reader")
        app.buttons["listenJump"].tap()
        idle(1)
        try shot("2-reader-jump-on")
        app.buttons["listenJump"].tap()
        idle(0.6)

        play.tap() // Listen: the Reader turns into Now Playing
        XCTAssertTrue(find(app, "nowPlayingHeader").waitForExistence(timeout: 5))
        XCTAssertTrue(eventually(8) { play.label == "Pause" })
        play.tap()
        XCTAssertTrue(eventually(5) { play.label == "Play" })
        idle(1.5)
        try shot("3-now-playing")
        app.buttons["listenJump"].tap()
        idle(1)
        try shot("4-now-playing-jump-on")
        app.buttons["listenJump"].tap()
        idle(0.6)
        app.buttons["listenSpeed"].tap()
        idle(1.2)
        try shot("5-now-playing-speed")
        find(app, "listenSpeedOption-1×").tap()
        idle(0.8)
        app.buttons["nowPlayingMore"].tap()
        idle(1.5)
        try shot("6-now-playing-menu")
        closeMenu(app)
    }

    /// The scrub bubble frozen mid fine-scrub (`-scrubBubbleDemo`), on Now Playing (paused).
    func testScrubBubble() throws {
        let app = launch(["-seedDemoArticle", "-seedDemoParagraphs", "12", "-openLibrary",
                          "-scrubBubbleDemo"])
        let row = app.cells.staticTexts["Demo Listen Article"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let play = app.buttons["listenPlayPause"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()
        idle(1)
        play.tap()
        idle(2.5)
        try shot("scrub-bubble-fine")
    }

    /// The two states (the screenshot that started the redesign): article A playing while the
    /// browser shows page B; then B's Reader with A in the bar, Now Playing, and A's page with its
    /// 🎧 playing. Offline test pages.
    func testTwoStates() throws {
        let app = launch(["-browseTestPages", "-reader.developerOptions", "NO"])
        openTestArticlePage(app) // A: page two
        find(app, "addressListen").tap()
        idle(3)
        try shot("1-a-playing-on-its-page")
        app.buttons["browseBack"].tap()
        let third = app.links["Third page"]
        XCTAssertTrue(third.waitForExistence(timeout: 10))
        third.tap()
        XCTAssertTrue(find(app, "addressListen").waitForExistence(timeout: 10))
        idle(1.5)
        try shot("2-browsing-b-while-a-plays")
        find(app, "addressReader").tap()
        XCTAssertTrue(app.buttons["readerClose"].waitForExistence(timeout: 10))
        idle(1.5)
        try shot("3-reader-b-while-a-plays")
        find(app, "nowPlayingBarOpen").tap()
        XCTAssertTrue(find(app, "nowPlayingHeader").waitForExistence(timeout: 5))
        idle(2)
        try shot("4-now-playing-a")
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -200)),
                   withVelocity: .slow, thenHoldForDuration: 0.1)
        idle(1)
        try shot("5-now-playing-scrolled-back-to-audio")
        // B's Reader (with its own Listen) is still under Now Playing: pause by Now Playing's label.
        app.buttons.matching(identifier: "listenPlayPause").matching(NSPredicate(format: "label == 'Pause'"))
            .firstMatch.tap()
    }

    /// The start page, the ⋯ menu, Favorites, the Library and its Reader, the Now Playing bar on
    /// the Library and on the start page, and Now Playing. Offline: the demo article and the seeded
    /// favorites (`example.com` links whose icons stay letter tiles: nothing is fetched).
    func testBrowserSurfaces() throws {
        let app = launch(["-seedBookmarks", "-seedDemoArticle", "-seedDemoParagraphs", "12"])
        idle(2)
        try shot("start")

        app.buttons["browseMore"].tap()
        idle(1.2)
        try shot("menu")
        find(app, "moreFavorites").tap()
        XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 5))
        idle(1)
        try shot("favorites")

        app.buttons["Everything"].tap() // Favorites is the Library's filter; back to all of it
        XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 5))
        idle(1.2)
        try shot("library")
        app.cells.staticTexts["Demo Listen Article"].tap()
        XCTAssertTrue(app.buttons["readerClose"].waitForExistence(timeout: 10))
        idle(2)
        try shot("library-reader")

        let play = app.buttons["listenPlayPause"]
        play.tap() // Listen: Now Playing
        XCTAssertTrue(find(app, "nowPlayingHeader").waitForExistence(timeout: 5))
        idle(2.5)
        try shot("now-playing")
        app.buttons["nowPlayingClose"].tap() // ⌄
        XCTAssertTrue(find(app, "nowPlayingBar").waitForExistence(timeout: 5))
        idle(1)
        try shot("library-now-playing-bar")
        app.buttons["libraryBrowser"].tap()
        XCTAssertTrue(find(app, "nowPlayingBar").waitForExistence(timeout: 5))
        idle(1.5)
        try shot("start-now-playing-bar")
        app.buttons["nowPlayingBarPlayPause"].tap()
    }

    /// The Library home, a folder (and its ⋯, Edit, the Move tree), a book, and the start page's
    /// Favorites. Offline: the demo article, book and folders, and the seeded favorites.
    func testLibrarySurfaces() throws {
        let app = launch(["-seedDemoArticle", "-seedDemoBook", "-seedDemoFolders", "-seedBookmarks", "-openLibrary",
                          "-reader.developerOptions", "NO"])
        XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 10))
        idle(1.5)
        try shot("1-library-home")

        row(app, "Demo Finance").tap()
        XCTAssertTrue(find(app, "folderScreen").waitForExistence(timeout: 5))
        idle(1.2)
        try shot("2-folder")
        app.buttons["libraryMore"].tap()
        idle(1.2)
        try shot("3-folder-menu")
        closeMenu(app)
        find(app, "folderEdit").tap()
        idle(0.8)
        row(app, "Index Funds").tap()
        idle(0.6)
        try shot("4-folder-edit")
        find(app, "editMove").tap()
        XCTAssertTrue(find(app, "moveTree").waitForExistence(timeout: 5))
        idle(1.2)
        try shot("5-move-tree")
        find(app, "moveCancel").tap()
        idle(0.8)
        find(app, "folderEdit").tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        idle(1)

        row(app, "The Demo Book").tap()
        XCTAssertTrue(find(app, "folderScreen").waitForExistence(timeout: 5))
        idle(1.2)
        try shot("6-book")
        find(app, "folderContinue").tap()
        XCTAssertTrue(find(app, "nowPlayingBar").waitForExistence(timeout: 10))
        idle(1.5)
        try shot("7-book-playing")
        app.buttons["nowPlayingBarPlayPause"].tap()
        app.buttons["libraryMore"].tap()
        idle(1.2)
        try shot("8-book-menu")
        closeMenu(app)

        app.buttons["libraryBrowser"].tap()
        XCTAssertTrue(find(app, "startFavorites").waitForExistence(timeout: 5))
        idle(1)
        try shot("9-start-page-favorites")

        app.buttons["browseMore"].tap()
        let favorites = find(app, "moreFavorites")
        XCTAssertTrue(favorites.waitForExistence(timeout: 3))
        idle(0.6)
        favorites.tap()
        XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 5))
        idle(1.2)
        try shot("10-favorites-tab")
        app.buttons["libraryMore"].tap()
        idle(1.2)
        try shot("11-favorites-tab-menu")
    }

    /// A book part-way (its bar, the percent and time left under it, Continue and Play from Start,
    /// the Chapters card) and a folder part-way, light and at the largest accessibility text size:
    /// every block on the page margin.
    /// The band the browser and the Library share (D22): the same frame on both, with the bar
    /// showing the page played last, paused.
    func testSharedBand() throws {
        let app = launch(["-seedDemoArticle", "-browseTestPages"])
        XCTAssertTrue(find(app, "bandField").waitForExistence(timeout: 30))
        try shot("chrome-browse-first-page")
        openTestArticlePage(app)
        idle(1)
        try shot("chrome-browse")
        app.buttons["browseLibrary"].tap()
        XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 5))
        idle(1.5)
        try shot("chrome-library")
    }

    func testBookAndFolderHeaders() throws {
        for (suffix, size) in [("", nil), ("-ax5", "UICTContentSizeCategoryAccessibilityXXXL")] as [(String, String?)] {
            var arguments = ["-seedDemoBook", "-seedDemoBookPlace", "2", "-seedDemoFolders",
                             "-openLibrary", "-reader.developerOptions", "NO"]
            if let size { arguments += ["-UIPreferredContentSizeCategoryName", size] }
            let app = launch(UITestSetup(arguments))
            XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 10))
            row(app, "The Demo Book").tap()
            XCTAssertTrue(find(app, "folderScreen").waitForExistence(timeout: 5))
            idle(1.2)
            try shot("1-book-part-way\(suffix)")
            if size != nil {
                app.swipeUp()
                idle(1)
                try shot("1b-book-buttons\(suffix)")
            }
            app.navigationBars.buttons.element(boundBy: 0).tap()
            idle(1)
            row(app, "Demo Finance").tap()
            XCTAssertTrue(find(app, "folderScreen").waitForExistence(timeout: 5))
            idle(1.2)
            try shot("2-folder-part-way\(suffix)")
            app.terminate()
        }
    }

    /// Downloads (decision D16) with the offline test voice: the book's ⋯ with *Download Book*,
    /// the progress line on the bottom chrome (with its toast, then alone), the Downloads list
    /// while it renders and once done, the Downloaded marks on the chapters and the book's row, after a voice change (Different Voice), and the Reader's ⋯
    /// with *Download*.
    func testDownloads() throws {
        let app = launch(UITestSetup(["-seedDemoBook", "-seedDemoFolders", "-testVoice", "-testVoiceDelay", "0.5",
                                      "-openLibrary", "-reader.developerOptions", "NO"], engine: "test.voice"))
        XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 10))
        row(app, "The Demo Book").tap()
        XCTAssertTrue(find(app, "folderScreen").waitForExistence(timeout: 5))
        app.buttons["libraryMore"].tap()
        idle(1.2)
        try shot("1-book-menu")
        find(app, "moreDownload").tap()
        idle(1.5)
        try shot("2-progress-line-and-toast")
        idle(4)
        try shot("3-progress-line")
        app.buttons["libraryMore"].tap()
        idle(1.2)
        find(app, "moreDownloads").tap()
        XCTAssertTrue(find(app, "downloadsSheet").waitForExistence(timeout: 5))
        idle(1.2)
        try shot("4-downloads-queued")
        XCTAssertTrue(find(app, "downloadsDoneHeader").waitForExistence(timeout: 90))
        idle(1.5)
        try shot("5-downloads-done")
        find(app, "downloadsDone").tap()
        idle(1)
        try shot("5b-book-downloaded")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        idle(1)
        try shot("5c-home-downloaded")
        app.buttons["libraryMore"].tap()
        idle(1.2)
        try shot("6-home-menu")
        find(app, "moreSettings").tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        openSettingsRow(app, "settingsVoice")
        let two = find(app, "voiceRow-two")
        for _ in 0..<6 where !(two.exists && two.isHittable) { app.swipeUp() }
        two.tap()
        idle(1)
        app.navigationBars["Voice"].buttons.firstMatch.tap()
        app.buttons["settingsDone"].tap()
        idle(1)
        app.buttons["libraryMore"].tap()
        idle(1.2)
        find(app, "moreDownloads").tap()
        XCTAssertTrue(find(app, "downloadsDifferentVoiceHeader").waitForExistence(timeout: 5))
        idle(1.2)
        try shot("7-downloads-different-voice")
        find(app, "downloadsDone").tap()
        idle(1)

        row(app, "Demo Loose Page").tap()
        XCTAssertTrue(app.buttons["readerMore"].waitForExistence(timeout: 10))
        idle(1)
        app.buttons["readerMore"].tap()
        idle(1.2)
        try shot("8-reader-menu")
    }

    /// Importing a book (`-importTestEPUB`): the Library's ⋯ and ＋ with *Import Book…*, the import
    /// sheet for a book downloaded from page one's link (medium and large), its *Add to* tree,
    /// the book it lands on, and D13's question when it's imported again.
    func testBookImport() throws {
        let app = launch(["-browseTestPages", "-seedDemoFolders", "-importTestEPUB",
                          "-reader.developerOptions", "NO"])
        let link = app.links["Download a book"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        app.buttons["browseLibrary"].tap()
        XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 5))
        idle(1)
        app.buttons["libraryMore"].tap()
        idle(1.2)
        try shot("1-library-menu")
        closeMenu(app)
        app.buttons["libraryAdd"].tap()
        idle(1)
        try shot("2-add-menu")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        idle(0.6)
        app.buttons["libraryBrowser"].tap()

        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        XCTAssertTrue(find(app, "importSheet").waitForExistence(timeout: 15))
        idle(1.5)
        try shot("3-import-sheet")
        find(app, "importHeader").swipeUp()
        idle(1)
        try shot("4-import-sheet-large")
        find(app, "importChange").tap()
        XCTAssertTrue(find(app, "importAddToTree").waitForExistence(timeout: 5))
        idle(1)
        try shot("5-import-add-to")
        app.buttons.matching(identifier: "moveFolder").matching(NSPredicate(format: "label == %@", "Demo Finance")).firstMatch.tap()
        idle(1)
        try shot("6-import-sheet-changed")
        find(app, "importStart").tap()
        XCTAssertTrue(find(app, "folderScreen").waitForExistence(timeout: 30))
        idle(1.2)
        try shot("7-landed-book")

        app.buttons["libraryAdd"].tap()
        let item = app.buttons["libraryImportBook"]
        XCTAssertTrue(item.waitForExistence(timeout: 3))
        item.tap()
        let ask = app.alerts.firstMatch
        XCTAssertTrue(ask.waitForExistence(timeout: 30))
        idle(1)
        try shot("8-already-in-library")
        ask.buttons["Cancel"].firstMatch.tap()
    }

    /// A row in a Library list, by its title.
    private func row(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.cells.staticTexts.matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    // MARK: - Network or installed models

    /// The address bar idle on a page, editing with Recent Searches, editing with Google
    /// suggestions (this test turns them on: no `-uiTesting`), and the ⋯ menu.
    func testBrowseBar() throws {
        let app = launch(UITestSetup(usesNetwork: true))
        let field = app.textFields["addressField"]
        func open(_ text: String) {
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            idle(0.6) // the page address is selected on focus, so typing replaces it
            field.typeText(text + "\n")
            idle(6)
        }
        open("text to speech") // a search → Recent Searches
        open("en.wikipedia.org/wiki/Speech_synthesis")
        try shot("idle")
        field.tap()
        idle(1.2)
        try shot("editing")
        field.typeText("speech")
        idle(2.5)
        try shot("editing-suggestions")
        app.buttons["addressCancel"].tap()
        idle(1)
        app.buttons["browseMore"].tap()
        idle(1.2)
        try shot("menu")
    }

    /// Kokoro rendering ahead of the playhead: the scrubber's lighter buffered fill.
    func testBufferedFill() throws {
        let app = launch(UITestSetup(["-seedDemoArticle", "-seedDemoParagraphs", "12", "-openLibrary"], engine: "local.kokoro"))
        idle(20) // Kokoro load on the Simulator
        let firstRow = app.cells.element(boundBy: 0)
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
        firstRow.staticTexts.element(boundBy: 0).tap()
        let play = app.buttons["listenPlayPause"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        play.tap()
        idle(30) // play + render ahead
        play.tap()
        idle(4)
        try shot("reader-buffered-fill")
    }
}
