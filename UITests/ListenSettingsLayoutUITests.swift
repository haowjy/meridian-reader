import XCTest

/// Settings › Listening › Voice: switching voices (and the download in progress) must not change
/// row heights or move rows. Records every voice row frame before and after switching the Kokoro
/// voice and saves screenshots to /tmp.
final class ListenSettingsLayoutUITests: XCTestCase {
    private let shotDir = URL(fileURLWithPath: "/tmp/reader-voiceui")
    private let rowIDs = ["voiceRow-af_heart", "voiceRow-af_bella", "voiceRow-bf_emma",
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
        let app = launch(UITestSetup(["-openLibrary"], engine: "local.kokoro"))

        // The Library's ⋯ › Settings › Voice.
        let more = app.buttons["libraryMore"]
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        more.tap()
        tapMenuRow(app, "moreSettings")
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        openSettingsRow(app, "settingsVoice")

        let heart = app.buttons["voiceRow-af_heart"]
        let bella = app.buttons["voiceRow-af_bella"]
        XCTAssertTrue(heart.waitForExistence(timeout: 10), "Kokoro voices listed on the Voice page")
        XCTAssertTrue(app.buttons["voicePreview-af_bella"].exists, "preview button per voice")

        XCTAssertTrue(eventually(10) { heart.isSelected }, "a fresh install's voice, Heart")
        XCTAssertNotNil(settledFrames(rowIDs.map { app.buttons[$0] }), "the rows settle")
        let before = frames(app)
        XCTAssertEqual(before.count, rowIDs.count, "all rows on screen: \(before.keys.sorted())")
        let heights = Set(before.filter { $0.key.hasPrefix("voiceRow") }.values.map { Int($0.height.rounded()) })
        XCTAssertEqual(heights.count, 1, "voice rows share one height: \(heights)")
        try shot("settings-voice-before.png")

        bella.tap()
        idle(0.15) // mid-switch, while Bella's pack downloads
        try shot("settings-voice-switching.png")
        assertSameLayout(before, frames(app), "while switching/downloading")

        XCTAssertTrue(eventually(45) { bella.isSelected }, "Bella selected (pack downloaded)")
        XCTAssertFalse(heart.isSelected)
        XCTAssertNotNil(settledFrames(rowIDs.map { app.buttons[$0] }), "the rows settle")
        try shot("settings-voice-after.png")
        assertSameLayout(before, frames(app), "after switching")

        // Preview button toggles without moving anything.
        app.buttons["voicePreview-bf_emma"].tap()
        idle(0.3) // while the preview plays
        assertSameLayout(before, frames(app), "while previewing")
        app.buttons["voicePreview-bf_emma"].tap()

        // Back to Heart.
        heart.tap()
        XCTAssertTrue(eventually(30) { heart.isSelected })
        assertSameLayout(before, frames(app), "after switching back")

        // The Language page (Automatic + manual list) for the record.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        openSettingsRow(app, "settingsLanguage")
        let automatic = app.buttons["languageRow-automatic"]
        XCTAssertTrue(automatic.waitForExistence(timeout: 3))
        XCTAssertNotNil(settledFrames([automatic]), "the page has come in")
        try shot("settings-language.png")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // Apple engine → the Voice page lists system voices instead.
        openSettingsRow(app, "engineRow-apple")
        XCTAssertTrue(eventually { app.buttons["engineRow-apple"].isSelected }, "Apple selected")
        openSettingsRow(app, "settingsVoice")
        XCTAssertTrue(app.buttons["voiceRow-system"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["voiceRow-af_heart"].exists)
        try shot("settings-apple-voices.png")
    }
}
