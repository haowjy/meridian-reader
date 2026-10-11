import XCTest

/// The five-slot bottom toolbar grid shared by Browse, the Reader sheet and Now Playing, the ⋯
/// menu's focus point, and the Now Playing bar's play button over the ⋯ slot.
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

    /// Browse `[‹][›][Search][Library][⋯]`, the Library `[＋][★][Search][Browser][⋯]`, the Reader `[🔖][ Listen ][⋯]` and Now Playing
    /// `[1×][⏮][▶︎][⏭][⋯]`: 5 equal, evenly spaced slots; slot N at the same x on every screen, ⋯ in
    /// slot 5 at the same spot; the bar's play button over ⋯.
    func testFiveSlotGridSharedByBrowseReaderAndNowPlaying() throws {
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
        for (s, frame) in browse.enumerated() {
            XCTAssertEqual(frame.midX, expected[s], accuracy: 1, "browse slot \(s + 1)")
        }

        // The Library: ＋ in slot 1, ★ Favorites in 2, Search in 3, Browser in 4, ⋯ in 5, on the
        // same grid.
        app.buttons["browseLibrary"].tap()
        XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 5))
        let library = [(0, "libraryAdd"), (1, "libraryFavorites"), (2, "librarySearch"), (3, "libraryBrowser"),
                       (4, "libraryMore")]
        for (s, id) in library {
            let frame = el(app, id).frame
            XCTAssertEqual(frame.midX, expected[s], accuracy: 1, "library slot \(s + 1): \(id)")
            XCTAssertEqual(frame.midY, browse[4].midY, accuracy: 1, "library \(id) on the browser's row")
        }
        assertMenuFocus(app, more: el(app, "libraryMore").frame, button: "libraryMore")
        app.buttons["libraryBrowser"].tap()
        XCTAssertTrue(icon.waitForExistence(timeout: 5))

        // The Reader: 🔖 in slot 1, ⋯ in slot 5, exactly where the browser's are.
        icon.tap()
        XCTAssertTrue(app.buttons["readerClose"].waitForExistence(timeout: 10))
        let save = el(app, "readerBookmark").frame
        let readerMore = app.buttons["readerMore"].frame
        XCTAssertEqual(save.midX, expected[0], accuracy: 1, "🔖 in slot 1")
        XCTAssertEqual(readerMore.midX, expected[4], accuracy: 1, "⋯ in slot 5")
        XCTAssertEqual(readerMore.midY, browse[4].midY, accuracy: 1, "⋯ at the browser's ⋯")
        XCTAssertEqual(save.midY, readerMore.midY, accuracy: 1, "one row")
        assertMenuFocus(app, more: readerMore, button: "readerMore")

        // Now Playing: the five-slot transport.
        app.buttons["listenPlayPause"].tap()
        XCTAssertTrue(el(app, "nowPlayingFrom").waitForExistence(timeout: 5))
        let play = app.buttons["listenPlayPause"]
        XCTAssertTrue(waitFor(8) { play.label == "Pause" }, "playing")
        let transport = [app.buttons["listenSpeed"], app.buttons["Previous paragraph"], play,
                         app.buttons["Next paragraph"], app.buttons["readerMore"]].map(\.frame)
        for (i, frame) in transport.enumerated() {
            XCTAssertEqual(frame.midX, expected[i], accuracy: 1, "Now Playing slot \(i + 1)")
            XCTAssertEqual(frame.midY, transport[4].midY, accuracy: 1, "one row")
        }
        for i in 1..<5 {
            XCTAssertEqual(transport[i].midX - transport[i - 1].midX, slot, accuracy: 1, "evenly spaced")
        }
        XCTAssertEqual(transport[4].midY, browse[4].midY, accuracy: 1, "⋯ same y")
        assertMenuFocus(app, more: transport[4], button: "readerMore")

        // The bar: play/pause over the ⋯ slot.
        app.buttons["readerClose"].tap()
        let barPlay = app.buttons["nowPlayingBarPlayPause"]
        XCTAssertTrue(barPlay.waitForExistence(timeout: 5))
        XCTAssertEqual(barPlay.frame.midX, expected[4], accuracy: 1, "bar play over ⋯")
        barPlay.tap()
    }

    /// ⋯ menu: the bottom-right big button's icon is slightly up and left of ⋯ (Safari feel), not
    /// dead-on. The morph still grows from ⋯.
    private func assertMenuFocus(_ app: XCUIApplication, more: CGRect, button: String) {
        app.buttons[button].tap()
        let focus = el(app, "moreMenuFocus")
        XCTAssertTrue(focus.waitForExistence(timeout: 3))
        wait(1.0)
        let window = app.windows.firstMatch.frame
        XCTAssertEqual(focus.frame.midX, more.midX - MorphMenuUITestOffset.width, accuracy: 1.5, "focus left of ⋯")
        XCTAssertEqual(focus.frame.midY, more.midY - MorphMenuUITestOffset.height, accuracy: 1.5, "focus above ⋯")
        XCTAssertLessThan(focus.frame.midX, more.midX - 4, "deliberately left of ⋯")
        XCTAssertLessThan(focus.frame.midY, more.midY - 4, "deliberately above ⋯")
        XCTAssertLessThanOrEqual(el(app, "moreMenuPanel").frame.maxX, window.maxX, "panel stays on screen")
        tapMenuDim(el(app, "moreMenuDismiss"))
        XCTAssertTrue(waitFor { !self.el(app, "moreMenuPanel").exists })
    }
}
