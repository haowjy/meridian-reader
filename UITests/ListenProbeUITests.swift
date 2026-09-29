import XCTest

final class ListenProbeUITests: XCTestCase {
    /// "N/M" from the scrubber's accessibility value ("Paragraph N of M").
    private func indexValue(_ app: XCUIApplication) -> String? {
        let el = app.descendants(matching: .any)["readerScrubber"]
        guard el.waitForExistence(timeout: 2) else { return nil }
        let words = "\(el.value ?? "")".split(separator: " ")
        guard words.count == 4 else { return nil }
        return "\(words[1])/\(words[3])"
    }

    private func waitForLabel(_ element: XCUIElement, _ label: String, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.label == label { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return element.label == label
    }

    private func waitForIndexPrefix(_ app: XCUIApplication, _ prefix: String, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let value = indexValue(app), value.hasPrefix(prefix) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return indexValue(app)?.hasPrefix(prefix) == true
    }

    func testPlaySkipSpeedAndParagraphTap() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedDemoArticle", "-uiTesting", "-openLibrary", "-reader.rateMultiplier", "1"]
        app.launch()

        XCTAssertTrue(app.cells.staticTexts["Demo Listen Article"].waitForExistence(timeout: 5))
        app.cells.staticTexts["Demo Listen Article"].tap()

        let playPause = app.buttons["listenPlayPause"]
        XCTAssertTrue(playPause.waitForExistence(timeout: 5))

        playPause.tap()
        XCTAssertTrue(waitForLabel(playPause, "Pause"), "Play starts")
        XCTAssertTrue(waitForIndexPrefix(app, "1/"), "Index 1, got \(indexValue(app) ?? "nil")")

        // Pause so TTS cannot race skip checks. Index stays while session is prepared.
        playPause.tap()
        XCTAssertTrue(waitForLabel(playPause, "Play"), "Paused")
        XCTAssertTrue(waitForIndexPrefix(app, "1/"), "Index still visible while paused")

        app.buttons["Next paragraph"].tap()
        XCTAssertTrue(waitForIndexPrefix(app, "2/"), "Next -> 2, got \(indexValue(app) ?? "nil")")

        app.buttons["Previous paragraph"].tap()
        XCTAssertTrue(waitForIndexPrefix(app, "1/"), "Previous -> 1, got \(indexValue(app) ?? "nil")")

        // Scrubber seek while paused: moves the playhead, stays paused (no stop-and-reload).
        let scrubber = app.descendants(matching: .any)["readerScrubber"]
        // A tap on the track scrubs + commits there (the three demo paragraphs are similar length).
        scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(waitForIndexPrefix(app, "2/"), "Scrub -> 2, got \(indexValue(app) ?? "nil")")
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        XCTAssertEqual(playPause.label, "Play", "paused seek stays paused")
        scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5)).tap()
        XCTAssertTrue(waitForIndexPrefix(app, "1/"), "Scrub back -> 1, got \(indexValue(app) ?? "nil")")

        let speed = app.buttons["listenSpeed"]
        let before = speed.label
        speed.tap()
        // Label reads "Speed 1×".
        let optionID = before.hasSuffix(" 1×") ? "listenSpeedOption-1.25×" : "listenSpeedOption-1×"
        let option = app.descendants(matching: .any)[optionID]
        if option.waitForExistence(timeout: 3) {
            option.tap()
        } else if app.buttons["1.25×"].waitForExistence(timeout: 2) {
            app.buttons["1.25×"].tap()
        } else if app.buttons["1×"].waitForExistence(timeout: 1) {
            app.buttons["1×"].tap()
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        XCTAssertNotEqual(before, speed.label, "Speed popover should change rate")

        // The listen bar's rightmost slot is the reader ⋯ menu (voice settings live there).
        XCTAssertTrue(app.buttons["readerMore"].waitForExistence(timeout: 3))

        // Jump mode: off by default; the button shows the hint, Cancel hides it.
        let jump = app.buttons["listenJump"]
        XCTAssertTrue(jump.waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["listenJumpHint"].exists)
        jump.tap()
        XCTAssertTrue(app.descendants(matching: .any)["listenJumpHint"].waitForExistence(timeout: 3))
        app.buttons["listenJumpCancel"].tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        XCTAssertFalse(app.descendants(matching: .any)["listenJumpHint"].exists)
        jump.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        let shot = XCUIScreen.main.screenshot()
        try? shot.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/reader_jump_mode.png"))
    }
}
