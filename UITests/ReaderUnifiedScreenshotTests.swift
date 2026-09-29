import XCTest

/// Browse Reader vs Saved reader should be the same screen. Captures screenshots to
/// `.screenshots/` and checks: [✕/‹][title] top row, bottom scrub row, Save keeps playing, reopen shows bookmark.fill,
/// and a second Save (different tracking params) does not duplicate.
final class ReaderUnifiedScreenshotTests: XCTestCase {
    private let dir = URL(fileURLWithPath: "/Users/jimmyyao/Developer/Reader/.screenshots")
    private let chapter = "https://www.royalroad.com/fiction/193675/the-witchs-bond/chapter/4008906/ch-2-dont-be-dead-part-1"

    private func shot(_ name: String) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: dir.appendingPathComponent(name))
    }

    private func wait(_ s: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }

    private func open(_ app: XCUIApplication, _ url: String) {
        let field = app.textFields["addressField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        wait(0.5)
        if let current = field.value as? String, !current.isEmpty, current != "Search or enter address" {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 5))
        }
        field.typeText(url + "\n")
        wait(7)
    }

    private func openReader(_ app: XCUIApplication) {
        let reader = app.buttons["addressReader"] // reader icon in the address field
        XCTAssertTrue(reader.waitForExistence(timeout: 10))
        reader.tap()
        XCTAssertTrue(app.buttons["readerClose"].waitForExistence(timeout: 20))
        wait(2)
    }

    func testBrowseAndSavedReaderMatch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        // Start clean for this URL: unsave from Saved if a previous run left it.
        open(app, chapter + "?utm_source=home&utm_medium=latest-updates")
        openReader(app)

        let bookmark = app.buttons["readerBookmark"]
        XCTAssertTrue(bookmark.exists)
        if (bookmark.value as? String) == "Saved" {
            bookmark.tap() // unsave → start from unsaved state
            wait(1)
        }
        XCTAssertEqual(bookmark.value as? String, "Not saved")
        try shot("1-browse-reader-unsaved.png")

        // Jump sits next to the scrubber; banner only while on.
        app.buttons["listenJump"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["listenJumpHint"].waitForExistence(timeout: 3))
        try shot("2-browse-reader-jump-mode.png")
        app.buttons["listenJumpCancel"].tap()
        wait(0.5)

        // Play, then Save mid-listen: bookmark fills, playback keeps going, same screen.
        let play = app.buttons["listenPlayPause"]
        play.tap()
        wait(3)
        XCTAssertEqual(play.label, "Pause")
        bookmark.tap()
        wait(1.5)
        XCTAssertEqual(bookmark.value as? String, "Saved")
        XCTAssertEqual(play.label, "Pause", "Save must not stop playback")
        XCTAssertTrue(app.buttons["readerClose"].exists, "Save must not leave the reader")
        try shot("3-browse-reader-saved-while-playing.png")
        play.tap() // pause
        wait(1)

        // Reopen the same chapter without tracking params → resolves to the saved article.
        app.buttons["readerClose"].tap()
        wait(1)
        open(app, chapter)
        openReader(app)
        XCTAssertEqual(app.buttons["readerBookmark"].value as? String, "Saved",
                       "Reopening a saved URL must show bookmark.fill")
        try shot("4-browse-reader-reopened.png")
        app.buttons["readerClose"].tap()
        wait(1)

        // Library (⋯ → Saved): exactly one row for this chapter, and its reader looks the same.
        app.buttons["browseMore"].tap()
        app.descendants(matching: .any)["moreLibrary"].tap()
        XCTAssertTrue(app.navigationBars["Saved"].waitForExistence(timeout: 5))
        wait(1)
        let rows = app.cells.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Ch. 2 - Don"))
        XCTAssertEqual(rows.count, 1, "Saved must not contain duplicates")
        rows.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["readerClose"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["readerBookmark"].value as? String, "Saved")
        wait(2)
        try shot("5-saved-reader.png")
    }
}
