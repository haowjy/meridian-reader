import XCTest

/// Now Playing: the bar opens it over every surface; ⌄ and the pull down shrink it back to the
/// same screen. Its header names where it plays from, its text follows the audio until you scroll,
/// and at the end it stays with ▶.
final class NowPlayingUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testOpensOverTheBrowserAndPullsBackDown() throws {
        let app = launchTestPages()
        openTestPage(app, "Next page")
        listenHere(app)

        find(app, "nowPlayingBarOpen").tap()
        let from = find(app, "nowPlayingHeader")
        XCTAssertTrue(from.waitForExistence(timeout: 5), "Now Playing")
        XCTAssertEqual(playingFrom(app), "Playing from pages", "the close pill names the site")
        XCTAssertFalse(find(app, "nowPlayingBar").exists, "no bar on Now Playing")

        pullDown(app, from: "nowPlayingHeader")
        XCTAssertTrue(eventually(5) { !from.exists }, "the pull down shrinks it")
        XCTAssertTrue(find(app, "nowPlayingBar").waitForExistence(timeout: 5), "back into the bar")
        XCTAssertTrue(app.textFields["addressField"].exists, "on the browser, as it was")
        XCTAssertTrue(app.staticTexts["Second page"].exists, "same page")

        find(app, "nowPlayingBarOpen").tap()
        XCTAssertTrue(from.waitForExistence(timeout: 5))
        app.buttons["nowPlayingClose"].tap() // ⌄
        XCTAssertTrue(eventually(5) { !from.exists }, "⌄ shrinks it")
        find(app, "nowPlayingBarPlayPause").tap()
    }

    func testOpensOverTheLibraryAndOverAReader() throws {
        let app = launchTestPages(["-seedDemoArticle"])
        openTestPage(app, "Next page")
        listenHere(app)

        // Over a Reader sheet of another page.
        backToPageOne(app)
        openTestPage(app, "Third page")
        find(app, "addressReader").tap()
        let back = app.buttons["readerClose"]
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        XCTAssertEqual(back.label, "Back to Browser")
        find(app, "nowPlayingBarOpen").tap()
        XCTAssertTrue(find(app, "nowPlayingHeader").waitForExistence(timeout: 5))
        // The Reader stays under Now Playing (and in the UI-test tree), with a close of its own.
        app.buttons["nowPlayingClose"].tap()
        XCTAssertTrue(eventually(5) { !self.find(app, "nowPlayingHeader").exists })
        XCTAssertEqual(app.buttons["readerClose"].label, "Back to Browser", "the Reader is still there")
        app.buttons["readerClose"].tap()
        XCTAssertTrue(eventually(5) { !app.buttons["readerClose"].exists })
        XCTAssertTrue(find(app, "nowPlayingBar").waitForExistence(timeout: 5), "back on the browser, with its bar")

        // Over the Library, which stays as it was.
        app.buttons["browseLibrary"].tap()
        XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 5))
        let bar = find(app, "nowPlayingBarOpen")
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "the bar shows on the Library")
        bar.tap()
        XCTAssertTrue(find(app, "nowPlayingHeader").waitForExistence(timeout: 5))
        pullDown(app, from: "nowPlayingHeader")
        XCTAssertTrue(eventually(5) { !self.find(app, "nowPlayingHeader").exists })
        XCTAssertTrue(app.libraryHome.exists, "back on the Library")
        XCTAssertTrue(app.cells.staticTexts["Demo Listen Article"].exists, "its list as it was")
        find(app, "nowPlayingBarPlayPause").tap()
    }

    func testScrollingAwayOffersJumpToAudio() throws {
        let app = launchLongDemo()
        openNowPlayingFromTheLibrary(app)
        XCTAssertEqual(playingFrom(app), "Playing from Library", "a saved page plays from the Library")
        assertJumpToAudioReturnsToTheSpokenSentence(app)

        // ⋯ → Go to Library (D24: the pill only closes).
        find(app, "nowPlayingMore").tap()
        let goTo = find(app, "moreGoTo")
        XCTAssertTrue(goTo.waitForExistence(timeout: 3), "⋯ → Go to")
        XCTAssertEqual(goTo.label, "Go to Library")
        tapMenuRow(app, "moreGoTo")
        XCTAssertTrue(eventually(5) { !self.find(app, "nowPlayingHeader").exists }, "Now Playing closes")
        XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 5), "on the Library")
    }

    /// A plain-text article (no reading HTML) reads on the same page: it follows the audio, offers
    /// Jump to Audio, and Jump to Audio brings the spoken sentence back.
    func testPlainTextArticleReadsTheSameWay() throws {
        let app = launchLongDemo(["-seedDemoPlainText"])
        openNowPlayingFromTheLibrary(app)
        XCTAssertTrue(paragraph(app, 0).waitForExistence(timeout: 5), "the paragraphs on the reading page")
        assertJumpToAudioReturnsToTheSpokenSentence(app)
    }

    /// Now Playing opened on what is playing opens at the spoken sentence, already in the middle,
    /// without Jump to Audio: here reopened from the bar, paused on paragraph 7.
    func testNowPlayingOpensAtTheSpokenSentence() throws {
        let app = launchLongDemo()
        openNowPlayingFromTheLibrary(app)
        let play = app.buttons["listenPlayPause"]
        XCTAssertTrue(eventually(8) { play.label == "Pause" }, "playing")
        for _ in 0..<6 { app.buttons["Next paragraph"].tap() }
        play.tap()
        XCTAssertTrue(eventually(5) { play.label == "Play" }, "paused")
        XCTAssertTrue(eventually(3) { (self.find(app, "readerScrubOffset").value as? String)?.hasPrefix("p=6 ") == true },
                      "paused on paragraph 7")
        app.buttons["nowPlayingClose"].tap() // ⌄
        XCTAssertTrue(eventually(5) { !self.find(app, "nowPlayingHeader").exists }, "back in the bar")

        find(app, "nowPlayingBarOpen").tap()
        XCTAssertTrue(find(app, "nowPlayingHeader").waitForExistence(timeout: 5), "Now Playing")
        let spoken = paragraph(app, 6)
        XCTAssertTrue(eventually(5) { self.holdsTheMiddle(app, spoken) },
                      "paragraph 7's sentence in the middle: \(spoken.frame), middle \(nowPlayingMiddle(app))")
        XCTAssertFalse(find(app, "nowPlayingJumpToAudio").exists, "following, so no Jump to Audio")
    }

    /// The Reader of a page part-way through opens at its saved spot: the sentence there in the
    /// middle of the text (underlined; the page underlines what it is given, see
    /// `SpokenSentenceScrollTests`), and Listen turns it into Now Playing right there (D2).
    func testTheReaderOpensAtTheSavedSpot() throws {
        let app = launchLongDemo(["-seedDemoProgress", "20"])
        let row = app.cells.staticTexts["Demo Listen Article"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let listen = app.buttons["listenPlayPause"]
        XCTAssertTrue(listen.waitForExistence(timeout: 10))
        XCTAssertTrue(listen.label.hasPrefix("Resume"), listen.label)
        let saved = paragraph(app, 20)
        let middle = { (app.buttons["readerClose"].frame.maxY + listen.frame.minY) / 2 }
        XCTAssertTrue(eventually(5) { saved.exists && self.holds(middle(), saved) },
                      "paragraph 21's sentence in the middle: \(saved.frame), middle \(middle())")
        let before = settledTop(of: saved)

        listen.tap()
        XCTAssertTrue(find(app, "nowPlayingHeader").waitForExistence(timeout: 5), "Now Playing")
        let play = app.buttons["listenPlayPause"]
        XCTAssertTrue(eventually(8) { play.label == "Pause" }, "playing")
        play.tap()
        XCTAssertTrue(eventually(5) { play.label == "Play" })
        // D2: the same line at the same place on screen.
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        XCTAssertEqual(settledTop(of: saved), before, accuracy: 1, "Now Playing opens where the Reader was")
        XCTAssertFalse(find(app, "nowPlayingJumpToAudio").exists, "following, so no Jump to Audio")
    }

    /// D24: the Reader and Now Playing share their chrome. Listen turns one into the other with
    /// 🔖, ⋯, ☝︎ and the close pill where they were (the pill's width follows its title), and in
    /// Now Playing 🔖 still files the page (its long-press opens the Move tree) and the speed sits
    /// at the end of the scrub capsule.
    func testTheReaderAndNowPlayingShareTheirChrome() throws {
        let app = launchLongDemo()
        let row = app.cells.staticTexts["Demo Listen Article"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let listen = app.buttons["listenPlayPause"]
        XCTAssertTrue(listen.waitForExistence(timeout: 10))
        // Each control's id in the Reader, and in Now Playing.
        let controls = [("bookmark", "readerBookmark", "nowPlayingBookmark"), ("more", "readerMore", "nowPlayingMore"),
                        ("jump", "listenJump", "listenJump"), ("close", "readerClose", "nowPlayingClose")]
        XCTAssertNotNil(settledFrames(controls.map { app.buttons[$0.1] }), "the Reader has risen")
        let reader = Dictionary(uniqueKeysWithValues: controls.map { ($0.0, app.buttons[$0.1].frame) })
        XCTAssertEqual(app.buttons["readerClose"].label, "Back to Library")

        listen.tap()
        XCTAssertTrue(find(app, "nowPlayingHeader").waitForExistence(timeout: 5), "Now Playing")
        XCTAssertNotNil(settledFrames(controls.map { app.buttons[$0.2] }), "Now Playing has settled")
        XCTAssertFalse(app.buttons["readerClose"].exists, "the Reader turned into Now Playing")
        let player = Dictionary(uniqueKeysWithValues: controls.map { ($0.0, app.buttons[$0.2].frame) })
        XCTAssertEqual(app.buttons["nowPlayingClose"].label, "Close Now Playing")
        for id in ["bookmark", "more", "jump"] {
            let (r, p) = (reader[id]!, player[id]!)
            XCTAssertFalse(r.isEmpty, id)
            XCTAssertEqual(p.minX, r.minX, accuracy: 0.5, "\(id) x: Reader \(r), Now Playing \(p)")
            XCTAssertEqual(p.minY, r.minY, accuracy: 0.5, "\(id) y: Reader \(r), Now Playing \(p)")
            XCTAssertEqual(p.width, r.width, accuracy: 0.5, "\(id) width: Reader \(r), Now Playing \(p)")
            XCTAssertEqual(p.height, r.height, accuracy: 0.5, "\(id) height: Reader \(r), Now Playing \(p)")
        }
        let (r, p) = (reader["close"]!, player["close"]!)
        XCTAssertEqual(p.minX, r.minX, accuracy: 0.5, "the close pill's leading edge: \(r), \(p)")
        XCTAssertEqual(p.minY, r.minY, accuracy: 0.5, "the close pill's top: \(r), \(p)")
        XCTAssertEqual(p.height, r.height, accuracy: 0.5, "the close pill's height: \(r), \(p)")

        // The speed, in the scrub capsule's trailing end.
        let speed = app.buttons["listenSpeed"]
        let scrubber = find(app, "readerScrubber")
        XCTAssertTrue(speed.exists && scrubber.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(speed.frame.minX, scrubber.frame.maxX, "the speed after the scrubber")
        XCTAssertEqual(speed.frame.midY, scrubber.frame.midY, accuracy: 1, "on the scrub row")

        // 🔖's long-press: Save to Folder…, the Move tree, as in the Reader.
        app.buttons["nowPlayingBookmark"].press(forDuration: 1.0)
        XCTAssertTrue(find(app, "moveTree").waitForExistence(timeout: 5), "🔖's long-press opens the Move tree")
        app.buttons["moveCancel"].tap()
        XCTAssertTrue(eventually(5) { !self.find(app, "moveTree").exists })
        app.buttons["listenPlayPause"].tap()
    }

    /// 🔖 is one fact for the page: saved in the Reader, Now Playing shows it saved; removed in Now
    /// Playing, the Reader shows it removed (once another page plays, so it opens as a Reader).
    func testTheReaderAndNowPlayingAgreeOnSaved() throws {
        let app = launchTestPages(["-seedDemoArticle"])
        openTestPage(app, "Next page")
        find(app, "addressReader").tap()
        let reader = app.buttons["readerBookmark"]
        XCTAssertTrue(reader.waitForExistence(timeout: 10))
        XCTAssertTrue(eventually(5) { reader.value as? String == "Not saved" })
        reader.tap()
        XCTAssertTrue(eventually(5) { reader.value as? String == "Saved" }, "saved in the Reader")

        app.buttons["listenPlayPause"].tap()
        XCTAssertTrue(find(app, "nowPlayingHeader").waitForExistence(timeout: 5), "Now Playing")
        let player = app.buttons["nowPlayingBookmark"]
        XCTAssertTrue(eventually(5) { player.value as? String == "Saved" }, "Now Playing shows it saved")
        player.tap()
        XCTAssertTrue(eventually(5) { player.value as? String == "Not saved" }, "removed in Now Playing")

        app.buttons["nowPlayingClose"].tap()
        XCTAssertTrue(eventually(5) { !self.find(app, "nowPlayingHeader").exists })
        // The header leaves the tree before the sheet has gone; the bar takes taps once it has.
        let bar = find(app, "nowPlayingBarOpen")
        XCTAssertTrue(eventually(5) { bar.isHittable }, "back in the bar")
        backToPageOne(app)
        openTestPage(app, "Third page")
        listenHere(app)
        backToPageOne(app)
        openTestPage(app, "Next page")
        find(app, "addressReader").tap()
        XCTAssertTrue(app.buttons["readerClose"].waitForExistence(timeout: 10), "a Reader, not Now Playing")
        XCTAssertTrue(eventually(5) { app.buttons["readerBookmark"].value as? String == "Not saved" },
                      "the Reader shows it removed")
        find(app, "nowPlayingBarPlayPause").tap()
    }

    /// The title card says what is playing (title, site or Library, time left) and scrolls with
    /// the text; the big round button plays and pauses.
    func testTheTitleCardShowsWhatIsPlayingAndScrollsWithTheText() throws {
        let app = launchLongDemo()
        openNowPlayingFromTheLibrary(app)
        let card = find(app, "nowPlayingTitleCard")
        XCTAssertTrue(card.waitForExistence(timeout: 5), "the title card")
        XCTAssertTrue(card.label.contains("Demo Listen Article"), card.label)
        XCTAssertTrue(card.label.contains("min left"), card.label)
        let play = app.buttons["listenPlayPause"]
        XCTAssertTrue(eventually(8) { play.label == "Pause" }, "playing")
        XCTAssertGreaterThanOrEqual(play.frame.width, 64, "the big round ⏸")
        play.tap()
        XCTAssertTrue(eventually(5) { play.label == "Play" }, "it pauses")

        let top = card.frame.minY
        dragText(app, by: -200)
        XCTAssertTrue(eventually(3) { !card.exists || card.frame.minY < top - 100 }, "it scrolls up with the text")
    }

    /// Listen in the Reader (D2): Now Playing opens with the text exactly where the Reader had it,
    /// though the title card replaces the title. Within 1 pt: the two pages lay out the same text at the same width, the offset is
    /// set exactly, and what's left is rounding of the frames the accessibility tree reports.
    func testListenKeepsTheReadersScrollPosition() throws {
        assertListenKeepsTheLine(launchLongDemo())
    }

    /// The same at the largest text size, where the title and the title card differ the most.
    func testListenKeepsTheReadersScrollPositionAtTheLargestTextSize() throws {
        // A paragraph is over 1,000 pt tall there: the second one is far enough down.
        assertListenKeepsTheLine(launchLongDemo(Self.largestText), paragraph: 1)
    }

    /// The same for a plain-text article (no reading HTML: its paragraphs, on the same page).
    func testListenKeepsTheReadersScrollPositionForPlainText() throws {
        assertListenKeepsTheLine(launchLongDemo(["-seedDemoPlainText"]))
    }

    /// Listen in a Reader still at its top: Now Playing opens at its top, the title card in full
    /// under the header, at the default text size and the largest.
    func testListenFromTheReadersTopOpensAtTheTopWithTheTitleCardInFull() throws {
        for extra in [[], Self.largestText] {
            let app = launchLongDemo(extra)
            let row = app.cells.staticTexts["Demo Listen Article"]
            XCTAssertTrue(row.waitForExistence(timeout: 10))
            row.tap()
            let listen = app.buttons["listenPlayPause"]
            XCTAssertTrue(listen.waitForExistence(timeout: 10))
            XCTAssertTrue(eventually(10) { listen.isEnabled }, "listen document ready")
            listen.tap()
            let header = find(app, "nowPlayingHeader")
            XCTAssertTrue(header.waitForExistence(timeout: 5))
            let card = find(app, "nowPlayingTitleCard")
            XCTAssertTrue(card.waitForExistence(timeout: 5), "the title card")
            let top = settledTop(of: card)
            let size = extra.isEmpty ? "default size" : "largest text"
            XCTAssertGreaterThanOrEqual(top, header.frame.maxY - 1, "\(size): the card's top under the header")
            XCTAssertLessThan(top, header.frame.maxY + 40, "\(size): at the top of the page")
            XCTAssertLessThanOrEqual(card.frame.maxY, app.windows.firstMatch.frame.maxY, "\(size): all of it on screen")
            app.terminate()
        }
    }

    /// The round ⏸ / ▶ is taller than the toolbar row: a tap on the part that reaches above or
    /// below the row, or at its sides, plays and pauses, and never lands on ⏮, ⏭ or ⋯.
    func testTheRoundButtonsEdgePlaysAndPauses() throws {
        let app = launchLongDemo()
        openNowPlayingFromTheLibrary(app)
        let play = app.buttons["listenPlayPause"]
        XCTAssertTrue(eventually(8) { play.label == "Pause" }, "playing")
        play.tap()
        XCTAssertTrue(eventually(5) { play.label == "Play" }, "paused")
        let paragraph = { self.find(app, "readerScrubOffset").value as? String }
        let spot = paragraph()
        XCTAssertNotNil(spot)
        let row = app.buttons["Next paragraph"].frame
        let disc = play.frame
        XCTAssertGreaterThan(disc.height, row.height + 10, "the disc reaches past the row")
        // Inside the circle (radius 32): 27 pt above and below the centre is outside the 44 pt row;
        // 28 pt to the sides is the disc's edge, nearest ⏮ and ⏭.
        let edges: [(String, CGVector)] = [("top", CGVector(dx: 0, dy: -27)), ("bottom", CGVector(dx: 0, dy: 27)),
                                           ("left", CGVector(dx: -28, dy: 0)), ("right", CGVector(dx: 28, dy: 0))]
        for (edge, offset) in edges {
            let before = play.label
            play.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(offset).tap()
            XCTAssertTrue(eventually(5) { play.label != before }, "a tap on the \(edge) edge toggles play / pause")
            XCTAssertFalse(find(app, "moreMenuPanel").exists, "the \(edge) edge doesn't open ⋯")
            if play.label == "Pause" {
                play.tap()
                XCTAssertTrue(eventually(5) { play.label == "Play" })
            }
            XCTAssertEqual(paragraph()?.prefix(4), spot?.prefix(4), "the \(edge) edge doesn't skip")
        }
    }

    /// The status bar is readable (the clock at 4.5:1 or better against the strip under it) over
    /// whatever is on top: dark on paper, light over Now Playing in a dark reading theme, over a
    /// sheet that comes over it and goes, after leaving the app and coming back, and while a
    /// finger holds Now Playing part way down (the dim lifts, a scrim under the status bar keeps
    /// the strip dark); dark again on paper once it closes.
    func testTheStatusBarFollowsTheSurfaceOnTop() throws {
        let app = launchLongDemo(["-reading.theme", "dark"])
        assertStatusBar(.dark, "on the Library's paper")
        openNowPlayingFromTheLibrary(app)
        assertStatusBar(.light, "over Now Playing")

        find(app, "nowPlayingMore").tap()
        tapMenuRow(app, "moreSettings")
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5), "Settings over Now Playing")
        XCTAssertNotNil(settledFrames([app.navigationBars["Settings"]]), "the sheet has risen")
        assertStatusBar(nil, "over Settings")
        app.buttons["settingsDone"].tap()
        XCTAssertTrue(eventually(5) { !app.navigationBars["Settings"].exists })
        assertStatusBar(.light, "on Now Playing again")

        XCUIDevice.shared.press(.home)
        idle(2)
        app.activate()
        XCTAssertTrue(find(app, "nowPlayingHeader").waitForExistence(timeout: 10))
        assertStatusBar(.light, "after coming back")

        // Held a third of the way down, two seconds into the hold, by the header between the close
        // pill and Aa.
        let header = find(app, "nowPlayingHeader").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .withOffset(CGVector(dx: 60, dy: 0))
        let held = try XCTUnwrap(screenshot(after: 2) {
            header.press(forDuration: 0.1, thenDragTo: header.withOffset(CGVector(dx: 0, dy: 300)),
                         withVelocity: .slow, thenHoldForDuration: 3.5)
        })
        let below = statusBarFrame().maxY
        let uncovered = try XCTUnwrap(StatusBarContrast.read(
            held.image, region: CGRect(x: 0, y: below + 40, width: statusBarFrame().width, height: 40)))
        XCTAssertGreaterThan(uncovered.stripLuminance, 0.1,
                             "the sheet was down: the dimmed Library shows under the status bar, \(uncovered)")
        let pulled = try XCTUnwrap(statusBarContrast(held))
        XCTAssertEqual(pulled.text, .light, "held part way down: \(pulled)")
        XCTAssertTrue(pulled.isReadable, "held part way down: \(pulled)")

        print("Status bar held part way down: \(pulled)")
        idle(1.5) // released: it settles back up or carries on down
        if find(app, "nowPlayingHeader").exists { app.buttons["Close Now Playing"].tap() }
        XCTAssertTrue(eventually(5) { !self.find(app, "nowPlayingHeader").exists })
        assertStatusBar(.dark, "on paper again")
    }

    /// Held on the real scrub row, the paragraph under the thumb is the one in full ink on the
    /// page (Now Playing passes the scrub preview to the reading page), and the rest is dimmed.
    /// Checked on screenshots taken while the finger holds the thumb, each read on its own: a shot
    /// counts only if it shows the scrub bubble ("¶ n of 40") with n mid-article, and then the
    /// reading area must show no title card, paragraph n's lines in full ink (the title card's ink
    /// before the scrub) and the other paragraphs dimmed. Shots without the bubble were taken
    /// before the finger came down or after it lifted, and are rejected, never passed. On the Dark
    /// reading theme: the levels read light text on a dark page.
    func testTheParagraphUnderTheScrubThumbIsInFullInk() throws {
        let app = launchLongDemo(["-reading.theme", "dark"])
        openNowPlayingFromTheLibrary(app)
        let play = app.buttons["listenPlayPause"]
        XCTAssertTrue(eventually(8) { play.label == "Pause" }, "playing")
        play.tap()
        XCTAssertTrue(eventually(5) { play.label == "Play" }, "paused on paragraph 1")
        let scrubber = find(app, "readerScrubber")
        XCTAssertTrue(scrubber.waitForExistence(timeout: 5))
        idle(1) // the scrub map

        let card = find(app, "nowPlayingTitleCard")
        let window = app.windows.firstMatch.frame
        let top = find(app, "nowPlayingHeader").frame.maxY + 8
        let area = CGRect(x: 0, y: top, width: window.width, height: window.height * 0.6 - top)
        XCTAssertTrue(area.contains(card.frame), "the title card at the top of the reading area")
        let rest = textLevels(XCUIScreen.main.screenshot(), in: area)
        let fullInk = try XCTUnwrap(rest.max())
        XCTAssertTrue(rest.contains { $0 > 0.1 && $0 < fullInk * 0.5 }, "dimmed paragraphs at rest: \(rest)")

        let from = scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5))
        let to = scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let shots = screenshots(at: [1.5, 2.25, 3, 3.75, 4.5]) {
            from.press(forDuration: 0.3, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 4)
        }
        let landed = (find(app, "readerScrubOffset").value as? String) ?? ""
        XCTAssertGreaterThan(Int(landed.dropFirst(2).prefix { $0.isNumber }) ?? 0, 10, "scrubbed into the middle: \(landed)")

        var held = 0
        for (i, shot) in shots.enumerated() {
            let lines = try ScreenText.lines(in: shot)
            guard let (header, n) = lines.lazy.compactMap({ line in Self.bubbleParagraph(line.text).map { (line, $0) } }).first
            else {
                print("Scrub shot \(i): no scrub bubble, taken outside the hold: rejected")
                continue
            }
            guard n > 10 else {
                print("Scrub shot \(i): bubble on ¶\(n), not yet mid-article: rejected")
                continue
            }
            held += 1
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = "scrub held on ¶\(n)"
            add(attachment)
            // The page from under the header down to the bubble (its card starts a line above
            // its header; it covers the page under it).
            let page = lines.filter { line in
                line.frame.midY > top && line.frame.maxY < header.frame.minY - header.frame.height
            }
            print("Scrub shot \(i): bubble ¶\(n), full ink \(fullInk); page \(page)")
            XCTAssertFalse(page.contains { $0.text.contains("Demo Listen") || $0.text.contains("example.com") },
                           "shot \(i): the title card is out of the measured area: \(page)")
            let full = page.filter { $0.ink > fullInk * 0.85 }
            let dimmed = page.filter { $0.ink > 0.1 && $0.ink < fullInk * 0.5 }
            XCTAssertTrue(full.contains { Self.paragraphNumber($0.text) == n },
                          "shot \(i): ¶\(n), under the thumb, in full ink: \(page)")
            XCTAssertFalse(full.contains { Self.paragraphNumber($0.text).map { $0 != n } ?? false },
                           "shot \(i): only ¶\(n) in full ink: \(full)")
            XCTAssertTrue(dimmed.contains { Self.paragraphNumber($0.text).map { $0 != n } ?? false },
                          "shot \(i): the other paragraphs dimmed: \(page)")
        }
        XCTAssertGreaterThan(held, 0, "no screenshot showed the held scrub mid-article")
    }

    /// The paragraph a scrub bubble names ("¶ 21 of 40", "sentence 1 of 2" → 21), from its text.
    private static func bubbleParagraph(_ text: String) -> Int? {
        guard let match = text.firstMatch(of: #/(\d+)\s*of\s*40\b/#) else { return nil }
        return Int(match.1)
    }

    /// The demo paragraph a page line belongs to, where the line says it ("Extra paragraph 21 …",
    /// "… harbor 21, …").
    private static func paragraphNumber(_ text: String) -> Int? {
        guard let match = text.firstMatch(of: #/(?:paragraph|harbor)\s+(\d+)/#) else { return nil }
        return Int(match.1)
    }

    func testAtTheEndNowPlayingStaysWithPlay() throws {
        let app = launch(UITestSetup(["-seedDemoArticle", "-openLibrary"], rate: 2))
        let row = app.cells.staticTexts["Demo Listen Article"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let play = app.buttons["listenPlayPause"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        play.tap()
        XCTAssertTrue(find(app, "nowPlayingHeader").waitForExistence(timeout: 5))
        // The last paragraph, then let it finish.
        app.buttons["Next paragraph"].tap()
        app.buttons["Next paragraph"].tap()
        let card = find(app, "nowPlayingTitleCard")
        XCTAssertTrue(eventually(45) { card.label.contains("✓ Finished") }, "✓ Finished, on the title card: \(card.label)")
        let elsewhere = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Finished"))
            .allElementsBoundByIndex.filter { !card.frame.contains($0.frame) }
        XCTAssertTrue(elsewhere.isEmpty, "shown once, not again under the text: \(elsewhere.map(\.label))")
        XCTAssertTrue(find(app, "nowPlayingHeader").exists, "Now Playing stays on the page")
        XCTAssertEqual(play.label, "Play", "with ▶")

        app.buttons["nowPlayingClose"].tap()
        let bar = find(app, "nowPlayingBarOpen")
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "the bar stays after the end")
        XCTAssertTrue(bar.label.contains("Finished"), bar.label)
        find(app, "nowPlayingBarPlayPause").tap()
        XCTAssertTrue(eventually(5) { self.find(app, "nowPlayingBarPlayPause").label == "Pause" }, "▶ plays it again")
        find(app, "nowPlayingBarPlayPause").tap()
    }

    /// The bar writes the time left as the page's row does (at 1×, both count at 1×): past the
    /// hour, "1 h 23 min left", for the same spot before and after Stop Listening.
    func testTheBarWritesTimeLeftAsTheRowDoes() throws {
        let app = launch(["-seedDemoArticle", "-seedDemoParagraphs", "500", "-openLibrary"])
        openNowPlayingFromTheLibrary(app)
        app.buttons["Next paragraph"].tap()
        app.buttons["Next paragraph"].tap()
        let play = app.buttons["listenPlayPause"]
        XCTAssertTrue(eventually(8) { play.label == "Pause" }, "playing")
        play.tap()
        XCTAssertTrue(eventually(5) { play.label == "Play" }, "paused")
        app.buttons["nowPlayingClose"].tap()

        let bar = find(app, "nowPlayingBarOpen")
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "the bar, on the Library")
        let barLeft = try XCTUnwrap(Self.timeLeft(in: bar.label), bar.label)
        XCTAssertNotNil(barLeft.firstMatch(of: #/^\d+ h( \d+ min)? left$/#), "hours and minutes: \(barLeft)")

        find(app, "nowPlayingBar").press(forDuration: 1.0)
        let stop = app.buttons["Stop Listening"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5), "the bar's long-press")
        stop.tap()
        let row = app.cells.staticTexts["Demo Listen Article"]
        XCTAssertTrue(eventually(5) { (row.value as? String)?.contains("left") == true },
                      "the row shows its time left once nothing plays: \(String(describing: row.value))")
        XCTAssertEqual((row.value as? String).flatMap(Self.timeLeft(in:)), barLeft, "the row says what the bar said")
    }

    /// "1 h 23 min left", "6 min left" or "2 h left" out of an accessibility label.
    private static func timeLeft(in label: String) -> String? {
        label.firstMatch(of: #/(\d+ h \d+ min|\d+ h|\d+ min) left/#).map { String($0.output.0) }
    }

    // MARK: - Helpers

    private static let largestText = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]

    /// Scrolls the first line of paragraph `index` to the middle of the Reader, then Listen: in
    /// Now Playing that line is where it was on screen, to the point.
    private func assertListenKeepsTheLine(_ app: XCUIApplication, paragraph index: Int = 8,
                                          file: StaticString = #filePath, line: UInt = #line) {
        let row = app.cells.staticTexts["Demo Listen Article"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), file: file, line: line)
        row.tap()
        let listen = app.buttons["listenPlayPause"]
        XCTAssertTrue(listen.waitForExistence(timeout: 10), file: file, line: line)
        let target = paragraph(app, index)
        XCTAssertTrue(target.waitForExistence(timeout: 5), file: file, line: line)
        let middle = app.windows.firstMatch.frame.height * 0.4
        for _ in 0..<20 where !topIsInMiddle(app, target) {
            dragText(app, by: max(-300, min(300, middle - target.frame.minY)))
        }
        let name = "paragraph \(index + 1)"
        XCTAssertTrue(topIsInMiddle(app, target), "\(name) scrolled into the middle of the Reader", file: file, line: line)
        let before = settledTop(of: target)

        listen.tap() // plays paragraph 1; the text stays where it is
        XCTAssertTrue(find(app, "nowPlayingHeader").waitForExistence(timeout: 5), "Now Playing", file: file, line: line)
        let play = app.buttons["listenPlayPause"]
        XCTAssertTrue(eventually(8) { play.label == "Pause" }, file: file, line: line)
        play.tap() // paused on paragraph 1, so following has nothing new to move to
        XCTAssertTrue(eventually(5) { play.label == "Play" }, file: file, line: line)
        let after = paragraph(app, index)
        XCTAssertTrue(eventually(5) { after.exists && self.topIsInMiddle(app, after) },
                      "\(name) is still in view, not the top of the page: before \(before), after \(after.frame), "
                        + "first \(paragraph(app, 0).frame), web views \(app.webViews.count)", file: file, line: line)
        XCTAssertEqual(settledTop(of: after), before, accuracy: 1, "at the Reader's scroll position", file: file, line: line)
        XCTAssertFalse(isInMiddle(app, paragraph(app, 0)), "not scrolled to the spoken paragraph", file: file, line: line)
    }

    /// The element's first line is in the reading area: below the header, above the controls.
    private func topIsInMiddle(_ app: XCUIApplication, _ element: XCUIElement) -> Bool {
        guard element.exists else { return false }
        let window = app.windows.firstMatch.frame
        let y = element.frame.minY
        return y > window.minY + window.height * 0.25 && y < window.minY + window.height * 0.6
    }

    /// The element's top once it has stopped moving (a drag's deceleration, a sheet settling).
    private func settledTop(of element: XCUIElement) -> CGFloat {
        var last = element.frame.minY
        for _ in 0..<20 {
            idle(0.25)
            let now = element.frame.minY
            if abs(now - last) < 0.01 { return now }
            last = now
        }
        return last
    }

    /// Waits up to 3 s for the status bar to read `text` (nil: either way) at 4.5:1 or better.
    private func assertStatusBar(_ text: StatusBarContrast.Text?, _ what: String,
                                 file: StaticString = #filePath, line: UInt = #line) {
        var last: StatusBarContrast?
        let readable = eventually(3) {
            last = self.statusBarContrast()
            guard let last else { return false }
            return last.isReadable && (text == nil || last.text == text)
        }
        let reading = last.map(String.init(describing:)) ?? "no status bar"
        print("Status bar \(what): \(reading)")
        XCTAssertTrue(readable, "\(what): \(reading)", file: file, line: line)
    }

    /// The brightest pixel of each text line in `area` of `shot` (relative luminance; rows of
    /// background between lines are skipped): one value per run of rows brighter than the page.
    private func textLevels(_ shot: XCUIScreenshot, in area: CGRect) -> [Double] {
        let image = shot.image
        guard let cg = image.cgImage else { return [] }
        let scale = image.scale
        let rect = CGRect(x: area.minX * scale, y: area.minY * scale, width: area.width * scale,
                          height: area.height * scale).integral
        guard let crop = cg.cropping(to: rect) else { return [] }
        let (w, h) = (crop.width, crop.height)
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        bytes.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?
                .draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        var lines: [Double] = []
        var peak = 0.0
        for y in 0..<h {
            var row = 0.0
            for x in 0..<w {
                let i = (y * w + x) * 4
                row = max(row, StatusBarContrast.luminance(bytes[i], bytes[i + 1], bytes[i + 2]))
            }
            if row > 0.06 {
                peak = max(peak, row)
            } else if peak > 0 {
                lines.append(peak)
                peak = 0
            }
        }
        if peak > 0 { lines.append(peak) }
        return lines
    }

    private func openNowPlayingFromTheLibrary(_ app: XCUIApplication) {
        let row = app.cells.staticTexts["Demo Listen Article"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let listen = app.buttons["listenPlayPause"]
        XCTAssertTrue(listen.waitForExistence(timeout: 10))
        listen.tap()
        XCTAssertTrue(find(app, "nowPlayingHeader").waitForExistence(timeout: 5), "Listen turns the Reader into Now Playing")
    }

    /// Skips to paragraph 7 and pauses there (on its first sentence), scrolls it away, then Jump to
    /// Audio: the sentence is back in the middle of the text. The accessibility tree has no
    /// sentence frames: the paragraph holding the middle of the visible text stands for it here,
    /// and `SpokenSentenceScrollTests` measures the sentence itself.
    private func assertJumpToAudioReturnsToTheSpokenSentence(_ app: XCUIApplication) {
        let back = find(app, "nowPlayingJumpToAudio")
        XCTAssertFalse(back.exists, "following the audio")
        let play = app.buttons["listenPlayPause"]
        XCTAssertTrue(eventually(8) { play.label == "Pause" }, "playing")
        for _ in 0..<6 { app.buttons["Next paragraph"].tap() }
        play.tap()
        XCTAssertTrue(eventually(5) { play.label == "Play" }, "paused")
        XCTAssertTrue(eventually(3) { (self.find(app, "readerScrubOffset").value as? String)?.hasPrefix("p=6 ") == true },
                      "paused on paragraph 7: \(find(app, "readerScrubOffset").value ?? "")")
        let spoken = paragraph(app, 6)
        XCTAssertTrue(eventually(5) { spoken.exists && self.isInMiddle(app, spoken) }, "following: paragraph 7 in view")

        for _ in 0..<3 { dragText(app, by: -260) }
        XCTAssertTrue(back.waitForExistence(timeout: 3), "scrolling away offers Jump to Audio")
        XCTAssertFalse(isOnScreen(app, spoken), "paragraph 7 scrolled out of view")

        back.tap()
        XCTAssertTrue(eventually(3) { !back.exists }, "following again")
        XCTAssertTrue(eventually(3) { self.holdsTheMiddle(app, spoken) },
                      "Jump to Audio brings paragraph 7's sentence to the middle: \(spoken.frame), middle \(nowPlayingMiddle(app))")
    }

    /// Paragraph `index` of the demo article on the reading page.
    private func paragraph(_ app: XCUIApplication, _ index: Int) -> XCUIElement {
        let opening = ["First paragraph", "Second paragraph", "Third paragraph"]
        let prefix = index < opening.count ? opening[index] : "Extra paragraph \(index + 1) "
        return app.webViews.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    private func isOnScreen(_ app: XCUIApplication, _ element: XCUIElement) -> Bool {
        element.exists && app.windows.firstMatch.frame.intersects(element.frame)
    }

    /// The middle of Now Playing's visible text: between the header and the scrubber.
    private func nowPlayingMiddle(_ app: XCUIApplication) -> CGFloat {
        (find(app, "nowPlayingHeader").frame.maxY + find(app, "readerScrubber").frame.minY) / 2
    }

    private func holdsTheMiddle(_ app: XCUIApplication, _ element: XCUIElement) -> Bool {
        holds(nowPlayingMiddle(app), element)
    }

    /// `element` reaches across `y`, give or take the header's padding (the frames name the
    /// controls, not the edges of the text).
    private func holds(_ y: CGFloat, _ element: XCUIElement) -> Bool {
        element.exists && element.frame.minY - 24 < y && element.frame.maxY + 24 > y
    }

    /// In the reading area: below the header, above the controls.
    private func isInMiddle(_ app: XCUIApplication, _ element: XCUIElement) -> Bool {
        guard element.exists else { return false }
        let window = app.windows.firstMatch.frame
        let y = element.frame.midY
        return y > window.minY + window.height * 0.15 && y < window.minY + window.height * 0.7
    }

    private func dragText(_ app: XCUIApplication, by dy: CGFloat) {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: dy)),
                   withVelocity: .slow, thenHoldForDuration: 0.1)
    }
}
