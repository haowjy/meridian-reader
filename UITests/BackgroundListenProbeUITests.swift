import XCTest

/// Measurement probe (not part of the normal suite): Kokoro listen → Home for 40 s → back.
/// Run with `TEST_RUNNER_READER_BG_PROBE=1 xcodebuild test … -only-testing:ReaderUITests/BackgroundListenProbeUITests`
/// then read `Application Support/ListenTiming/timing.jsonl` in the Simulator app container
/// (`app_phase`, `bg_unit`, `bg_deferred`, `synth`, `synth_blocked_bg`, `fallback_apple`).
final class BackgroundListenProbeUITests: XCTestCase {
    func testListenContinuesInBackgroundWithoutCoreML() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["READER_BG_PROBE"] == "1", "probe only")
        let app = XCUIApplication()
        app.launchArguments = ["-seedDemoArticle", "-seedDemoParagraphs", "14",
                               "-selectEngine", "local.kokoro", "-uiTesting", "-openLibrary"]
        app.launch()
        XCTAssertTrue(app.cells.staticTexts["Demo Listen Article"].waitForExistence(timeout: 10))
        // Let Kokoro load (Simulator) before Play so the local engine is used.
        RunLoop.current.run(until: Date().addingTimeInterval(20))
        app.cells.staticTexts["Demo Listen Article"].tap()
        let playPause = app.buttons["listenPlayPause"]
        XCTAssertTrue(playPause.waitForExistence(timeout: 10))
        playPause.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(10)) // foreground: play + bake ahead

        XCUIDevice.shared.press(.home) // leave the app
        RunLoop.current.run(until: Date().addingTimeInterval(40))

        app.activate()
        XCTAssertTrue(playPause.waitForExistence(timeout: 10))
        RunLoop.current.run(until: Date().addingTimeInterval(16)) // Kokoro should take over again
        let add = XCTAttachment(screenshot: app.screenshot())
        add.lifetime = .keepAlways
        self.add(add)
        XCTAssertEqual(playPause.label, "Pause", "still playing after coming back")
    }
}
