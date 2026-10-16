import XCTest

/// Where the playhead lands: a scrub release lands on the sentence under the finger, a paused
/// seek stays paused, and a speed change keeps the current spot.
final class PlayheadPositionUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func position(_ app: XCUIApplication) -> (p: Int, o: Int)? {
        let marker = find(app, "readerScrubOffset")
        guard marker.waitForExistence(timeout: 2), let value = marker.value as? String else { return nil }
        let parts = value.split(separator: " ").compactMap { $0.split(separator: "=").last.flatMap { Int($0) } }
        return parts.count == 2 ? (parts[0], parts[1]) : nil
    }

    /// Release lands on the sentence under the finger (not the paragraph start); a small fine
    /// scrub back lands on that sentence's start; a paused seek stays paused and Play starts there.
    /// The scrubber is Now Playing's: Listen in the Reader, then pause.
    func testScrubLandsOnSentenceAndPausedStaysPaused() throws {
        let app = launch(["-seedDemoArticle", "-openLibrary"])
        let row = app.cells.staticTexts["Demo Listen Article"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let play = app.buttons["listenPlayPause"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap() // Listen: the Reader turns into Now Playing
        XCTAssertTrue(eventually(8) { play.label == "Pause" }, "playing")
        play.tap()
        XCTAssertTrue(eventually(5) { play.label == "Play" }, "paused")
        let scrubber = find(app, "readerScrubber")
        XCTAssertTrue(scrubber.waitForExistence(timeout: 5))
        idle(1.0) // sentence map built

        // Paused: a tap in the middle of paragraph 2 → its 2nd sentence ("Extra sentences…").
        scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.52, dy: 0.5)).tap()
        XCTAssertTrue(eventually { self.position(app)?.p == 1 }, "paragraph 2, got \(String(describing: position(app)))")
        let sentence = try XCTUnwrap(position(app)).o
        XCTAssertGreaterThan(sentence, 0, "a sentence inside the paragraph, not its start")
        XCTAssertEqual(scrubber.value as? String, "Paragraph 2 of 3")
        XCTAssertEqual(play.label, "Play", "a paused seek stays paused")

        // Play starts at that sentence (Apple voice speaks from it), then pause.
        play.tap()
        XCTAssertTrue(eventually(8) { play.label == "Pause" }, "playing")
        idle(1.0) // long enough to tell a start at the sentence from one at the paragraph's start
        let playing = try XCTUnwrap(position(app))
        XCTAssertEqual(playing.p, 1)
        XCTAssertGreaterThanOrEqual(playing.o, sentence, "played from the sentence, not the paragraph start")
        play.tap()
        XCTAssertTrue(eventually(5) { play.label == "Play" })

        // Grab the thumb and slide straight up into fine-scrub range, then release: the thumb
        // doesn't jump (relative grab) and release lands on the start of the sentence it's in.
        let start = scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.52, dy: 0.5))
        start.press(forDuration: 0.3, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -200)),
                    withVelocity: .slow, thenHoldForDuration: 0.2)
        _ = eventually(3) { self.position(app).map { $0.p == 1 && $0.o == sentence } == true }
        XCTAssertEqual(play.label, "Play", "paused seek stays paused")
        let after = try XCTUnwrap(position(app))
        XCTAssertEqual(after.p, 1, "still paragraph 2")
        XCTAssertEqual(after.o, sentence, "back at the sentence start (not the paragraph start)")
    }

    /// A speed change mid-paragraph keeps going from the current spot (no paragraph restart).
    func testSpeedChangeKeepsThePosition() throws {
        let app = launch(["-seedDemoArticle", "-openLibrary"])
        let row = app.cells.staticTexts["Demo Listen Article"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let play = app.buttons["listenPlayPause"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()
        XCTAssertTrue(eventually(8) { play.label == "Pause" }, "playing")
        XCTAssertTrue(eventually(8) { (self.position(app)?.o ?? 0) > 20 }, "moving through paragraph 1")
        let before = try XCTUnwrap(position(app))

        let speed = app.buttons["listenSpeed"]
        speed.tap()
        let option = find(app, "listenSpeedOption-1.5×")
        XCTAssertTrue(option.waitForExistence(timeout: 3))
        option.tap()
        XCTAssertTrue(eventually(3) { speed.label == "Speed 1.5×" })
        idle(0.3) // a restart would have moved back by now
        let after = try XCTUnwrap(position(app))
        // Same spot or later (it may have moved on into the next paragraph) — never back to the start.
        XCTAssertTrue(after.p > before.p || (after.p == before.p && after.o >= before.o - 2),
                      "didn't jump back to the paragraph start: \(before) → \(after)")
        XCTAssertEqual(play.label, "Pause", "still playing")
        play.tap()
    }
}
