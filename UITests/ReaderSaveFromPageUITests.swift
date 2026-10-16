import XCTest

/// The reader opened over a web page and the same article opened from Saved are one screen.
/// Offline: the `reader-test://pages/two` article page (`-browseTestPages`). Checks the bookmark
/// state, Jump next to the scrubber, Save while playing (keeps playing, stays in Now Playing),
/// reopening a saved page, and exactly one Saved row. Screenshots are attached to the test result.
final class ReaderSaveFromPageUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitFor(_ predicate: String, _ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let exp = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        return XCTWaiter().wait(for: [exp], timeout: timeout) == .completed
    }

    /// 📄: the Reader, or Now Playing when the page is what you hear (`close` names which, by its
    /// close pill).
    private func openReader(_ app: XCUIApplication, close: String = "readerClose") {
        let icon = app.descendants(matching: .any).matching(identifier: "addressReader").firstMatch
        XCTAssertTrue(icon.waitForExistence(timeout: 10), "reader icon on the article page")
        icon.tap()
        XCTAssertTrue(app.buttons[close].waitForExistence(timeout: 10))
    }

    func testSaveFromPageReaderMatchesSavedReader() throws {
        let app = XCUIApplication()
        // The demo seed empties Saved, so the page starts unsaved whatever an earlier run left.
        app.launchArguments = ["-uiTesting", "-seedDemoArticle", "-browseTestPages", "-resetBookmarks",
                               "-selectEngine", "apple", "-reader.rateMultiplier", "1"]
        app.launch()
        let link = app.links["Next page"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.tap()
        openReader(app)

        let bookmark = app.buttons["readerBookmark"]
        XCTAssertTrue(bookmark.waitForExistence(timeout: 5))
        XCTAssertEqual(bookmark.value as? String, "Not saved")
        shot(app, "1-page-reader-unsaved")

        // Jump sits next to the scrubber; its hint shows only while it's on.
        app.buttons["listenJump"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["listenJumpHint"].waitForExistence(timeout: 3))
        shot(app, "2-page-reader-jump-mode")
        app.buttons["listenJumpCancel"].tap()

        // Play, then Save mid-listen: Listen turns the Reader into Now Playing (D2), whose 🔖
        // fills; playback keeps going, same screen.
        let play = app.buttons["listenPlayPause"]
        play.tap()
        XCTAssertTrue(waitFor("label == 'Pause'", play, timeout: 8), "playing")
        let playing = app.buttons["nowPlayingBookmark"]
        XCTAssertEqual(playing.value as? String, "Not saved", "Now Playing's 🔖 says what the Reader's did")
        playing.tap()
        XCTAssertTrue(waitFor("value == 'Saved'", playing))
        XCTAssertEqual(play.label, "Pause", "Save must not stop playback")
        XCTAssertTrue(app.buttons["nowPlayingClose"].exists, "Save must not leave Now Playing")
        shot(app, "3-page-reader-saved-while-playing")
        play.tap()

        // Reopen over the same page: it is what you hear, so Now Playing, and saved.
        app.buttons["nowPlayingClose"].tap()
        XCTAssertTrue(waitFor("exists == false", app.buttons["nowPlayingClose"]))
        openReader(app, close: "nowPlayingClose")
        XCTAssertEqual(app.buttons["nowPlayingBookmark"].value as? String, "Saved", "a saved page opens saved")
        app.buttons["nowPlayingClose"].tap()
        XCTAssertTrue(waitFor("exists == false", app.buttons["nowPlayingClose"]))

        // Library: exactly one row for the page, and it opens the same screen.
        app.buttons["browseLibrary"].tap()
        XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 5))
        let rows = app.cells.staticTexts.matching(NSPredicate(format: "label == %@", "Second page"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 1, "Saved must not contain duplicates")
        rows.firstMatch.tap()
        XCTAssertTrue(app.buttons["nowPlayingClose"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["nowPlayingBookmark"].value as? String, "Saved")
        shot(app, "4-saved-reader")
    }
}
