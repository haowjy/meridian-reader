import XCTest

/// One look for one thing (the 2026-10-15 design review): Edit keeps the five-slot toolbar, a
/// folder's name shows once, every ⋯ ends with the same rows in the same order and names an
/// action one way, toasts float above the Now Playing bar, and the sheets' Done buttons match.
final class DesignConsistencyUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// The toolbar slot centres, as `ToolbarGridUITests` measures them.
    private func slotCentres(_ app: XCUIApplication) -> [CGFloat] {
        let window = app.windows.firstMatch.frame
        let slot = (window.width - 2 * 12) / 5
        return (0..<5).map { window.minX + 12 + slot * (CGFloat($0) + 0.5) }
    }

    /// Edit puts *Move to…*, *Mark as Finished* and *Remove* in the toolbar's own slots (1, 3, 5),
    /// as symbols on the same row, so the chrome keeps its shape.
    func testEditKeepsTheFiveSlotToolbar() throws {
        let app = launchLibrary()
        let more = find(app, "libraryMore").frame
        openFolder(app, "Demo Finance")
        app.buttons["folderEdit"].tap()
        let centres = slotCentres(app)
        for (id, slot, label) in [("editMove", 0, "Move to…"), ("editMarkFinished", 2, "Mark as Finished"),
                                  ("editRemove", 4, "Remove")] {
            let button = app.buttons[id]
            XCTAssertTrue(button.waitForExistence(timeout: 5), id)
            XCTAssertEqual(button.frame.midX, centres[slot], accuracy: 1, "\(id) in slot \(slot + 1)")
            XCTAssertEqual(button.frame.midY, more.midY, accuracy: 1, "\(id) on the toolbar's row")
            XCTAssertEqual(button.label, label, "\(id) named by its verb")
        }
    }

    /// A folder's name is its header's title; the navigation bar doesn't repeat it at rest.
    func testAFolderShowsItsNameOnce() throws {
        let app = launchLibrary()
        openFolder(app, "Demo Finance")
        let bar = app.navigationBars["Demo Finance"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "the screen keeps its title for VoiceOver and ‹")
        XCTAssertNotNil(settledFrames([bar]), "the push has finished")
        XCTAssertFalse(bar.staticTexts["Demo Finance"].exists, "no second title in the bar at rest")
        XCTAssertTrue(find(app, "folderScreen").staticTexts["Demo Finance"].exists, "the header's title")
    }

    /// Every ⋯ ends the same way, in the same order: Download, Downloads, Settings. A book names
    /// its own rows.
    func testMenusShareTheirTailAndNames() throws {
        let app = launchLibrary()
        app.buttons["libraryMore"].tap()
        assertOrder(app, ["moreNewFolder", "moreDownloads", "moreSettings"], "the home's ⋯")
        closeMenu(app)

        openFolder(app, "Demo Finance")
        app.buttons["libraryMore"].tap()
        assertOrder(app, ["moreMove", "moreDeleteFolder", "moreDownload", "moreDeleteDownloads", "moreDownloads",
                          "moreSettings"], "a folder's ⋯")
        XCTAssertEqual(find(app, "moreMove").label, "Move to…")
        XCTAssertEqual(find(app, "moreDownload").label, "Download Folder")
        closeMenu(app)
        app.navigationBars["Demo Finance"].buttons.element(boundBy: 0).tap()

        openFolder(app, "The Demo Book")
        app.buttons["libraryMore"].tap()
        XCTAssertTrue(find(app, "moreDownload").waitForExistence(timeout: 3))
        XCTAssertEqual(find(app, "moreDownload").label, "Download Book")
        XCTAssertEqual(find(app, "moreDeleteFolder").label, "Delete Book…")
        closeMenu(app)
    }

    /// The toast a download shows sits above the Now Playing bar, not on it.
    func testAToastFloatsAboveTheNowPlayingBar() throws {
        let app = launch(UITestSetup(["-seedDemoArticle", "-seedDemoFolders", "-testVoice", "-testVoiceDelay", "0.3",
                                      "-openLibrary"], engine: "test.voice"))
        XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 10))
        openFolder(app, "Demo Finance")
        app.buttons["libraryMore"].tap()
        tapMenuRow(app, "moreDownload")
        let toast = find(app, "toast")
        XCTAssertTrue(toast.waitForExistence(timeout: 5), "Downloading …")
        let bar = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier IN %@", ["nowPlayingBar", "nowPlayingBarResume", "nowPlayingBarPlaceholder"])
        ).firstMatch
        XCTAssertTrue(bar.exists, "the Now Playing bar")
        XCTAssertLessThanOrEqual(toast.frame.maxY, bar.frame.minY + 1, "toast \(toast.frame) above the bar \(bar.frame)")
    }

    /// History, Downloads and Settings close with the same Done pill.
    func testSheetsShareOneDoneButton() throws {
        let app = launchLibrary()
        var heights: [String: CGFloat] = [:]
        for (row, done) in [("moreHistory", "historyDone"), ("moreDownloads", "downloadsDone"),
                            ("moreSettings", "settingsDone")] {
            tapWhenHittable(app.buttons["libraryMore"])
            tapMenuRow(app, row)
            let button = app.buttons[done]
            XCTAssertTrue(button.waitForExistence(timeout: 5), done)
            XCTAssertEqual(button.label, "Done")
            heights[done] = button.frame.height
            button.tap()
            XCTAssertTrue(eventually(5) { !button.exists }, "\(done) closes its sheet")
            if !eventually(1, { app.libraryHome.exists }) { tapWhenHittable(app.buttons["browseLibrary"]) }
            XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 5))
        }
        let values = Array(heights.values)
        // A medium-detent sheet is drawn a little smaller than a full one: within that.
        for h in values { XCTAssertEqual(h, values[0], accuracy: 2, "one pill: \(heights)") }
    }

    // MARK: - Helpers

    private func assertOrder(_ app: XCUIApplication, _ ids: [String], _ what: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        var last = -CGFloat.infinity
        for id in ids {
            let row = find(app, id)
            XCTAssertTrue(row.waitForExistence(timeout: 3), "\(what): \(id)", file: file, line: line)
            XCTAssertGreaterThan(row.frame.midY, last, "\(what): \(id) after the rows before it", file: file, line: line)
            last = row.frame.midY
        }
    }
}
