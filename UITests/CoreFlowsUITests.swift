import XCTest

/// The three end-to-end flows kept as automated checks; everything else is verified by probing
/// the running app. Offline: the `reader-test://` pages and the demo seeds.
final class CoreFlowsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// A browsed page, played from its Reader and saved mid-listen: Save keeps it playing in Now
    /// Playing, and the Library then holds exactly one row for it.
    func testSaveAndPlayABrowsedArticle() throws {
        let app = launch(["-browseTestPages"])
        let link = app.links["Next page"]
        XCTAssertTrue(appears(link, timeout: 10))
        link.tap()
        let reader = find(app, "addressReader")
        XCTAssertTrue(appears(reader, timeout: 10), "📄 on the article page")
        tapWhenHittable(reader)

        // The page's text replaces the page; Listen there plays it in Now Playing.
        let listen = app.buttons["pageReaderListen"]
        XCTAssertTrue(appears(listen, timeout: 10), "the page's reader view")
        tapWhenHittable(listen)
        let play = app.buttons["listenPlayPause"]
        XCTAssertTrue(appears(play, timeout: 10), "Now Playing")
        XCTAssertTrue(eventually(8) { play.exists && play.label == "Pause" }, "playing")
        let bookmark = app.buttons["nowPlayingBookmark"]
        XCTAssertEqual(bookmark.value as? String, "Not saved")
        XCTAssertTrue(eventually { bookmark.isEnabled }, "the bookmark takes taps once the page's text has loaded")
        bookmark.tap()
        XCTAssertTrue(eventually { bookmark.value as? String == "Saved" })
        XCTAssertEqual(play.label, "Pause", "Save must not stop playback")
        XCTAssertTrue(play.exists, "Save must not leave Now Playing")
        play.tap()

        tapWhenHittable(app.buttons["chromeLibrary"])
        XCTAssertTrue(appears(app.libraryHome, timeout: 5))
        let rows = app.cells.staticTexts.matching(NSPredicate(format: "label == %@", "Second page"))
        XCTAssertTrue(appears(rows.firstMatch, timeout: 5))
        XCTAssertEqual(rows.count, 1, "one row per page")
    }

    /// The Reader opened from the Library is in place under the chrome: scrolling down folds the
    /// chrome to one row and scrolling up unfolds it again, a tap in the middle of the text removes
    /// it and another brings it back, and there is no Close pill.
    func testInPlaceReaderFoldsOnScrollAndFullScreenIsAMiddleTap() throws {
        let app = launchLibrary()
        // A row's tap plays it; its menu's Read opens the Reader.
        tapWhenHittable(libraryCell(app, "Demo Listen Article").buttons["rowMore"])
        tapWhenHittable(find(app, "menuRead"))
        let more = app.buttons["chromeReaderMore"]
        XCTAssertTrue(appears(more, timeout: 10), "the Reader, in place")

        let pill = app.buttons["chromeLibrary"], icon = app.buttons["chromeScreenIcon"]
        XCTAssertTrue(pill.exists && !icon.exists, "expanded: the pill")
        XCTAssertTrue(app.otherElements["readingPlayerCard"].exists, "the player card is above it")
        XCTAssertFalse(app.buttons["readerClose"].exists, "no Close pill")

        // Each drag ends held still, so nothing glides on and a later tap is a tap.
        let text = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        let low = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        text.press(forDuration: 0.05, thenDragTo: top, withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertTrue(eventually { icon.exists && !pill.exists }, "scrolling down folds to one row")

        top.press(forDuration: 0.05, thenDragTo: low, withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertTrue(eventually { pill.exists && !icon.exists }, "scrolling up unfolds it: the Reader scrolls like the rest")

        text.press(forDuration: 0.05, thenDragTo: top, withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertTrue(eventually { icon.exists && !pill.exists })
        text.tap()
        XCTAssertTrue(eventually { !icon.exists && !pill.exists && !more.exists }, "a middle tap removes the chrome")
        text.tap()
        XCTAssertTrue(eventually { icon.exists && more.exists }, "another brings it back, still folded")
        XCTAssertFalse(pill.exists)
    }
}
