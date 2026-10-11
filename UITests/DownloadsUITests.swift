import XCTest

/// Downloads (decision D16), offline, with the Debug test voice (`-testVoice`: a tone, voices One
/// and Two) standing in for Kokoro: the demo book downloaded from its screen's ⋯ shows the
/// progress line while it renders and lands in Downloads under Done, named by its voice, with
/// the storage it uses; a voice change moves it to Different Voice, where Keep and Re-download
/// settle it; a queued download pauses and is removed.
final class DownloadsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(delay: Double = 0.15) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-seedDemoBook", "-resetBookmarks", "-resetDownloads", "-testVoice",
                               "-testVoiceDelay", "\(delay)", "-selectEngine", "test.voice", "-openLibrary"]
        app.launch()
        XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 10), "the Library")
        return app
    }

    /// The book's ⋯ › *Download Book*.
    private func downloadTheBook(_ app: XCUIApplication) {
        openFolder(app, "The Demo Book")
        app.buttons["libraryMore"].tap()
        tapMenuRow(app, "moreDownload")
    }

    /// ⋯ › Downloads.
    private func openDownloads(_ app: XCUIApplication) {
        app.buttons["libraryMore"].tap()
        tapMenuRow(app, "moreDownloads")
        XCTAssertTrue(find(app, "downloadsSheet").waitForExistence(timeout: 5), "Downloads")
    }

    private func closeDownloads(_ app: XCUIApplication) {
        app.buttons["downloadsDone"].tap()
        XCTAssertTrue(eventually(5) { !find(app, "downloadsSheet").exists })
        idle(0.5)
    }

    /// The row titled `title` in the Downloads list: its value is its detail line.
    private func downloadRow(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        find(app, "downloadsSheet").staticTexts.matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    private func value(_ element: XCUIElement) -> String { element.value as? String ?? "" }

    func testABookDownloadsWithItsVoiceShownAndAVoiceChangeAsksToRedownloadOrKeep() throws {
        let app = launch()
        downloadTheBook(app)
        XCTAssertTrue(find(app, "downloadProgress").waitForExistence(timeout: 5), "the progress line while it renders")
        XCTAssertFalse(find(app, "downloadsSheet").exists, "nothing modal")

        openDownloads(app)
        let row = downloadRow(app, "The Demo Book")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(eventually(60) { find(app, "downloadsDoneHeader").exists }, "done, got \(value(row))")
        XCTAssertTrue(value(row).hasPrefix("Test Voice One"), "named by its voice, got \(value(row))")
        XCTAssertTrue(find(app, "downloadsStorage").waitForExistence(timeout: 5), "the storage it uses")
        XCTAssertFalse(value(row).contains("·"), "parts set apart by space, not a dot")
        closeDownloads(app)
        XCTAssertTrue(eventually(5) { !find(app, "downloadProgress").exists }, "no line once nothing is queued")

        // Another voice (Voice Settings from the home's ⋯): the download is marked as a different voice.
        app.navigationBars["The Demo Book"].buttons.firstMatch.tap()
        XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 5))
        app.buttons["libraryMore"].tap()
        tapMenuRow(app, "moreVoice")
        XCTAssertTrue(app.navigationBars["Listen"].waitForExistence(timeout: 5), "Voice settings")
        let two = find(app, "voiceRow-two")
        for _ in 0..<6 where !(two.exists && two.isHittable) { app.swipeUp() }
        two.tap()
        idle(1)
        app.navigationBars["Listen"].buttons["Done"].tap()
        XCTAssertTrue(eventually(5) { !app.navigationBars["Listen"].exists })
        idle(0.5)

        openDownloads(app)
        XCTAssertTrue(find(app, "downloadsDifferentVoiceHeader").waitForExistence(timeout: 5), "Different Voice")
        XCTAssertTrue(value(downloadRow(app, "The Demo Book")).hasPrefix("Test Voice One"))
        XCTAssertFalse(find(app, "downloadsDoneHeader").exists)

        // Keep: done, still in its own voice.
        find(app, "downloadKeep").tap()
        XCTAssertTrue(find(app, "downloadsDoneHeader").waitForExistence(timeout: 5), "kept: Done")
        XCTAssertFalse(find(app, "downloadsDifferentVoiceHeader").exists)
        XCTAssertTrue(value(downloadRow(app, "The Demo Book")).hasPrefix("Test Voice One"))

        // Re-download (the row's menu): rendered again in voice Two.
        downloadRow(app, "The Demo Book").press(forDuration: 1.0)
        let redownload = app.buttons["Re-download"]
        XCTAssertTrue(redownload.waitForExistence(timeout: 5))
        redownload.tap()
        XCTAssertTrue(eventually(60) { value(downloadRow(app, "The Demo Book")).hasPrefix("Test Voice Two")
                && find(app, "downloadsDoneHeader").exists }, "re-downloaded in Two, got \(value(downloadRow(app, "The Demo Book")))")
    }

    func testAQueuedDownloadPausesAndIsRemoved() throws {
        let app = launch(delay: 0.8)
        downloadTheBook(app)
        XCTAssertTrue(find(app, "downloadProgress").waitForExistence(timeout: 5))

        openDownloads(app)
        XCTAssertTrue(find(app, "downloadsQueuedHeader").waitForExistence(timeout: 5), "Queued")
        let pause = find(app, "downloadPause")
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        pause.tap()
        let row = downloadRow(app, "The Demo Book")
        XCTAssertTrue(eventually(5) { self.value(row).contains("Paused") }, "paused, got \(value(row))")
        XCTAssertTrue(find(app, "downloadResume").exists, "the ring offers to resume")
        XCTAssertTrue(eventually(5) { !find(app, "downloadProgress").exists }, "no line while everything is paused")

        row.swipeLeft()
        let remove = app.buttons["Remove"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        XCTAssertTrue(find(app, "downloadsEmpty").waitForExistence(timeout: 5), "nothing downloaded")
    }
}
