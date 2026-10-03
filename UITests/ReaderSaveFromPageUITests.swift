import XCTest

/// The reader opened over a web page and the same article opened from Saved are one screen.
/// Offline: the `reader-test://pages/two` article page (`-browseTestPages`). Checks the bookmark
/// state, Jump next to the scrubber, Save while playing (keeps playing, stays in the reader),
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

    private func openReader(_ app: XCUIApplication) {
        let icon = app.descendants(matching: .any).matching(identifier: "addressReader").firstMatch
        XCTAssertTrue(icon.waitForExistence(timeout: 10), "reader icon on the article page")
        icon.tap()
        XCTAssertTrue(app.buttons["readerClose"].waitForExistence(timeout: 10))
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

        // Play, then Save mid-listen: the bookmark fills, playback keeps going, same screen.
        let play = app.buttons["listenPlayPause"]
        play.tap()
        XCTAssertTrue(waitFor("label == 'Pause'", play, timeout: 8), "playing")
        bookmark.tap()
        XCTAssertTrue(waitFor("value == 'Saved'", bookmark))
        XCTAssertEqual(play.label, "Pause", "Save must not stop playback")
        XCTAssertTrue(app.buttons["readerClose"].exists, "Save must not leave the reader")
        shot(app, "3-page-reader-saved-while-playing")
        play.tap()

        // Reopen the reader over the same page: it resolves to the saved article.
        app.buttons["readerClose"].tap()
        XCTAssertTrue(waitFor("exists == false", app.buttons["readerClose"]))
        openReader(app)
        XCTAssertEqual(app.buttons["readerBookmark"].value as? String, "Saved", "a saved page opens saved")
        app.buttons["readerClose"].tap()
        XCTAssertTrue(waitFor("exists == false", app.buttons["readerClose"]))

        // Library: exactly one row for the page, and its reader is the same screen.
        app.buttons["browseLibrary"].tap()
        XCTAssertTrue(app.navigationBars["Saved"].waitForExistence(timeout: 5))
        let rows = app.cells.staticTexts.matching(NSPredicate(format: "label == %@", "Second page"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 1, "Saved must not contain duplicates")
        rows.firstMatch.tap()
        XCTAssertTrue(app.buttons["readerClose"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["readerBookmark"].value as? String, "Saved")
        shot(app, "4-saved-reader")
    }
}
