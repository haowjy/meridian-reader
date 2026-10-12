import XCTest

/// Voice Settings: swipe → *Delete* on an on-device engine deletes its download, and its row
/// stays (to download it again); the list goes on taking changes. Offline: the Debug test voice.
final class VoiceSettingsDeleteUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testDeletingAnEnginesDownloadKeepsItsRow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-testVoice", "-selectEngine", "apple", "-openLibrary"]
        app.launch()
        let more = app.buttons["libraryMore"]
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        more.tap()
        let voice = app.descendants(matching: .any).matching(identifier: "moreVoice").firstMatch
        XCTAssertTrue(voice.waitForExistence(timeout: 3))
        idle(0.6)
        voice.tap()

        let row = app.buttons["engineRow-test.voice"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the test voice's row")
        row.swipeLeft()
        let delete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 3), "the swipe action")
        delete.tap()
        idle(1)
        XCTAssertTrue(row.exists, "the row stays")

        app.buttons["engineRow-test.voice"].tap()
        idle(1)
        app.buttons["engineRow-apple"].tap()
        idle(1)
        XCTAssertEqual(app.state, .runningForeground, "the app is still up")
        XCTAssertTrue(row.exists, "the row is still there")
    }
}
