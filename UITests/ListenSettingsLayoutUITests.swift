import XCTest

/// Settings → Listen: switching voices (and engine state changes) must not change row heights
/// or move rows. Records every engine/voice row frame before and after switching the Kokoro
/// voice (including the download-in-progress state) and saves screenshots to /tmp.
final class ListenSettingsLayoutUITests: XCTestCase {
    private let shotDir = URL(fileURLWithPath: "/tmp/reader-voiceui")
    private let rowIDs = ["engineRow-apple", "engineRow-local.kokoro",
                          "voiceRow-af_heart", "voiceRow-af_bella", "voiceRow-bf_emma",
                          "voiceRow-am_puck", "voiceRow-bm_fable"]

    private func frames(_ app: XCUIApplication) -> [String: CGRect] {
        var out: [String: CGRect] = [:]
        for id in rowIDs {
            let el = app.buttons[id]
            if el.exists { out[id] = el.frame }
        }
        return out
    }

    private func shot(_ name: String) throws {
        try FileManager.default.createDirectory(at: shotDir, withIntermediateDirectories: true)
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: shotDir.appendingPathComponent(name))
    }

    private func waitSelected(_ el: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if el.isSelected { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return el.isSelected
    }

    private func assertSameLayout(_ a: [String: CGRect], _ b: [String: CGRect], _ label: String,
                                  file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Set(a.keys), Set(b.keys), "\(label): same rows", file: file, line: line)
        for (id, fa) in a {
            guard let fb = b[id] else { continue }
            XCTAssertEqual(fa.height, fb.height, accuracy: 0.5, "\(label): \(id) height", file: file, line: line)
            XCTAssertEqual(fa.minY, fb.minY, accuracy: 0.5, "\(label): \(id) moved", file: file, line: line)
        }
    }

    func testSwitchingKokoroVoiceKeepsRowHeights() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-selectEngine", "local.kokoro", "-uiTesting", "-openLibrary"]
        app.launch()
        addTeardownBlock {
            // Leave the simulator on Apple + Heart for the other UI tests.
            let reset = XCUIApplication()
            reset.launchArguments = ["-selectEngine", "apple", "-uiTesting"]
            reset.launch()
            reset.terminate()
        }

        let chooseVoice = app.buttons["Choose voice"] // library sheet toolbar
        XCTAssertTrue(chooseVoice.waitForExistence(timeout: 10))
        chooseVoice.tap()

        let heart = app.buttons["voiceRow-af_heart"]
        let bella = app.buttons["voiceRow-af_bella"]
        XCTAssertTrue(heart.waitForExistence(timeout: 10), "Kokoro voices listed in the Voice section")
        XCTAssertTrue(app.buttons["voicePreview-af_bella"].exists, "preview button per voice")

        // Normalize to Heart first (the simulator may remember another voice).
        if !heart.isSelected { heart.tap(); _ = waitSelected(heart, timeout: 30) }
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        let before = frames(app)
        XCTAssertEqual(before.count, rowIDs.count, "all rows on screen: \(before.keys.sorted())")
        let heights = Set(before.filter { $0.key.hasPrefix("voiceRow") }.values.map { Int($0.height.rounded()) })
        XCTAssertEqual(heights.count, 1, "voice rows share one height: \(heights)")
        try shot("settings-voice-before.png")

        bella.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        try shot("settings-voice-switching.png")
        assertSameLayout(before, frames(app), "while switching/downloading")

        XCTAssertTrue(waitSelected(bella, timeout: 45), "Bella selected (pack downloaded)")
        XCTAssertFalse(heart.isSelected)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        try shot("settings-voice-after.png")
        assertSameLayout(before, frames(app), "after switching")

        // Preview button toggles without moving anything.
        app.buttons["voicePreview-bf_emma"].tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        assertSameLayout(before, frames(app), "while previewing")
        app.buttons["voicePreview-bf_emma"].tap()

        // Back to Heart (default) so the simulator state stays as it was.
        heart.tap()
        XCTAssertTrue(waitSelected(heart, timeout: 30))
        assertSameLayout(before, frames(app), "after switching back")

        // Language section (Automatic + manual list) for the record.
        app.swipeUp()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        XCTAssertTrue(app.buttons["languageRow-automatic"].waitForExistence(timeout: 3))
        try shot("settings-language.png")

        // Apple engine → Voice section lists system voices instead.
        app.swipeDown()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        app.buttons["engineRow-apple"].tap()
        XCTAssertTrue(app.buttons["voiceRow-system"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["voiceRow-af_heart"].exists)
        try shot("settings-apple-voices.png")
    }
}
