import XCTest

/// Start page (no page loaded): Continue listening (in-progress saves, tap to open in the Reader
/// sheet at their spot) and Saved (recent saves, Show All → library).
final class BrowseStartPageUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func row(_ app: XCUIApplication, in section: String) -> XCUIElement {
        el(app, section).buttons.matching(NSPredicate(format: "label CONTAINS 'Demo Listen Article'")).firstMatch
    }

    func testContinueListeningResumesWhereYouLeftOff() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedDemoArticle", "-seedDemoProgress", "1", "-uiTesting",
                               "-selectEngine", "apple", "-reader.rateMultiplier", "1"]
        app.launch()

        XCTAssertTrue(el(app, "startContinue").waitForExistence(timeout: 10), "Continue listening section")
        let resume = row(app, in: "startContinue")
        XCTAssertTrue(resume.exists, "in-progress article listed")
        XCTAssertFalse(el(app, "startSaved").exists, "not repeated under Saved")

        resume.tap()
        let close = app.buttons["readerClose"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertEqual(close.label, "Back to Browser", "opens in the Reader sheet over the browser")
        let listen = app.buttons["listenPlayPause"]
        XCTAssertTrue(listen.waitForExistence(timeout: 5))
        XCTAssertTrue(listen.label.hasPrefix("Resume"), "offers to resume: \(listen.label)")

        // Resume plays from the saved paragraph: Now Playing's scrubber and the Debug position
        // marker both read paragraph 2 of 3 (paused at once, so the voice can't move it on).
        listen.tap()
        let play = app.buttons["listenPlayPause"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        XCTAssertTrue(waitFor(8) { play.label == "Pause" }, "playing")
        play.tap()
        XCTAssertTrue(waitFor(5) { play.label == "Play" }, "paused")
        let scrubber = el(app, "readerScrubber")
        XCTAssertTrue(scrubber.waitForExistence(timeout: 5))
        XCTAssertEqual(scrubber.value as? String, "Paragraph 2 of 3", "resumes at the saved paragraph")
        let marker = el(app, "readerScrubOffset")
        XCTAssertTrue(marker.waitForExistence(timeout: 2))
        XCTAssertEqual((marker.value as? String)?.hasPrefix("p=1 "), true, "session paragraph: \(marker.value ?? "")")

        app.buttons["readerClose"].firstMatch.tap() // ⌄: Now Playing goes, the start page is back
        XCTAssertTrue(el(app, "startContinue").waitForExistence(timeout: 5))
    }

    private func waitFor(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }

    func testSavedSectionShowAllOpensLibrary() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedDemoArticle", "-uiTesting"]
        app.launch()

        XCTAssertTrue(el(app, "startSaved").waitForExistence(timeout: 10), "Saved section")
        XCTAssertFalse(el(app, "startContinue").exists, "unstarted article isn't in progress")
        XCTAssertTrue(row(app, in: "startSaved").exists)

        el(app, "startSavedShowAll").tap()
        XCTAssertTrue(app.navigationBars["Saved"].waitForExistence(timeout: 5), "library surface")
        XCTAssertTrue(el(app, "librarySearchField").exists, "search in the bottom field capsule")
        app.cells.staticTexts["Demo Listen Article"].tap()
        let close = app.buttons["readerClose"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertEqual(close.label, "Back to Library", "library pushes the reader")
    }

    /// Continue folds to three rows; Show All lists the rest in place (pages played without
    /// saving included, which the Library's list doesn't have), and Show Less folds it again.
    func testContinueShowAllListsEveryRowInPlace() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedDemoArticle", "-seedPlayedPages", "5", "-uiTesting"]
        app.launch()

        let section = el(app, "startContinue")
        XCTAssertTrue(section.waitForExistence(timeout: 10), "Continue listening section")
        let played = section.buttons.matching(NSPredicate(format: "label CONTAINS 'Played Page'"))
        XCTAssertEqual(played.count, 3, "folded to three")
        let toggle = el(app, "startContinueShowAll")
        XCTAssertEqual(toggle.label, "Show All")

        toggle.tap()
        let fifth = section.buttons.matching(NSPredicate(format: "label CONTAINS 'Played Page 5'")).firstMatch
        XCTAssertTrue(fifth.waitForExistence(timeout: 5), "the oldest row is listed")
        XCTAssertEqual(played.count, 5, "every row, in place")
        XCTAssertFalse(app.navigationBars["Saved"].exists, "still the start page, not the Library")
        XCTAssertEqual(toggle.label, "Show Less")

        toggle.tap()
        XCTAssertTrue(fifth.waitForNonExistence(timeout: 5))
        XCTAssertEqual(played.count, 3, "folded again")
    }
}
