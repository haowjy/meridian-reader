import XCTest

/// The three end-to-end flows kept as automated checks; everything else is verified by probing
/// the running app. Offline: the `reader-test://` pages and the demo seeds.
final class CoreFlowsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// A browsed page, played from its Reader and saved mid-listen: Save keeps it playing in Now
    /// Playing, and the Library then holds exactly one row for it.
    func testSaveAndPlayABrowsedPage() throws {
        let app = launch(["-browseTestPages"])
        let link = app.links["Next page"]
        XCTAssertTrue(appears(link, timeout: 10))
        link.tap()
        let reader = find(app, "addressReader")
        XCTAssertTrue(appears(reader, timeout: 10), "📄 on the article page")
        tapWhenHittable(reader)

        let play = app.buttons["listenPlayPause"]
        XCTAssertTrue(appears(play, timeout: 10), "the Reader")
        // The pill is in the tree while the Reader sheet still rises from below the screen.
        tapWhenHittable(play)
        XCTAssertTrue(eventually(8) { play.exists && play.label == "Pause" }, "playing")
        let bookmark = app.buttons["nowPlayingBookmark"]
        XCTAssertEqual(bookmark.value as? String, "Not saved")
        bookmark.tap()
        XCTAssertTrue(eventually { bookmark.value as? String == "Saved" })
        XCTAssertEqual(play.label, "Pause", "Save must not stop playback")
        XCTAssertTrue(app.buttons["nowPlayingClose"].exists, "Save must not leave Now Playing")
        play.tap()

        app.buttons["nowPlayingClose"].tap()
        XCTAssertTrue(eventually { !app.buttons["nowPlayingClose"].exists })
        tapWhenHittable(app.buttons["browseLibrary"])
        XCTAssertTrue(appears(app.libraryHome, timeout: 5))
        let rows = app.cells.staticTexts.matching(NSPredicate(format: "label == %@", "Second page"))
        XCTAssertTrue(appears(rows.firstMatch, timeout: 5))
        XCTAssertEqual(rows.count, 1, "one row per page")
    }

    /// Swipe → *Remove from Library* on the page you hear: its row leaves every list (not back in Recent,
    /// not in search), playback stops, the bar offers the page played before it (the demo
    /// folders' part-way page) instead, and the app stays up.
    func testSwipeRemovingAPlayedPageTakesItOutOfEveryList() throws {
        let app = launchLibrary()
        let cell = libraryCell(app, "Demo Listen Article")
        XCTAssertTrue(appears(cell, timeout: 5), "Pages: the demo article")
        libraryRow(app, "Demo Listen Article").tap()
        let bar = app.buttons["nowPlayingBarPlayPause"]
        XCTAssertTrue(appears(bar, timeout: 10), "the bar shows what you hear")
        XCTAssertTrue(eventually(10) { bar.label == "Pause" }, "playing")

        cell.swipeLeft()
        let remove = app.buttons["Remove from Library"].firstMatch
        XCTAssertTrue(appears(remove, timeout: 3), "the row's swipe action")
        remove.tap()
        let row = libraryRow(app, "Demo Listen Article")
        XCTAssertTrue(eventually(5) { !row.exists }, "its row leaves the list")
        XCTAssertEqual(app.state, .runningForeground, "the app is still up")
        XCTAssertTrue(libraryRow(app, "Demo Finance").exists, "the rest of the list is there")
        XCTAssertTrue(eventually(5) { !bar.exists }, "Remove stops what you hear")
        let resume = find(app, "nowPlayingBarResumeOpen")
        XCTAssertTrue(appears(resume, timeout: 3), "the bar resumes another page")
        XCTAssertTrue(resume.label.contains("Seven-Day Yield"), "the one played before, not the removed one")
        idle(1)
        XCTAssertFalse(row.exists, "not back in the list")

        let search = app.textFields["librarySearchField"]
        XCTAssertTrue(appears(search, timeout: 3))
        search.tap()
        search.typeText("Demo Listen")
        idle(1)
        XCTAssertFalse(libraryRow(app, "Demo Listen Article").exists, "search doesn't find it")
    }

    /// A folder opened from the Library plays from its header: *More* › *Play from Start* plays its
    /// first page, and the big ▶ shows it playing (⏸).
    func testOpenAFolderAndPlayIt() throws {
        let app = launchLibrary()
        let folder = libraryRow(app, "Demo Finance")
        XCTAssertTrue(appears(folder, timeout: 5))
        folder.tap()
        XCTAssertTrue(appears(app.navigationBars["Demo Finance"], timeout: 5), "the folder's screen")

        let round = app.buttons["folderContinue"]
        XCTAssertTrue(appears(round, timeout: 5), "the big ▶")
        app.buttons["folderMore"].tap()
        let fromStart = app.buttons["menuPlayFromStart"]
        XCTAssertTrue(appears(fromStart, timeout: 3), "More's menu")
        fromStart.tap()
        let bar = find(app, "nowPlayingBarOpen")
        XCTAssertTrue(appears(bar, timeout: 10))
        XCTAssertTrue(eventually(10) { bar.label.contains("Seven-Day Yield") }, "its first page: \(bar.label)")
        XCTAssertTrue(eventually(5) { round.label == "Pause" }, "the big ▶: \(round.label)")
        find(app, "nowPlayingBarPlayPause").tap()
    }
}
