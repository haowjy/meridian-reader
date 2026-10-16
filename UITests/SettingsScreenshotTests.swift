import XCTest

/// Screenshots of Settings, the app themes and the reading themes, for design review (not
/// assertions; `SettingsUITests` checks behaviour). Skipped unless a directory is given:
///
///     TEST_RUNNER_READER_SCREENSHOTS_DIR=/tmp/reader-shots \
///         xcodebuild test … -only-testing:MeridianReaderUITests/SettingsScreenshotTests
///
/// PNGs go to `<dir>/<name>.png`. Themes are chosen through launch arguments, which UserDefaults
/// reads ahead of what is stored (`-appearance.mode dark`, `-reading.theme sepia`), so nothing
/// stored in the Simulator changes.
final class SettingsScreenshotTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        guard let path = ProcessInfo.processInfo.environment["READER_SCREENSHOTS_DIR"], !path.isEmpty else {
            throw XCTSkip("Set TEST_RUNNER_READER_SCREENSHOTS_DIR=<dir> to capture screenshots.")
        }
        dir = URL(fileURLWithPath: path)
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

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-selectEngine", "apple", "-reader.rateMultiplier", "1"] + arguments
        app.launch()
        return app
    }

    // MARK: - Settings

    func testSettingsSections() throws {
        let app = launch(["-browseTestPages", "-resetBookmarks", "-reader.developerOptions", "YES"])
        XCTAssertTrue(app.links["Next page"].waitForExistence(timeout: 30))
        app.buttons["browseMore"].tap()
        idle(1.2)
        try shot("settings-0-menu-row")
        find(app, "moreSettings").tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        idle(1)
        try shot("settings-1-appearance-reading")
        let list = find(app, "settingsList")
        for (index, anchor) in ["settingsVoice", "settingsDownloads", "settingsVersionRow"].enumerated() {
            for _ in 0..<8 where !(find(app, anchor).exists && find(app, anchor).isHittable
                                   && find(app, anchor).frame.maxY < app.frame.height * 0.6) {
                list.swipeUp(velocity: .slow)
            }
            idle(0.8)
            try shot("settings-\(index + 2)-" + ["listening", "downloads-storage", "developer-version"][index])
        }
        for _ in 0..<8 where !find(app, "settingsVoice").isHittable { list.swipeDown(velocity: .slow) }
        find(app, "settingsVoice").tap()
        idle(1)
        try shot("settings-5-voice-page")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        idle(0.8)
        find(app, "settingsLanguage").tap()
        idle(1)
        try shot("settings-6-language-page")
    }

    // MARK: - App themes

    func testAppThemesOnLibraryAndBrowse() throws {
        let themes: [(String, String)] = [
            ("light", "jade"), ("dark", "jade"), ("light", "harbor"), ("dark", "harbor"), ("light", "plum"),
            ("dark", "plum"), ("light", "ember"), ("dark", "ember"), ("light", "graphite"), ("dark", "graphite"),
        ]
        for (mode, accent) in themes {
            let app = launch(["-seedDemoArticle", "-seedDemoFolders", "-seedBookmarks",
                              "-appearance.mode", mode, "-appearance.accent", accent])
            XCTAssertTrue(find(app, "browseLibrary").waitForExistence(timeout: 30))
            idle(1.5)
            try shot("app-\(accent)-\(mode)-browse-start")
            find(app, "browseLibrary").tap()
            idle(1.5)
            try shot("app-\(accent)-\(mode)-library")
            app.terminate()
        }
    }

    // MARK: - Reading themes

    func testReadingThemesOnReaderAndNowPlaying() throws {
        for theme in ["matchApp", "light", "sepia", "dark", "black"] {
            for mode in theme == "matchApp" ? ["light", "dark"] : ["light"] {
                let app = launch(["-browseTestPages", "-resetBookmarks", "-reading.theme", theme,
                                  "-appearance.mode", mode])
                let suffix = theme == "matchApp" ? "\(theme)-\(mode)" : theme
                openReader(app)
                try shot("reading-\(suffix)-reader")
                app.buttons["listenPlayPause"].tap()
                XCTAssertTrue(find(app, "nowPlayingHeader").waitForExistence(timeout: 8))
                idle(3)
                app.buttons["listenPlayPause"].tap() // pause, so the shot is still
                idle(1)
                try shot("reading-\(suffix)-now-playing")
                app.terminate()
            }
        }
    }

    func testAaPanelOnReaderAndNowPlaying() throws {
        let app = launch(["-browseTestPages", "-resetBookmarks", "-reading.theme", "sepia"])
        openReader(app)
        find(app, "textAppearanceButton").tap()
        idle(1.2)
        try shot("aa-panel-reader")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap()
        idle(0.8)
        app.buttons["listenPlayPause"].tap()
        XCTAssertTrue(find(app, "nowPlayingHeader").waitForExistence(timeout: 8))
        idle(2)
        app.buttons["listenPlayPause"].tap()
        idle(0.8)
        find(app, "nowPlayingHeader").buttons["textAppearanceButton"].tap()
        idle(1.2)
        try shot("aa-panel-now-playing")
    }

    /// Test page two in the Reader.
    private func openReader(_ app: XCUIApplication) {
        let link = app.links["Next page"]
        XCTAssertTrue(link.waitForExistence(timeout: 30))
        link.tap()
        XCTAssertTrue(find(app, "addressReader").waitForExistence(timeout: 10))
        idle(0.8)
        find(app, "addressReader").tap()
        XCTAssertTrue(app.buttons["readerClose"].waitForExistence(timeout: 10))
        idle(1.5)
    }
}
