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

    /// Listen opened from the Library is in place under the chrome: scrolling never folds it (the card and
    /// the row stay), its row has no ▶ (the card has one) while the Library's does, a tap in the middle
    /// of the text removes everything and another brings it back, and there is no Close pill.
    func testListenNeverFoldsOnScrollAndHasNoPlayOnItsRow() throws {
        let app = launchLibrary()
        openListen(app)
        let more = app.buttons["chromeReaderMore"]

        let pill = app.buttons["chromeLibrary"], icon = app.buttons["chromeScreenIcon"], rowPlay = app.buttons["chromePlayPause"]
        let card = app.otherElements["readingPlayerCard"]
        XCTAssertTrue(pill.exists && !icon.exists, "expanded: the pill")
        XCTAssertTrue(card.exists, "the player card is above it")
        XCTAssertFalse(rowPlay.exists, "Listen's row has no ▶: the card's is the one")
        XCTAssertTrue(app.buttons["listenPlayPause"].exists)
        XCTAssertFalse(app.buttons["readerClose"].exists, "no Close pill")

        // Each drag ends held still, so nothing glides on and a later tap is a tap.
        let text = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        let low = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        for _ in 0..<2 {
            text.press(forDuration: 0.05, thenDragTo: top, withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        idle(0.6)
        XCTAssertTrue(pill.exists && !icon.exists && card.exists && more.exists, "scrolling down leaves the chrome as it was")
        top.press(forDuration: 0.05, thenDragTo: low, withVelocity: .slow, thenHoldForDuration: 0.3)
        idle(0.4)
        XCTAssertTrue(pill.exists && card.exists, "and scrolling up")

        text.tap()
        XCTAssertTrue(eventually { !pill.exists && !card.exists && !more.exists }, "a middle tap removes the chrome")
        text.tap()
        XCTAssertTrue(eventually { pill.exists && card.exists && more.exists }, "another brings it back, expanded")
        XCTAssertFalse(icon.exists)
    }

    /// The Library's row keeps ▶ once a page has played, and Listen's does not.
    func testPlayStaysOnTheLibraryRowButNotListens() throws {
        let app = launchLibrary()
        openListen(app)
        XCTAssertFalse(app.buttons["chromePlayPause"].exists, "Listen: no ▶ on the row")
        tapWhenHittable(app.buttons["chromeLibrary"])
        XCTAssertTrue(appears(app.libraryHome, timeout: 5))
        XCTAssertTrue(appears(app.buttons["chromePlayPause"], timeout: 5), "Library: ▶ on the row")
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

    /// A drag on the card's scrubber that leaves the track vertically (a long way down, past the
    /// card, and released there) leaves no scrub behind: the bubble and its speed chip are gone,
    /// and the title row's buttons are in reach again.
    func testScrubThatLeavesTheTrackVerticallyEndsCleanly() throws {
        let app = launchLibrary()
        openListen(app)

        let scrubber = app.otherElements["readerScrubber"].exists ? app.otherElements["readerScrubber"] : find(app, "readerScrubber")
        XCTAssertTrue(appears(scrubber, timeout: 5), "the card's scrubber")
        let start = scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        let farBelow = scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 12))
        start.press(forDuration: 0.3, thenDragTo: farBelow)
        idle(1)
        XCTAssertFalse(find(app, "readerScrubBubble").exists, "no bubble once the finger is up")
        XCTAssertFalse(find(app, "readerScrubSpeed").exists, "no speed chip once the finger is up")
        let playing = app.buttons["nowPlayingVoice"].exists
        XCTAssertTrue(app.buttons[playing ? "nowPlayingVoice" : "readerVoice"].isHittable, "Voice is not covered")
    }

    /// The card's title block (art, title, source and time left) is inert: a tap on it, even on
    /// its lower edge beside the scrubber, never seeks and never reaches the page behind (a tap there hides the chrome).
    func testTapOnTheCardTitleBlockNeverSeeks() throws {
        let app = launchLibrary()
        openListen(app)

        let card = find(app, "readingPlayerCard")
        XCTAssertTrue(appears(card, timeout: 5))
        let scrubber = find(app, "readerScrubber")
        XCTAssertTrue(appears(scrubber, timeout: 5))
        // Paused, so the position can only move by a seek.
        let play = app.buttons["listenPlayPause"]
        if play.exists, play.label == "Pause" { play.tap() }
        XCTAssertTrue(eventually(5) { play.label == "Play" }, "paused")
        let before = scrubber.value as? String
        // Down the title block (36 pt art row at 12 pt), then its very bottom edge, 60% across.
        for y in [24.0, 38.0, 44.0, 47.0] {
            card.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0)).withOffset(CGVector(dx: 0, dy: y)).tap()
            idle(0.5)
            XCTAssertTrue(scrubber.exists, "the card is still there after a tap on the title block (y \(y)): the chrome did not hide")
            XCTAssertEqual(scrubber.value as? String, before, "a tap on the title block (y \(y)) must not seek")
        }
    }
}
