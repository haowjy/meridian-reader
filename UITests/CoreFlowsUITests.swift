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

    /// Listen, from a Library row: its tap plays it, and the Listen segment opens what plays.
    private func openListen(_ app: XCUIApplication) {
        tapWhenHittable(libraryCell(app, "Demo Listen Article"))
        tapWhenHittable(app.buttons["chromeListen"])
        XCTAssertTrue(appears(app.buttons["chromeReaderMore"], timeout: 10), "the Listen destination, in place")
    }

    /// Read from the Library opens the page in place like the Browser's reader mode: the Library stays
    /// the lit segment, nothing plays, and ‹ puts the Library back.
    func testLibraryReadOpensInPlaceAndNeverLeavesTheLibrary() throws {
        let app = launchLibrary()
        tapWhenHittable(libraryCell(app, "Demo Listen Article").buttons["rowMore"])
        tapWhenHittable(find(app, "menuRead"))
        XCTAssertTrue(appears(app.otherElements["browsePageReader"], timeout: 10), "the page's text, in place")
        XCTAssertTrue(app.buttons["chromeLibrary"].isSelected, "the Library stays lit")
        XCTAssertFalse(app.buttons["chromeListen"].isSelected, "not the Listen destination")
        XCTAssertFalse(app.buttons["chromeReaderMore"].exists, "no Listen screen")
        XCTAssertFalse(app.otherElements["readingPlayerCard"].exists, "no player card")
        XCTAssertFalse(app.buttons["listenPlayPause"].exists, "nothing plays")

        tapWhenHittable(app.buttons["libraryReaderBack"])
        XCTAssertTrue(appears(app.libraryHome, timeout: 5), "back to the Library")
        XCTAssertFalse(app.otherElements["browsePageReader"].exists)

        tapWhenHittable(libraryCell(app, "Demo Listen Article").buttons["rowMore"])
        tapWhenHittable(find(app, "menuRead"))
        tapWhenHittable(app.buttons["pageReaderListen"])
        XCTAssertTrue(appears(app.buttons["listenPlayPause"], timeout: 10), "Listen is the one way into Listen")
        XCTAssertTrue(app.buttons["chromeListen"].isSelected)
    }

    /// The Listen screen opened from the Library is in place under the chrome: scrolling down folds the
    /// chrome to one row and scrolling up leaves it folded, a tap in the middle of the text removes
    /// it and another brings it back, and there is no Close pill.
    func testInPlaceReaderFoldsOnScrollAndFullScreenIsAMiddleTap() throws {
        let app = launchLibrary()
        openListen(app)
        let more = app.buttons["chromeReaderMore"]

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
        idle(0.5)
        XCTAssertTrue(icon.exists && !pill.exists, "scrolling up gives no row back")
        text.tap()
        XCTAssertTrue(eventually { !icon.exists && !pill.exists && !more.exists }, "a middle tap removes the chrome")
        text.tap()
        XCTAssertTrue(eventually { icon.exists && more.exists }, "another brings it back, still folded")
        XCTAssertFalse(pill.exists)
    }

    /// Jump to Audio is for the bars up only (C128): scrolled away from the audio the pill shows,
    /// a middle tap into full screen removes it at once, and leaving full screen brings it back.
    func testJumpToAudioLeavesWithFullScreen() throws {
        let app = launch(["-browseTestPages"])
        let link = app.links["Next page"]
        XCTAssertTrue(appears(link, timeout: 10))
        link.tap()
        tapWhenHittable(find(app, "addressReader"))
        tapWhenHittable(app.buttons["pageReaderListen"])
        XCTAssertTrue(appears(app.buttons["listenPlayPause"], timeout: 10), "Now Playing")

        let jump = app.buttons["nowPlayingJumpToAudio"]
        let text = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        let low = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        low.press(forDuration: 0.05, thenDragTo: top, withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertTrue(appears(jump, timeout: 5), "scrolled away from the audio: the pill")

        text.tap()
        XCTAssertTrue(eventually(1) { !jump.exists }, "full screen removes the pill at once")
        Thread.sleep(forTimeInterval: 1)
        XCTAssertFalse(jump.exists, "and it stays away through full screen")
        text.tap()
        XCTAssertTrue(appears(jump, timeout: 3), "leaving full screen brings it back")
    }

    /// Voice and the bookmark sit pinned at the card's trailing edge (the mockup's card), the title
    /// keeping the room in between.
    func testCardVoiceAndBookmarkArePinnedFarRight() throws {
        let app = launchLibrary()
        openListen(app)

        let card = find(app, "readingPlayerCard")
        XCTAssertTrue(appears(card, timeout: 5), "the player card")
        // The page that plays is Now Playing's card, a page that does not is the Reader's.
        let playing = app.buttons["nowPlayingVoice"].exists
        let voice = app.buttons[playing ? "nowPlayingVoice" : "readerVoice"]
        let bookmark = app.buttons[playing ? "nowPlayingBookmark" : "readerBookmark"]
        XCTAssertTrue(appears(voice, timeout: 5), "Voice on the card")
        XCTAssertTrue(appears(bookmark, timeout: 5), "the bookmark on the card")
        XCTAssertGreaterThan(voice.frame.minX, card.frame.midX, "Voice is on the right half")
        XCTAssertLessThanOrEqual(card.frame.maxX - bookmark.frame.maxX, 20, "the bookmark is flush right")
        XCTAssertLessThan(bookmark.frame.minX - voice.frame.maxX, 20, "Voice sits right beside the bookmark")
    }

    /// Aa on the Reader's player card opens the text appearance panel, and a choice in it changes
    /// the page and leaves the panel open.
    func testAaOnTheReaderCardOpensTheAppearancePanel() throws {
        let app = launchLibrary()
        openListen(app)

        let aa = app.buttons["textAppearanceButton"]
        XCTAssertTrue(appears(aa, timeout: 5), "Aa on the card")
        tapWhenHittable(aa)
        let panel = find(app, "textAppearancePanel")
        XCTAssertTrue(appears(panel, timeout: 5), "the panel opens")
        // The whole panel fits (it opens above Aa, which sits at the foot of the screen).
        XCTAssertGreaterThan(panel.frame.height, 250, "the panel is not squeezed")
        let sans = find(app, "readingFont-sans")
        XCTAssertTrue(sans.isHittable, "every control of the panel is reachable")
        sans.tap()
        idle(1)
        XCTAssertTrue(panel.exists, "a choice leaves it open")
    }
}
