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
        idle(1.5) // the page's text settles after the launch
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

    /// Listen's floating ‹ returns to where it was entered from, and is gone in full screen.
    func testListenBackReturnsToWhereItWasEnteredFrom() throws {
        let app = launchLibrary()
        openListen(app)
        let back = app.buttons["listenBack"]
        XCTAssertTrue(appears(back, timeout: 5), "entered from the Library: ‹ floats top left")
        let text = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        idle(1.5)
        text.tap()
        XCTAssertTrue(eventually { !back.exists }, "full screen removes it")
        text.tap()
        XCTAssertTrue(appears(back, timeout: 3), "and leaving full screen brings it back")

        tapWhenHittable(back)
        XCTAssertTrue(appears(app.libraryHome, timeout: 5), "back in the Library, where it was")
        XCTAssertTrue(app.buttons["chromeLibrary"].isSelected)
        XCTAssertFalse(back.exists)
        XCTAssertFalse(app.buttons["chromeReaderMore"].exists, "Listen is down")
    }

    /// ‹ goes to the place that launched the listening, not the last other screen: launched from the
    /// Library, then the Browser, then Listen by the tab: ‹ is the Library. It can be used again.
    func testListenBackGoesToTheLaunchingPlaceNotTheLastScreen() throws {
        let app = launchLibrary()
        tapWhenHittable(libraryCell(app, "Demo Listen Article"))
        tapWhenHittable(app.buttons["chromeBrowser"])
        XCTAssertTrue(eventually { app.buttons["chromeBrowser"].isSelected })
        tapWhenHittable(app.buttons["chromeListen"])
        let back = app.buttons["listenBack"]
        XCTAssertTrue(appears(back, timeout: 8), "launched from the Library: ‹ shows")
        tapWhenHittable(back)
        XCTAssertTrue(appears(app.libraryHome, timeout: 5), "the Library that launched it, not the Browser")
        XCTAssertTrue(app.buttons["chromeLibrary"].isSelected)

        tapWhenHittable(app.buttons["chromeListen"])
        XCTAssertTrue(appears(app.buttons["listenBack"], timeout: 8), "the record stays: ‹ works on a second visit")
    }

    /// The pill's three segments keep one place on the Library, the Browser and Listen (▶'s slot stays
    /// empty on Listen), so switching destinations moves nothing.
    func testThePillSegmentsNeverMoveBetweenDestinations() throws {
        let app = launchLibrary()
        let ids = ["chromeListen", "chromeLibrary", "chromeBrowser"]
        func frames() -> [CGRect] { ids.map { app.buttons[$0].frame } }
        let library = frames()
        XCTAssertTrue(library.allSatisfy { !$0.isEmpty }, "the segments are there: \(library)")
        // The pill is the SE's 235 pt on every phone, in a 351 pt row centred on the screen (12 pt in on the SE).
        let screenWidth = app.windows.firstMatch.frame.width
        XCTAssertEqual(library.last!.maxX - library.first!.minX, 235, accuracy: 1, "the pill: \(library)")
        XCTAssertEqual(library.first!.minX, (screenWidth - 351) / 2, accuracy: 1, "the row is centred at \(screenWidth)")
        tapWhenHittable(app.buttons["chromeBrowser"])
        XCTAssertTrue(eventually { app.buttons["chromeBrowser"].isSelected })
        let browser = frames()
        tapWhenHittable(app.buttons["chromeLibrary"])
        XCTAssertTrue(appears(app.libraryHome, timeout: 5))
        tapWhenHittable(libraryCell(app, "Demo Listen Article"))
        tapWhenHittable(app.buttons["chromeListen"])
        XCTAssertTrue(appears(app.buttons["chromeReaderMore"], timeout: 10), "Listen")
        let listen = frames()
        for (i, id) in ids.enumerated() {
            for (name, other) in [("Browser", browser), ("Listen", listen)] {
                XCTAssertEqual(other[i].minX, library[i].minX, accuracy: 0.5, "\(id) x on \(name)")
                XCTAssertEqual(other[i].width, library[i].width, accuracy: 0.5, "\(id) width on \(name)")
                XCTAssertEqual(other[i].minY, library[i].minY, accuracy: 0.5, "\(id) y on \(name)")
            }
        }
    }

    /// The title block is a button that opens the article's place and never seeks.
    func testListenTitleBlockOpensTheArticlesPlaceInTheLibrary() throws {
        let app = launchLibrary()
        openListen(app)
        let origin = app.buttons["listenOrigin"]
        XCTAssertTrue(appears(origin, timeout: 5))
        XCTAssertTrue(origin.label.hasPrefix("Open "), origin.label)
        XCTAssertTrue(origin.label.hasSuffix(" in Library"), origin.label)
        tapWhenHittable(origin)
        XCTAssertTrue(appears(app.libraryHome, timeout: 5), "the Library at the article's place")
        XCTAssertTrue(app.buttons["chromeLibrary"].isSelected)
        XCTAssertFalse(app.buttons["listenBack"].exists, "left Listen another way: no ‹ left over")
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

    /// Jump to Audio scrolls the spoken spot to the middle of the visible text (between the top of
    /// the screen and the player card), not to its top edge.
    func testJumpToAudioCentresTheSpotInTheVisibleText() throws {
        let app = launch(["-seedDemoArticle", "-seedDemoParagraphs", "40", "-seedDemoListenAt", "20",
                          "-seedDemoBook", "-seedDemoFolders", "-openLibrary"])
        XCTAssertTrue(appears(app.libraryHome, timeout: 10), "the Library")
        openListen(app)
        let playPause = app.buttons["listenPlayPause"]
        XCTAssertTrue(appears(playPause, timeout: 10), "Now Playing")
        // Held still, so the spoken paragraph doesn't move on.
        tapWhenHittable(playPause)
        idle(2)
        let card = find(app, "readingPlayerCard")
        XCTAssertTrue(appears(card, timeout: 5))
        let viewportMid = card.frame.minY / 2
        let paragraphs = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Paragraph '"))
        // The spoken paragraph is the one the text opened with in the middle.
        let spoken = paragraphs.allElementsBoundByIndex.first {
            $0.frame.minY <= viewportMid && viewportMid <= $0.frame.maxY
        }
        let spot = try XCTUnwrap(spoken, "a paragraph is in the middle of the visible text")
        let label = spot.label
        NSLog("JUMPPROBE open: \(label.prefix(14)) \(spot.frame) viewport mid \(viewportMid)")

        // Scroll away from the audio, up the text and down it: the text follows no more and the
        // pill shows. Jump to Audio brings the spot back to the middle.
        let high = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        let low = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
        let again = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", String(label.prefix(13)))).firstMatch
        let jump = app.buttons["nowPlayingJumpToAudio"]
        for (from, to) in [(high, low), (low, high)] {
            for _ in 0..<3 { from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .fast, thenHoldForDuration: 0.2) }
            XCTAssertTrue(appears(jump, timeout: 5), "scrolled away from the audio: the pill")
            XCTAssertFalse(again.exists && again.frame.minY > 0 && again.frame.maxY < card.frame.minY, "the spot is out of view")
            jump.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            idle(2)
            NSLog("JUMPPROBE after jump: \(again.frame) viewport mid \(viewportMid)")
            XCTAssertEqual(again.frame.midY, viewportMid, accuracy: 40,
                           "the spot is in the middle of the visible text, not at its top: \(again.frame)")
            XCTAssertTrue(eventually(2) { !jump.exists }, "the pill goes once the audio is shown")
        }
    }

    /// Jump to Audio floats at the top of the text: centred, below the status bar, level with the
    /// floating ‹ without meeting it, and below the ☝︎ hint when that is up (it never covers a
    /// control).
    func testJumpToAudioSitsAtTheTopClearOfTheBackAndTheHint() throws {
        let app = launch(["-seedDemoArticle", "-seedDemoParagraphs", "40", "-seedDemoListenAt", "20",
                          "-seedDemoBook", "-seedDemoFolders", "-openLibrary"])
        XCTAssertTrue(appears(app.libraryHome, timeout: 10), "the Library")
        openListen(app)
        let playPause = app.buttons["listenPlayPause"]
        XCTAssertTrue(appears(playPause, timeout: 10), "Now Playing")
        tapWhenHittable(playPause)
        let window = app.windows.firstMatch.frame
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
        for _ in 0..<3 { from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .fast, thenHoldForDuration: 0.2) }
        let jump = app.buttons["nowPlayingJumpToAudio"]
        XCTAssertTrue(appears(jump, timeout: 5), "scrolled away from the audio: the pill")
        let pill = jump.frame
        NSLog("JUMPPROBE pill \(pill) window \(window)")
        XCTAssertEqual(pill.midX, window.midX, accuracy: 1, "centred")
        XCTAssertLessThan(pill.minY, window.height * 0.2, "at the top of the screen, not the middle")
        XCTAssertGreaterThan(pill.minY, 47, "below the status bar")
        let back = app.buttons["listenBack"]
        XCTAssertTrue(appears(back, timeout: 3), "the floating ‹")
        XCTAssertFalse(pill.intersects(back.frame), "the pill and ‹ never meet: \(pill) \(back.frame)")
        XCTAssertEqual(pill.midY, back.frame.midY, accuracy: 6, "level with the ‹ circle")

        // The ☝︎ hint comes up in the header: the pill is below it.
        tapWhenHittable(app.buttons["chromeReaderMore"])
        tapWhenHittable(find(app, "listenJump"))
        let hint = find(app, "listenJumpHint")
        XCTAssertTrue(appears(hint, timeout: 5), "the ☝︎ hint")
        idle(1)
        NSLog("JUMPPROBE hint \(hint.frame) pill \(jump.frame)")
        XCTAssertTrue(jump.exists, "the pill stays")
        XCTAssertGreaterThanOrEqual(jump.frame.minY, hint.frame.maxY, "below the hint")
        XCTAssertFalse(jump.frame.intersects(hint.frame))
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

    /// A tap on the card's title block (art, title, source and time left), even low on it beside the scrubber,
    /// goes to the article's place and never seeks; it never reaches the page behind either (a tap there hides the chrome).
    func testTapOnTheCardTitleBlockOpensItsPlaceAndNeverSeeks() throws {
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
        // Low on the title block, 60% across.
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0)).withOffset(CGVector(dx: 0, dy: 38)).tap()
        XCTAssertTrue(appears(app.libraryHome, timeout: 5), "it opened the article's place")
        tapWhenHittable(app.buttons["chromeListen"])
        XCTAssertTrue(appears(scrubber, timeout: 5), "Listen again")
        XCTAssertEqual(scrubber.value as? String, before, "and nothing sought")
    }

    /// ‹ then ›: after going back, › is there, on screen, takes taps and goes forward again, and
    /// ‹ stays beside it, dimmed, once the first page is reached (the case where › used to vanish).
    func testForwardShowsAndWorksAfterGoingBack() throws {
        let app = launch(["-browseTestPages"])
        let link = app.links["Next page"]
        XCTAssertTrue(appears(link, timeout: 10))
        link.tap()
        XCTAssertTrue(appears(find(app, "addressReader"), timeout: 10), "page two")
        let back = find(app, "browseBack"), forward = find(app, "browseForward")
        XCTAssertTrue(back.isEnabled)
        XCTAssertTrue(forward.exists && !forward.isEnabled, "› is there but dimmed with nowhere to go")
        tapWhenHittable(back)
        XCTAssertTrue(appears(app.links["Next page"], timeout: 10), "page one again")
        XCTAssertTrue(eventually { forward.exists && forward.isHittable && forward.isEnabled }, "› takes taps on the first page")
        XCTAssertTrue(forward.frame.width >= 44 && forward.frame.height >= 44)
        XCTAssertFalse(back.isEnabled, "‹ is the dimmed one now")
        tapWhenHittable(forward)
        XCTAssertTrue(appears(find(app, "addressReader"), timeout: 10), "page two again")
        XCTAssertTrue(eventually { !forward.isEnabled && back.isEnabled })
    }

    /// ‹ from a page's reader view goes to the page before; › comes back to the page in its reader view.
    func testForwardReentersTheReaderViewBackLeft() throws {
        let app = launch(["-browseTestPages"])
        let link = app.links["Next page"]
        XCTAssertTrue(appears(link, timeout: 10))
        link.tap()
        tapWhenHittable(find(app, "addressReader"))
        XCTAssertTrue(appears(app.buttons["pageReaderListen"], timeout: 10), "reader view")
        tapWhenHittable(find(app, "browseBack"))
        XCTAssertTrue(appears(app.links["Next page"], timeout: 10), "page one")
        XCTAssertFalse(app.buttons["pageReaderListen"].exists)
        tapWhenHittable(find(app, "browseForward"))
        XCTAssertTrue(appears(app.buttons["pageReaderListen"], timeout: 15), "› re-enters the reader view")
    }

    /// ↻ is a whole 44 pt control inside the field's end, never squeezed or clipped by the field's width.
    func testReloadIsAWholeControlInsideTheField() throws {
        let app = launch(["-browseTestPages"])
        let link = app.links["Next page"]
        XCTAssertTrue(appears(link, timeout: 10))
        link.tap()
        XCTAssertTrue(appears(find(app, "addressReader"), timeout: 10))
        let reload = find(app, "addressReload")
        XCTAssertTrue(appears(reload, timeout: 5))
        XCTAssertGreaterThanOrEqual(reload.frame.width, 44)
        XCTAssertGreaterThanOrEqual(reload.frame.height, 44)
        XCTAssertLessThanOrEqual(reload.frame.maxX, app.frame.width - 12, "↻ ends inside the field")
    }
}
