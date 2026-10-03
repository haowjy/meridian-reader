import XCTest

/// The five-slot bottom toolbar grid shared by Browse and the reader, the ⋯ menu's focus point,
/// and the mini player's play button over the ⋯ slot.
final class ToolbarGridUITests: XCTestCase {
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

    /// Browse `[‹][›][Search][Library][⋯]` and reader `[1×][⏮][▶︎][⏭][⋯]`: 5 equal, evenly spaced slots;
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

        let browse = ["browseBack", "browseForward", "browseSearch", "browseLibrary", "browseMore"]
            .map { el(app, $0).frame }
        let browseSlots = [0, 1, 2, 3, 4]
        for (frame, s) in zip(browse, browseSlots) {
            XCTAssertEqual(frame.midX, expected[s], accuracy: 1, "browse slot \(s + 1)")
        }

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
        XCTAssertEqual(reader[4].midY, browse[4].midY, accuracy: 1, "⋯ same y")

        // ⋯ menu: Website/Reader icon is slightly up and left of ⋯ (Safari feel) —
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
}
