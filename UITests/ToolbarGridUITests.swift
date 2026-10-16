import XCTest

/// The five-slot bottom toolbar grid shared by Browse, the Library, the Reader sheet and Now
/// Playing, the ⋯ menu's focus point, the Now Playing bar's play button over the ⋯ slot, and the
/// band the browser and the Library share (D22), the same to the point on both.
final class ToolbarGridUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// Browse `[‹][›][🔖][🕘][⋯]`, the Library `[‹][›][＋][🕘][⋯]`, the Reader `[🔖][ Listen ][⋯]` and
    /// Now Playing `[🔖][⏮][▶︎][⏭][⋯]`: 5 equal, evenly spaced slots; slot N at the same x on every
    /// screen, ⋯ in slot 5 at the same spot; the bar's play button over ⋯.
    func testFiveSlotGridSharedByBrowseReaderAndNowPlaying() throws {
        let app = launchTestPages()
        let link = app.links["Next page"]
        XCTAssertTrue(link.waitForExistence(timeout: 20))
        link.tap()
        let icon = find(app, "addressReader")
        XCTAssertTrue(icon.waitForExistence(timeout: 5))

        let window = app.windows.firstMatch.frame
        let rowWidth = window.width - 2 * 12 // BottomChrome.horizontalMargin
        let slot = rowWidth / 5
        let expected = (0..<5).map { window.minX + 12 + slot * (CGFloat($0) + 0.5) }

        let browse = try XCTUnwrap(settledFrames(Self.browseSlots.map { find(app, $0) }), "the browser's toolbar")
        for (s, frame) in browse.enumerated() {
            XCTAssertEqual(frame.midX, expected[s], accuracy: 1, "browse slot \(s + 1)")
        }

        // The Library: the same roles in the same slots, on the same row.
        app.buttons["browseLibrary"].tap()
        XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 5))
        let library = try XCTUnwrap(settledFrames(Self.librarySlots.map { find(app, $0) }), "the Library's toolbar")
        for (s, id) in Self.librarySlots.enumerated() {
            let frame = library[s]
            XCTAssertEqual(frame.midX, expected[s], accuracy: 1, "library slot \(s + 1): \(id)")
            XCTAssertEqual(frame.midY, browse[4].midY, accuracy: 1, "library \(id) on the browser's row")
        }
        assertMenuFocus(app, more: find(app, "libraryMore").frame, button: "libraryMore")
        app.buttons["libraryBrowser"].tap()
        XCTAssertTrue(icon.waitForExistence(timeout: 5))

        // The Reader: 🔖 in slot 1, ⋯ in slot 5, exactly where the browser's are, once the sheet
        // has finished rising.
        icon.tap()
        XCTAssertTrue(app.buttons["readerClose"].waitForExistence(timeout: 10))
        let reader = try XCTUnwrap(settledFrames([find(app, "readerBookmark"), app.buttons["readerMore"]]),
                                   "the Reader has risen")
        let (save, readerMore) = (reader[0], reader[1])
        XCTAssertEqual(save.midX, expected[0], accuracy: 1, "🔖 in slot 1")
        XCTAssertEqual(readerMore.midX, expected[4], accuracy: 1, "⋯ in slot 5")
        XCTAssertEqual(readerMore.midY, browse[4].midY, accuracy: 1, "⋯ at the browser's ⋯")
        XCTAssertEqual(save.midY, readerMore.midY, accuracy: 1, "one row")
        assertMenuFocus(app, more: readerMore, button: "readerMore")

        // Now Playing: the five-slot transport.
        app.buttons["listenPlayPause"].tap()
        XCTAssertTrue(find(app, "nowPlayingHeader").waitForExistence(timeout: 5))
        let play = app.buttons["listenPlayPause"]
        XCTAssertTrue(eventually(8) { play.label == "Pause" }, "playing")
        let transport = try XCTUnwrap(settledFrames([app.buttons["nowPlayingBookmark"], app.buttons["Previous paragraph"], play,
                                                     app.buttons["Next paragraph"], app.buttons["nowPlayingMore"]]),
                                      "Now Playing has settled")
        for (i, frame) in transport.enumerated() {
            XCTAssertEqual(frame.midX, expected[i], accuracy: 1, "Now Playing slot \(i + 1)")
            XCTAssertEqual(frame.midY, transport[4].midY, accuracy: 1, "one row")
        }
        for i in 1..<5 {
            XCTAssertEqual(transport[i].midX - transport[i - 1].midX, slot, accuracy: 1, "evenly spaced")
        }
        XCTAssertEqual(transport[4].midY, browse[4].midY, accuracy: 1, "⋯ same y")
        assertMenuFocus(app, more: transport[4], button: "nowPlayingMore")

        // The bar: play/pause over the ⋯ slot.
        app.buttons["nowPlayingClose"].tap()
        let barPlay = app.buttons["nowPlayingBarPlayPause"]
        XCTAssertTrue(barPlay.waitForExistence(timeout: 5))
        let barFrame = try XCTUnwrap(settledFrames([barPlay])?.first, "the bar has settled")
        XCTAssertEqual(barFrame.midX, expected[4], accuracy: 1, "bar play over ⋯")
        barPlay.tap()
    }

    static let browseSlots = ["browseBack", "browseForward", "browseSave", "browseHistory", "browseMore"]
    static let librarySlots = ["libraryBack", "libraryForward", "libraryAdd", "libraryHistory", "libraryMore"]

    /// The band (D22): swap, Now Playing, field and every toolbar slot sit at the same frames in the
    /// Library and the browser, whatever the bar shows, with each slot present (dimmed when it has
    /// nothing to do) and the swap a full tap target.
    func testBandIsPixelStableAcrossLibraryAndBrowse() throws {
        let app = launchTestPages()
        XCTAssertTrue(app.links["Next page"].waitForExistence(timeout: 20))

        // What you hear, the page played last, or Nothing playing: whichever, always there.
        let bars = ["nowPlayingBar", "nowPlayingBarResume", "nowPlayingBarPlaceholder"]
        XCTAssertTrue(eventually { bars.contains { self.find(app, $0).exists } }, "the bar is always there")
        let nowPlaying = find(app, try XCTUnwrap(bars.first { find(app, $0).exists }))
        let field = find(app, "bandField")
        let browse = (swap: find(app, "browseLibrary").frame, bar: nowPlaying.frame, field: field.frame,
                      slots: Self.browseSlots.map { find(app, $0).frame })
        XCTAssertGreaterThanOrEqual(browse.swap.width, 44, "swap tap target")
        XCTAssertGreaterThanOrEqual(browse.swap.height, 44, "swap tap target")
        XCTAssertLessThan(browse.bar.maxY, browse.field.minY, "bar over the field")
        XCTAssertLessThan(browse.field.maxY, browse.slots[0].minY + 1, "field over the toolbar")
        // D23: Now Playing alone across row 1; the swap leads row 2, then the field.
        XCTAssertEqual(browse.swap.minX, browse.bar.minX, accuracy: 1, "swap at the band's leading edge")
        XCTAssertEqual(browse.swap.midY, browse.field.midY, accuracy: 1, "swap on the field's row")
        XCTAssertLessThan(browse.swap.width, 48, "swap is just its tap target")
        XCTAssertLessThanOrEqual(browse.swap.maxX, browse.field.minX + 1, "swap, then the field")
        XCTAssertLessThan(browse.field.minX - browse.swap.maxX, 6, "smallest gap before the field")
        XCTAssertEqual(browse.bar.maxX, browse.field.maxX, accuracy: 1, "bar and field share the trailing edge")
        XCTAssertEqual(browse.bar.minX, browse.slots[0].minX, accuracy: 1, "bar spans the whole toolbar width")

        app.buttons["browseLibrary"].tap()
        XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 5))
        XCTAssertTrue(eventually { self.find(app, "libraryBrowser").frame == browse.swap }, "swap frame")
        XCTAssertEqual(find(app, "libraryBrowser").frame, browse.swap, "swap frame")
        XCTAssertEqual(nowPlaying.frame, browse.bar, "Now Playing frame")
        XCTAssertEqual(field.frame, browse.field, "field frame")
        for (i, id) in Self.librarySlots.enumerated() {
            XCTAssertEqual(find(app, id).frame, browse.slots[i], "slot \(i + 1): \(id)")
        }
        XCTAssertTrue(app.textFields["librarySearchField"].exists, "Library search in the band's field")
        XCTAssertFalse(app.buttons["libraryBack"].isEnabled, "‹ dimmed at the Library's top")
        XCTAssertFalse(app.buttons["libraryForward"].isEnabled, "› dimmed in the Library")
        XCTAssertTrue(find(app, "libraryTabs").exists, "Everything / Favorites stay at the top")

        app.buttons["libraryBrowser"].tap()
        XCTAssertTrue(eventually { !app.libraryHome.exists })
        XCTAssertEqual(find(app, "browseLibrary").frame, browse.swap, "back: swap frame")
        XCTAssertEqual(nowPlaying.frame, browse.bar, "back: Now Playing frame")
        XCTAssertEqual(field.frame, browse.field, "back: field frame")
    }

    /// ⋯ menu: the bottom-right big button's icon is slightly up and left of ⋯ (Safari feel), not
    /// dead-on. The morph still grows from ⋯.
    private func assertMenuFocus(_ app: XCUIApplication, more: CGRect, button: String) {
        app.buttons[button].tap()
        let focus = find(app, "moreMenuFocus")
        XCTAssertTrue(focus.waitForExistence(timeout: 3))
        XCTAssertNotNil(settledFrames([focus, find(app, "moreMenuPanel")]), "the morph has finished")
        let window = app.windows.firstMatch.frame
        XCTAssertEqual(focus.frame.midX, more.midX - MorphMenuUITestOffset.width, accuracy: 1.5, "focus left of ⋯")
        XCTAssertEqual(focus.frame.midY, more.midY - MorphMenuUITestOffset.height, accuracy: 1.5, "focus above ⋯")
        XCTAssertLessThan(focus.frame.midX, more.midX - 4, "deliberately left of ⋯")
        XCTAssertLessThan(focus.frame.midY, more.midY - 4, "deliberately above ⋯")
        XCTAssertLessThanOrEqual(find(app, "moreMenuPanel").frame.maxX, window.maxX, "panel stays on screen")
        closeMenu(app)
    }
}
