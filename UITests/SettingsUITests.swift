import XCTest

/// Settings and the Aa panel: Settings is the last row of every ⋯ panel, titled as its row; Aa
/// sits at the same place in the Reader's and Now Playing's top bars, opens the text appearance
/// panel, and the panel and Settings › Reading show and change one store.
final class SettingsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// The ⋯ panel's rows, top to bottom (the big buttons under the divider left out).
    private func menuRows(_ app: XCUIApplication) -> [XCUIElement] {
        let tiles: Set<String> = ["moreFavorites", "moreHistory", "moreBrowser", "moreReaderToggle", "moreWebsite",
                                  "moreMenuFocus", "moreMenuDismiss"]
        let all = find(app, "moreMenuPanel").descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'more' AND identifier != 'moreMenuPanel'"))
            .allElementsBoundByIndex
        var seen = Set<String>()
        return all.filter { !tiles.contains($0.identifier) && seen.insert($0.identifier).inserted }
            .sorted { $0.frame.minY < $1.frame.minY }
    }

    /// The open ⋯ panel ends its rows with Settings, above the big buttons; Settings opens titled
    /// as its row, and Done closes it.
    private func assertSettingsIsLast(_ app: XCUIApplication, _ place: String, tile: String) {
        let settings = find(app, "moreSettings")
        XCTAssertTrue(settings.waitForExistence(timeout: 3), "\(place): Settings row")
        XCTAssertNotNil(settledFrames([settings]), "\(place): the ⋯ panel finished growing")
        let rows = menuRows(app)
        XCTAssertEqual(rows.last?.identifier, "moreSettings", "\(place): last row, got \(rows.map(\.identifier))")
        XCTAssertLessThan(settings.frame.maxY, find(app, tile).frame.minY, "\(place): above the big buttons")
        XCTAssertEqual(settings.label, "Settings")
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5), "\(place): titled as its row")
        app.buttons["settingsDone"].tap()
        XCTAssertTrue(eventually(5) { !app.navigationBars["Settings"].exists }, "\(place): Done closes it")
        idle(0.5)
    }

    func testSettingsIsTheLastRowOfEveryMenu() throws {
        let app = launchLibrary(["-reader.developerOptions", "YES"])
        app.buttons["libraryMore"].tap()
        assertSettingsIsLast(app, "the Library home", tile: "moreBrowser")

        openFolder(app, "Demo Finance")
        app.buttons["libraryMore"].tap()
        assertSettingsIsLast(app, "a folder", tile: "moreBrowser")
        app.navigationBars["Demo Finance"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 5))

        let row = libraryRow(app, "Demo Listen Article")
        find(app, "libraryHome").swipeUp()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.buttons["readerMore"].waitForExistence(timeout: 5), "the Reader")
        app.buttons["readerMore"].tap()
        assertSettingsIsLast(app, "the Reader", tile: "moreWebsite")

        app.buttons["listenPlayPause"].tap()
        XCTAssertTrue(find(app, "nowPlayingHeader").waitForExistence(timeout: 5), "Now Playing")
        app.buttons["nowPlayingMore"].tap()
        assertSettingsIsLast(app, "Now Playing", tile: "moreWebsite")
        app.buttons["listenPlayPause"].tap()
        app.buttons["nowPlayingClose"].tap()
        XCTAssertTrue(eventually(5) { !self.find(app, "nowPlayingHeader").exists })
        tapWhenHittable(app.buttons["libraryMore"])
        tapMenuRow(app, "moreBrowser")
        XCTAssertTrue(app.buttons["browseMore"].waitForExistence(timeout: 5))
        app.buttons["browseMore"].tap()
        assertSettingsIsLast(app, "the browser", tile: "moreReaderToggle")
    }

    /// Aa in the Reader and in Now Playing: the same place, left of ☝︎; its panel changes the
    /// reading appearance, and the other panel and Settings › Reading show the same choices.
    func testTheAaPanelOnBothSheetsAndSettingsShareOneStore() throws {
        let app = launchTestPages()
        openTestPage(app, "Next page")
        find(app, "addressReader").tap()
        XCTAssertTrue(app.buttons["readerClose"].waitForExistence(timeout: 10), "the Reader")

        let aa = app.buttons["textAppearanceButton"]
        XCTAssertTrue(aa.waitForExistence(timeout: 5), "Aa in the Reader")
        let jump = app.buttons["listenJump"]
        let inReader = aa.frame
        XCTAssertLessThanOrEqual(inReader.maxX, jump.frame.minX, "Aa left of ☝︎")
        XCTAssertEqual(inReader.midY, jump.frame.midY, accuracy: 1, "on the top bar's line")
        let moreInReader = app.buttons["readerMore"].frame

        aa.tap()
        XCTAssertTrue(find(app, "textAppearancePanel").waitForExistence(timeout: 3), "the panel")
        XCTAssertTrue(app.buttons["readingTheme-matchApp"].isSelected, "Match App to start")
        app.buttons["readingTheme-sepia"].tap()
        XCTAssertTrue(eventually(3) { app.buttons["readingTheme-sepia"].isSelected }, "Sepia chosen")
        app.buttons["readingTextLarger"].tap()
        XCTAssertTrue(eventually(3) { self.find(app, "readingTextSize").label == "110%" }, "a size larger")
        app.buttons["readingFont-rounded"].tap()
        XCTAssertTrue(eventually(3) { app.buttons["readingFont-rounded"].isSelected })
        XCTAssertEqual(app.buttons["readerMore"].frame, moreInReader, "the bottom chrome stays put")
        closePopover(app)

        // Listen: Now Playing has Aa at the same place, and its panel shows the same choices.
        app.buttons["listenPlayPause"].tap()
        let header = find(app, "nowPlayingHeader")
        XCTAssertTrue(header.waitForExistence(timeout: 5), "Now Playing")
        let aaPlaying = header.buttons["textAppearanceButton"]
        XCTAssertTrue(aaPlaying.waitForExistence(timeout: 3), "Aa in Now Playing")
        XCTAssertEqual(aaPlaying.frame.minX, inReader.minX, accuracy: 1, "the same place")
        XCTAssertEqual(aaPlaying.frame.minY, inReader.minY, accuracy: 1, "the same place")
        XCTAssertEqual(app.buttons["nowPlayingMore"].frame.minX, moreInReader.minX, accuracy: 1, "⋯ where it was")
        app.buttons["listenPlayPause"].tap() // pause
        aaPlaying.tap()
        XCTAssertTrue(find(app, "textAppearancePanel").waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["readingTheme-sepia"].isSelected, "the Reader's choice")
        XCTAssertEqual(find(app, "readingTextSize").label, "110%")
        app.buttons["readingTheme-dark"].tap()
        XCTAssertTrue(eventually(3) { app.buttons["readingTheme-dark"].isSelected })
        closePopover(app)

        // Settings › Reading shows what the panel chose; a change there is what Aa shows next.
        app.buttons["nowPlayingMore"].tap()
        tapMenuRow(app, "moreSettings")
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["readingTheme-dark"].isSelected, "Settings shows the panel's theme")
        XCTAssertTrue(app.buttons["readingFont-rounded"].isSelected)
        XCTAssertEqual(find(app, "readingTextSize").label, "110%")
        app.buttons["readingTheme-matchApp"].tap()
        app.buttons["readingTextSmaller"].tap()
        XCTAssertTrue(eventually(3) { self.find(app, "readingTextSize").label == "100%" })
        app.buttons["readingFont-serif"].tap()
        app.buttons["settingsDone"].tap()
        XCTAssertTrue(eventually(5) { !app.navigationBars["Settings"].exists })

        header.buttons["textAppearanceButton"].tap()
        XCTAssertTrue(find(app, "textAppearancePanel").waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["readingTheme-matchApp"].isSelected, "Aa shows Settings' choice")
        XCTAssertTrue(app.buttons["readingFont-serif"].isSelected)
        XCTAssertEqual(find(app, "readingTextSize").label, "100%")
        closePopover(app)
    }

    /// Settings › Appearance: the app's colour and appearance apply at once and stay chosen.
    func testAppearanceChoicesApply() throws {
        let app = launchTestPages()
        app.buttons["browseMore"].tap()
        tapMenuRow(app, "moreSettings")
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["appearanceMode-system"].isSelected)
        XCTAssertTrue(app.buttons["appAccent-jade"].isSelected)
        app.buttons["appAccent-plum"].tap()
        app.buttons["appearanceMode-dark"].tap()
        XCTAssertTrue(eventually(3) { app.buttons["appAccent-plum"].isSelected })
        XCTAssertTrue(app.buttons["appearanceMode-dark"].isSelected)
        app.buttons["settingsDone"].tap()
        XCTAssertTrue(eventually(5) { !app.navigationBars["Settings"].exists })
        app.buttons["browseMore"].tap()
        tapMenuRow(app, "moreSettings")
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["appAccent-plum"].isSelected, "kept")
        XCTAssertTrue(app.buttons["appearanceMode-dark"].isSelected, "kept")
        app.buttons["appearanceMode-system"].tap()
        app.buttons["appAccent-jade"].tap()
        app.buttons["settingsDone"].tap()
    }

    /// A popover closes on a tap outside it (low on the page, clear of the panel and the bars).
    private func closePopover(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)).tap()
        XCTAssertTrue(eventually(3) { !self.find(app, "textAppearancePanel").exists }, "the panel closes")
        idle(0.4)
    }
}
