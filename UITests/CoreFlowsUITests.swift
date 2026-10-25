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
        idle(1)  // Now Playing cross-fades in; a tap during it doesn't land
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

    /// The Reader is a destination under the chrome: scrolling down collapses it to one row, a tap in
    /// the middle of the text removes the whole chrome and another brings it back (collapsed, as it
    /// was), and there is no Close pill.
    func testReaderCollapsesOnScrollAndFullScreenIsAMiddleTap() throws {
        let app = launch(["-browseTestPages"])
        let link = app.links["Next page"]
        XCTAssertTrue(appears(link, timeout: 10))
        link.tap()
        tapWhenHittable(find(app, "addressReader"))
        let listen = app.buttons["pageReaderListen"]
        XCTAssertTrue(appears(listen, timeout: 10))
        tapWhenHittable(listen)
        XCTAssertTrue(appears(app.buttons["listenPlayPause"], timeout: 10), "Now Playing, in place")

        let pill = app.buttons["chromeLibrary"], icon = app.buttons["chromeScreenIcon"]
        XCTAssertTrue(pill.exists && !icon.exists, "expanded: the pill")
        XCTAssertFalse(app.buttons["nowPlayingClose"].exists || app.buttons["readerClose"].exists, "no Close pill")

        let text = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        text.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)))
        XCTAssertTrue(eventually { icon.exists && !pill.exists }, "scrolling down collapses to one row")

        idle(1)  // a touch that stops a scroll is never a tap
        text.tap()
        XCTAssertTrue(eventually { !icon.exists && !pill.exists && !app.buttons["chromePlayPause"].exists },
                      "a middle tap removes the chrome")
        text.tap()
        XCTAssertTrue(eventually { icon.exists }, "another brings it back, still collapsed")
    }
}
