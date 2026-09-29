import XCTest

/// Must match `MorphMenu.focusOffsetFromAnchor` (Nav J Safari nudge).
enum MorphMenuUITestOffset {
    static let width: CGFloat = 12
    static let height: CGFloat = 10
}

/// Nav I: the five-slot bottom toolbar grid shared by Browse and the reader, developer options
/// hidden, sub-paragraph (sentence) scrubbing.
final class NavIUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func wait(_ s: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }

    private func waitFor(_ timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            wait(0.1)
        }
        return condition()
    }

    // MARK: - Five-slot grid

    /// Browse `[‹][›][Search][ ][⋯]` and reader `[1×][⏮][▶︎][⏭][⋯]`: 5 equal, evenly spaced slots;
    /// slot N at the same x on both screens; the mini player's play button over ⋯.
    func testFiveSlotGridSharedByBrowseAndReader() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetBookmarks", "-browseTestPages", "-selectEngine", "apple"]
        app.launch()
        let link = app.links["Next page"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.tap()
        let icon = el(app, "addressReader")
        XCTAssertTrue(icon.waitForExistence(timeout: 5))

        let window = app.windows.firstMatch.frame
        let rowWidth = window.width - 2 * 12 // BottomChrome.horizontalMargin
        let slot = rowWidth / 5
        let expected = (0..<5).map { window.minX + 12 + slot * (CGFloat($0) + 0.5) }

        let browse = ["browseBack", "browseForward", "browseSearch", "browseMore"].map { el(app, $0).frame }
        let browseSlots = [0, 1, 2, 4]
        for (frame, s) in zip(browse, browseSlots) {
            XCTAssertEqual(frame.midX, expected[s], accuracy: 1, "browse slot \(s + 1)")
        }
        // Slot 4 is empty on Browse.
        let slot4 = app.buttons.allElementsBoundByIndex.filter {
            $0.frame.midY > browse[0].minY && $0.frame.midY < browse[0].maxY && abs($0.frame.midX - expected[3]) < slot / 2
        }
        XCTAssertTrue(slot4.isEmpty, "browse slot 4 is empty")

        icon.tap()
        XCTAssertTrue(app.buttons["readerClose"].waitForExistence(timeout: 10))
        let play = app.buttons["listenPlayPause"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        let reader = [app.buttons["listenSpeed"], app.buttons["Previous paragraph"], play,
                      app.buttons["Next paragraph"], app.buttons["readerMore"]].map(\.frame)
        for (i, frame) in reader.enumerated() {
            XCTAssertEqual(frame.midX, expected[i], accuracy: 1, "reader slot \(i + 1)")
            XCTAssertEqual(frame.midY, reader[4].midY, accuracy: 1, "one row")
        }
        for i in 1..<5 {
            XCTAssertEqual(reader[i].midX - reader[i - 1].midX, slot, accuracy: 1, "evenly spaced")
        }
        // Same x on both screens for the shared slots, ⋯ in slot 5 on both.
        for (frame, s) in zip(browse, browseSlots) {
            XCTAssertEqual(reader[s].midX, frame.midX, accuracy: 1, "slot \(s + 1) same x in Browse and the reader")
        }
        XCTAssertEqual(reader[4].midY, browse[3].midY, accuracy: 1, "⋯ same y")

        // ⋯ menu: Website/Reader icon is slightly up and left of ⋯ (Safari feel, Nav J) —
        // not dead-on overlap. Morph still grows from ⋯.
        app.buttons["readerMore"].tap()
        let focus = el(app, "moreMenuFocus")
        XCTAssertTrue(focus.waitForExistence(timeout: 3))
        wait(1.0)
        let dx = MorphMenuUITestOffset.width
        let dy = MorphMenuUITestOffset.height
        XCTAssertEqual(focus.frame.midX, reader[4].midX - dx, accuracy: 1.5, "focus left of ⋯")
        XCTAssertEqual(focus.frame.midY, reader[4].midY - dy, accuracy: 1.5, "focus above ⋯")
        XCTAssertLessThan(focus.frame.midX, reader[4].midX - 4, "deliberately left of ⋯")
        XCTAssertLessThan(focus.frame.midY, reader[4].midY - 4, "deliberately above ⋯")
        let panel = el(app, "moreMenuPanel").frame
        XCTAssertLessThanOrEqual(panel.maxX, window.maxX, "panel stays on screen")
        el(app, "moreMenuDismiss").tap()
        XCTAssertTrue(waitFor { !self.el(app, "moreMenuPanel").exists })

        // Mini player: play/pause sits over the ⋯ slot.
        play.tap()
        XCTAssertTrue(waitFor(8) { play.label == "Pause" }, "playing")
        app.buttons["readerClose"].tap()
        let mini = app.buttons["miniPlayerPlayPause"]
        XCTAssertTrue(mini.waitForExistence(timeout: 5))
        XCTAssertEqual(mini.frame.midX, expected[4], accuracy: 1, "mini player play over ⋯")
        mini.tap()
    }

    // MARK: - Developer options

    /// Release default (forced here with the launch argument): no Debug anywhere; the version row
    /// is in Voice settings.
    func testDeveloperOptionsOffHidesDebug() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedDemoArticle", "-uiTesting", "-openLibrary", "-resetBookmarks", "-reader.rateMultiplier", "1",
                               "-selectEngine", "apple",
                               "-reader.developerOptions", "NO", "-reader.listenDebugEnabled", "YES"]
        app.launch()
        let row = app.cells.staticTexts["Demo Listen Article"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.buttons["readerClose"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["listenPlayPause"].waitForExistence(timeout: 5))
        XCTAssertFalse(el(app, "listenBakeDebugChip").exists, "no Debug pill even with Listen debug stored on")

        app.buttons["readerMore"].tap()
        XCTAssertTrue(el(app, "moreVoice").waitForExistence(timeout: 3))
        XCTAssertFalse(el(app, "moreDebug").exists, "no Debug row in the reader ⋯")
        wait(0.6)
        el(app, "moreVoice").tap()
        XCTAssertTrue(app.navigationBars["Listen"].waitForExistence(timeout: 5))
        let version = el(app, "settingsVersionRow")
        for _ in 0..<6 where !version.exists { app.swipeUp() }
        XCTAssertTrue(version.waitForExistence(timeout: 3), "version row")
        XCTAssertFalse(el(app, "listenDebugEnabledToggle").exists, "no Listen debug section")

        // Long-press the version (2 s): developer options on, Listen debug comes back.
        version.press(forDuration: 2.4)
        let alert = app.alerts["Developer options on"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3), "confirmation")
        alert.buttons["OK"].tap()
        XCTAssertTrue(el(app, "listenDebugEnabledToggle").waitForExistence(timeout: 3), "debug section shown")
        for _ in 0..<4 where !(version.exists && version.isHittable) { app.swipeUp() }
        version.press(forDuration: 2.4)
        XCTAssertTrue(app.alerts["Developer options off"].waitForExistence(timeout: 3))
        app.alerts["Developer options off"].buttons["OK"].tap()
        XCTAssertTrue(waitFor { !self.el(app, "listenDebugEnabledToggle").exists })
    }

    func testDeveloperOptionsOffHidesBrowseDebugRow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetBookmarks", "-reader.developerOptions", "NO"]
        app.launch()
        let more = app.buttons["browseMore"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()
        XCTAssertTrue(el(app, "moreVoice").waitForExistence(timeout: 3))
        XCTAssertFalse(el(app, "moreDebug").exists, "no Debug row in the browser ⋯")
    }

    // MARK: - Sentence scrubbing

    private func position(_ app: XCUIApplication) -> (p: Int, o: Int)? {
        let marker = el(app, "readerScrubOffset")
        guard marker.waitForExistence(timeout: 2), let value = marker.value as? String else { return nil }
        let parts = value.split(separator: " ").compactMap { $0.split(separator: "=").last.flatMap { Int($0) } }
        return parts.count == 2 ? (parts[0], parts[1]) : nil
    }

    /// Release lands on the sentence under the finger (not the paragraph start); a small fine
    /// scrub back lands on that sentence's start; a paused seek stays paused and Play starts there.
    func testScrubLandsOnSentenceAndPausedStaysPaused() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedDemoArticle", "-uiTesting", "-openLibrary", "-resetBookmarks", "-reader.rateMultiplier", "1",
                               "-selectEngine", "apple"]
        app.launch()
        let row = app.cells.staticTexts["Demo Listen Article"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let scrubber = el(app, "readerScrubber")
        XCTAssertTrue(scrubber.waitForExistence(timeout: 5))
        wait(1.0) // sentence map built

        // Not loaded: a tap in the middle of paragraph 2 → its 2nd sentence ("Extra sentences…").
        scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.52, dy: 0.5)).tap()
        XCTAssertTrue(waitFor { self.position(app)?.p == 1 }, "paragraph 2, got \(String(describing: position(app)))")
        let sentence = try XCTUnwrap(position(app)).o
        XCTAssertGreaterThan(sentence, 0, "a sentence inside the paragraph, not its start")
        XCTAssertEqual(scrubber.value as? String, "Paragraph 2 of 3")

        // Play starts at that sentence (Apple voice speaks from it), then pause.
        let play = app.buttons["listenPlayPause"]
        play.tap()
        XCTAssertTrue(waitFor(8) { play.label == "Pause" }, "playing")
        wait(1.0)
        let playing = try XCTUnwrap(position(app))
        XCTAssertEqual(playing.p, 1)
        XCTAssertGreaterThanOrEqual(playing.o, sentence, "played from the sentence, not the paragraph start")
        play.tap()
        XCTAssertTrue(waitFor(5) { play.label == "Play" })

        // Grab the thumb and slide straight up into fine-scrub range, then release: the thumb
        // doesn't jump (relative grab) and release lands on the start of the sentence it's in.
        let start = scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.52, dy: 0.5))
        start.press(forDuration: 0.3, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -200)),
                    withVelocity: .slow, thenHoldForDuration: 0.2)
        wait(0.8)
        XCTAssertEqual(play.label, "Play", "paused seek stays paused")
        let after = try XCTUnwrap(position(app))
        XCTAssertEqual(after.p, 1, "still paragraph 2")
        XCTAssertEqual(after.o, sentence, "back at the sentence start (not the paragraph start)")
    }

    // MARK: - Speed

    /// A speed change mid-paragraph keeps going from the current spot (no paragraph restart).
    func testSpeedChangeKeepsThePosition() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedDemoArticle", "-uiTesting", "-openLibrary", "-resetBookmarks", "-reader.rateMultiplier", "1",
                               "-selectEngine", "apple"]
        app.launch()
        let row = app.cells.staticTexts["Demo Listen Article"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let play = app.buttons["listenPlayPause"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()
        XCTAssertTrue(waitFor(8) { play.label == "Pause" }, "playing")
        XCTAssertTrue(waitFor(8) { (self.position(app)?.o ?? 0) > 20 }, "moving through paragraph 1")
        let before = try XCTUnwrap(position(app))

        let speed = app.buttons["listenSpeed"]
        speed.tap()
        let option = el(app, "listenSpeedOption-1.5×")
        XCTAssertTrue(option.waitForExistence(timeout: 3))
        option.tap()
        XCTAssertTrue(waitFor(3) { speed.label == "Speed 1.5×" })
        wait(0.3)
        let after = try XCTUnwrap(position(app))
        // Same spot or later (it may have moved on into the next paragraph) — never back to the start.
        XCTAssertTrue(after.p > before.p || (after.p == before.p && after.o >= before.o - 2),
                      "didn't jump back to the paragraph start: \(before) → \(after)")
        XCTAssertEqual(play.label, "Pause", "still playing")
        play.tap()
    }
}
