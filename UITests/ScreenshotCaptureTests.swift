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

    private func wait(_ s: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-selectEngine", "apple"] + arguments
        app.launch()
        return app
    }

    /// Offline page two (an article): the page with its reader icon showing.
    private func openTestArticlePage(_ app: XCUIApplication) {
        let link = app.links["Next page"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.tap()
        XCTAssertTrue(el(app, "addressReader").waitForExistence(timeout: 5))
        wait(1)
    }

    private func dismissMenu(_ app: XCUIApplication, settle: TimeInterval = 0.8) {
        let dismiss = el(app, "moreMenuDismiss")
        if dismiss.waitForExistence(timeout: 2) {
            tapMenuDim(dismiss)
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        }
        wait(settle)
    }

    // MARK: - Offline

    /// Toolbars and ⋯ menus on a page and in its Reader (developer options off), the Reader
    /// scrolled mid-article, Voice settings down to the version row, and the Now Playing bar.
    func testMenusOnPageAndInReader() throws {
        let app = launch(["-resetBookmarks", "-browseTestPages", "-reader.developerOptions", "NO"])
        openTestArticlePage(app)
        try shot("1-browse-toolbar")
        app.buttons["browseMore"].tap()
        wait(1.5)
        try shot("2-browse-menu")
        dismissMenu(app)

        el(app, "addressReader").tap()
        XCTAssertTrue(app.buttons["readerClose"].waitForExistence(timeout: 10))
        wait(1.5)
        try shot("3-reader-toolbar")
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -300)),
                   withVelocity: .slow, thenHoldForDuration: 0.1)
        wait(1.2)
        try shot("4-reader-scrolled")
        app.buttons["readerMore"].tap()
        wait(1.5)
        try shot("5-reader-menu")

        el(app, "moreVoice").tap()
        XCTAssertTrue(app.navigationBars["Listen"].waitForExistence(timeout: 5))
        wait(1)
        try shot("6-voice-settings")
        for _ in 0..<6 where !el(app, "settingsVersionRow").isHittable { app.swipeUp() }
        wait(0.8)
        try shot("7-voice-settings-version")
        app.navigationBars["Listen"].buttons["Done"].tap()
        wait(1)

        app.buttons["listenPlayPause"].tap() // Listen: the Reader turns into Now Playing
        wait(2)
        app.buttons["readerClose"].tap() // ⌄
        wait(1.5)
        try shot("8-browse-now-playing-bar")
        app.buttons["nowPlayingBarPlayPause"].tap()
    }

    /// The ⋯ morph closed / mid-animation / open, slowed to 3 s (`-slowMenuAnimation`), on the
    /// start page (Reader disabled), on a page, and in the reader.
    func testMenuMorph() throws {
        let morph: TimeInterval = 3
        let app = launch(["-resetBookmarks", "-browseTestPages", "-slowMenuAnimation"])
        func sequence(button: String, prefix: String) throws {
            try shot("\(prefix)-closed")
            app.buttons[button].tap()
            wait(0.9)
            try shot("\(prefix)-mid-animation")
            wait(morph)
            XCTAssertTrue(el(app, "moreMenuPanel").exists)
            try shot("\(prefix)-open")
        }

        XCTAssertTrue(app.links["Next page"].waitForExistence(timeout: 10))
        app.buttons["browseMore"].tap()
        wait(morph + 0.6)
        XCTAssertFalse(el(app, "moreReaderToggle").isEnabled, "page one isn't readable")
        try shot("non-article-open")
        dismissMenu(app, settle: morph + 0.6)

        openTestArticlePage(app)
        try sequence(button: "browseMore", prefix: "browse")
        el(app, "moreReaderToggle").tap()
        XCTAssertTrue(app.buttons["readerClose"].waitForExistence(timeout: 10))
        wait(morph + 1)
        try sequence(button: "readerMore", prefix: "reader")
    }

    /// The scrub bubble frozen mid fine-scrub (`-scrubBubbleDemo`), on Now Playing (paused).
    func testScrubBubble() throws {
        let app = launch(["-seedDemoArticle", "-seedDemoParagraphs", "12", "-openLibrary", "-resetBookmarks",
                          "-scrubBubbleDemo"])
        let row = app.cells.staticTexts["Demo Listen Article"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let play = app.buttons["listenPlayPause"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()
        wait(1)
        play.tap()
        wait(2.5)
        try shot("scrub-bubble-fine")
    }

    /// The two states (the screenshot that started the redesign): article A playing while the
    /// browser shows page B; then B's Reader with A in the bar, Now Playing, and A's page with its
    /// 🎧 playing. Offline test pages.
    func testTwoStates() throws {
        let app = launch(["-resetBookmarks", "-browseTestPages", "-reader.developerOptions", "NO"])
        openTestArticlePage(app) // A: page two
        el(app, "addressListen").tap()
        wait(3)
        try shot("1-a-playing-on-its-page")
        app.buttons["browseBack"].tap()
        let third = app.links["Third page"]
        XCTAssertTrue(third.waitForExistence(timeout: 10))
        third.tap()
        XCTAssertTrue(el(app, "addressListen").waitForExistence(timeout: 10))
        wait(1.5)
        try shot("2-browsing-b-while-a-plays")
        el(app, "addressReader").tap()
        XCTAssertTrue(app.buttons["readerClose"].waitForExistence(timeout: 10))
        wait(1.5)
        try shot("3-reader-b-while-a-plays")
        el(app, "nowPlayingBarOpen").tap()
        XCTAssertTrue(el(app, "nowPlayingFrom").waitForExistence(timeout: 5))
        wait(2)
        try shot("4-now-playing-a")
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -200)),
                   withVelocity: .slow, thenHoldForDuration: 0.1)
        wait(1)
        try shot("5-now-playing-scrolled-back-to-audio")
        // B's Reader (with its own Listen) is still under Now Playing: pause by Now Playing's label.
        app.buttons.matching(identifier: "listenPlayPause").matching(NSPredicate(format: "label == 'Pause'"))
            .firstMatch.tap()
    }

    /// The start page, the ⋯ menu, Favorites, the Library and its Reader, the Now Playing bar on
    /// the Library and on the start page, and Now Playing. Offline: the demo article and the seeded
    /// favorites (their icons are letter tiles without the network).
    func testBrowserSurfaces() throws {
        let app = launch(["-seedBookmarks", "-seedDemoArticle", "-seedDemoParagraphs", "12"])
        wait(2)
        try shot("start")

        app.buttons["browseMore"].tap()
        wait(1.2)
        try shot("menu")
        el(app, "moreFavorites").tap()
        XCTAssertTrue(app.navigationBars["Favorites"].waitForExistence(timeout: 5))
        wait(1)
        try shot("favorites")
        app.navigationBars["Favorites"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.99)))
        wait(1)

        app.buttons["browseLibrary"].tap()
        XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 5))
        wait(1.2)
        try shot("library")
        app.cells.staticTexts["Demo Listen Article"].tap()
        XCTAssertTrue(app.buttons["readerClose"].waitForExistence(timeout: 10))
        wait(2)
        try shot("library-reader")

        let play = app.buttons["listenPlayPause"]
        play.tap() // Listen: Now Playing
        XCTAssertTrue(el(app, "nowPlayingFrom").waitForExistence(timeout: 5))
        wait(2.5)
        try shot("now-playing")
        app.buttons["readerClose"].tap() // ⌄
        XCTAssertTrue(el(app, "nowPlayingBar").waitForExistence(timeout: 5))
        wait(1)
        try shot("library-now-playing-bar")
        app.buttons["libraryBrowser"].tap()
        XCTAssertTrue(el(app, "nowPlayingBar").waitForExistence(timeout: 5))
        wait(1.5)
        try shot("start-now-playing-bar")
        app.buttons["nowPlayingBarPlayPause"].tap()
    }

    /// The Library home, a folder (and its ⋯, Edit, the Move tree), a book, and the start page's
    /// Favorites. Offline: the demo article, book and folders, and the seeded favorites.
    func testLibrarySurfaces() throws {
        let app = launch(["-seedDemoArticle", "-seedDemoBook", "-seedDemoFolders", "-seedBookmarks", "-openLibrary",
                          "-reader.developerOptions", "NO"])
        XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 10))
        wait(1.5)
        try shot("1-library-home")

        row(app, "Demo Finance").tap()
        XCTAssertTrue(el(app, "folderScreen").waitForExistence(timeout: 5))
        wait(1.2)
        try shot("2-folder")
        app.buttons["libraryMore"].tap()
        wait(1.2)
        try shot("3-folder-menu")
        dismissMenu(app)
        el(app, "folderEdit").tap()
        wait(0.8)
        row(app, "Index Funds").tap()
        wait(0.6)
        try shot("4-folder-edit")
        el(app, "editMove").tap()
        XCTAssertTrue(el(app, "moveTree").waitForExistence(timeout: 5))
        wait(1.2)
        try shot("5-move-tree")
        el(app, "moveCancel").tap()
        wait(0.8)
        el(app, "folderEdit").tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        wait(1)

        row(app, "The Demo Book").tap()
        XCTAssertTrue(el(app, "bookScreen").waitForExistence(timeout: 5))
        wait(1.2)
        try shot("6-book")
        el(app, "bookContinue").tap()
        XCTAssertTrue(el(app, "nowPlayingBar").waitForExistence(timeout: 10))
        wait(1.5)
        try shot("7-book-playing")
        app.buttons["nowPlayingBarPlayPause"].tap()
        app.buttons["libraryMore"].tap()
        wait(1.2)
        try shot("8-book-menu")
        dismissMenu(app)

        app.buttons["libraryBrowser"].tap()
        XCTAssertTrue(el(app, "startFavorites").waitForExistence(timeout: 5))
        wait(1)
        try shot("9-start-page-favorites")

        app.buttons["browseMore"].tap()
        let favorites = el(app, "moreFavorites")
        XCTAssertTrue(favorites.waitForExistence(timeout: 3))
        wait(0.6)
        favorites.tap()
        XCTAssertTrue(el(app, "favoritesMore").waitForExistence(timeout: 5))
        wait(1.2)
        try shot("10-favorites-sheet")
        app.buttons["favoritesMore"].tap()
        wait(1.2)
        try shot("11-favorites-sheet-menu")
    }

    /// Downloads (decision D16) with the offline test voice: the book's ⋯ with *Download Book*,
    /// the progress line on the bottom chrome (with its toast, then alone), the Downloads list
    /// while it renders and once done, after a voice change (Different Voice), and the Reader's ⋯
    /// with *Download*.
    func testDownloads() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-seedDemoBook", "-seedDemoFolders", "-resetBookmarks", "-resetDownloads",
                               "-testVoice", "-testVoiceDelay", "0.5", "-selectEngine", "test.voice", "-openLibrary",
                               "-reader.developerOptions", "NO"]
        app.launch()
        XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 10))
        row(app, "The Demo Book").tap()
        XCTAssertTrue(el(app, "bookScreen").waitForExistence(timeout: 5))
        app.buttons["libraryMore"].tap()
        wait(1.2)
        try shot("1-book-menu")
        el(app, "moreDownload").tap()
        wait(1.5)
        try shot("2-progress-line-and-toast")
        wait(4)
        try shot("3-progress-line")
        app.buttons["libraryMore"].tap()
        wait(1.2)
        el(app, "moreDownloads").tap()
        XCTAssertTrue(el(app, "downloadsSheet").waitForExistence(timeout: 5))
        wait(1.2)
        try shot("4-downloads-queued")
        XCTAssertTrue(el(app, "downloadsDoneHeader").waitForExistence(timeout: 90))
        wait(1.5)
        try shot("5-downloads-done")
        el(app, "downloadsDone").tap()
        wait(1)

        app.navigationBars.buttons.element(boundBy: 0).tap()
        wait(1)
        app.buttons["libraryMore"].tap()
        wait(1.2)
        try shot("6-home-menu")
        el(app, "moreVoice").tap()
        XCTAssertTrue(app.navigationBars["Listen"].waitForExistence(timeout: 5))
        let two = el(app, "voiceRow-two")
        for _ in 0..<6 where !(two.exists && two.isHittable) { app.swipeUp() }
        two.tap()
        wait(1)
        app.navigationBars["Listen"].buttons["Done"].tap()
        wait(1)
        app.buttons["libraryMore"].tap()
        wait(1.2)
        el(app, "moreDownloads").tap()
        XCTAssertTrue(el(app, "downloadsDifferentVoiceHeader").waitForExistence(timeout: 5))
        wait(1.2)
        try shot("7-downloads-different-voice")
        el(app, "downloadsDone").tap()
        wait(1)

        row(app, "Demo Loose Page").tap()
        XCTAssertTrue(app.buttons["readerMore"].waitForExistence(timeout: 10))
        wait(1)
        app.buttons["readerMore"].tap()
        wait(1.2)
        try shot("8-reader-menu")
    }

    /// Importing a book (`-importTestEPUB`): the Library's ⋯ and ＋ with *Import Book…*, the import
    /// sheet for a book downloaded from page one's link (medium and large), its *Add to* tree,
    /// the book it lands on, and D13's question when it's imported again.
    func testBookImport() throws {
        let app = launch(["-browseTestPages", "-resetBookmarks", "-seedDemoFolders", "-importTestEPUB",
                          "-reader.developerOptions", "NO"])
        let link = app.links["Download a book"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        app.buttons["browseLibrary"].tap()
        XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 5))
        wait(1)
        app.buttons["libraryMore"].tap()
        wait(1.2)
        try shot("1-library-menu")
        dismissMenu(app)
        app.buttons["libraryAdd"].tap()
        wait(1)
        try shot("2-add-menu")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        wait(0.6)
        app.buttons["libraryBrowser"].tap()

        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        XCTAssertTrue(el(app, "importSheet").waitForExistence(timeout: 15))
        wait(1.5)
        try shot("3-import-sheet")
        el(app, "importHeader").swipeUp()
        wait(1)
        try shot("4-import-sheet-large")
        el(app, "importChange").tap()
        XCTAssertTrue(el(app, "importAddToTree").waitForExistence(timeout: 5))
        wait(1)
        try shot("5-import-add-to")
        app.buttons.matching(identifier: "moveFolder").matching(NSPredicate(format: "label == %@", "Demo Finance")).firstMatch.tap()
        wait(1)
        try shot("6-import-sheet-changed")
        el(app, "importStart").tap()
        XCTAssertTrue(el(app, "bookScreen").waitForExistence(timeout: 30))
        wait(1.2)
        try shot("7-landed-book")

        app.buttons["libraryAdd"].tap()
        let item = app.buttons["libraryImportBook"]
        XCTAssertTrue(item.waitForExistence(timeout: 3))
        item.tap()
        let ask = app.alerts.firstMatch
        XCTAssertTrue(ask.waitForExistence(timeout: 30))
        wait(1)
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
        let app = XCUIApplication()
        app.launch()
        let field = app.textFields["addressField"]
        func open(_ text: String) {
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            wait(0.6) // the page address is selected on focus, so typing replaces it
            field.typeText(text + "\n")
            wait(6)
        }
        open("text to speech") // a search → Recent Searches
        open("en.wikipedia.org/wiki/Speech_synthesis")
        try shot("idle")
        field.tap()
        wait(1.2)
        try shot("editing")
        field.typeText("speech")
        wait(2.5)
        try shot("editing-suggestions")
        app.buttons["addressCancel"].tap()
        wait(1)
        app.buttons["browseMore"].tap()
        wait(1.2)
        try shot("menu")
    }

    /// Kokoro rendering ahead of the playhead: the scrubber's lighter buffered fill.
    func testBufferedFill() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-selectEngine", "local.kokoro", "-openLibrary"]
        app.launch()
        addTeardownBlock {
            let reset = XCUIApplication()
            reset.launchArguments = ["-uiTesting", "-selectEngine", "apple"]
            reset.launch()
            reset.terminate()
        }
        wait(20) // Kokoro load on the Simulator
        let firstRow = app.cells.element(boundBy: 0)
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
        firstRow.staticTexts.element(boundBy: 0).tap()
        let play = app.buttons["listenPlayPause"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        play.tap()
        wait(30) // play + render ahead
        play.tap()
        wait(4)
        try shot("reader-buffered-fill")
    }
}
