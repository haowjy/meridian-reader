import XCTest

/// The demo book's screen, a folder screen like any other (decision D19): front matter dimmed and
/// skipped, a chapter tap opens its Reader, Continue plays the current chapter (chapter 1 for a
/// fresh book; the place, at its paragraph, for a book part-way) and turns into the playing
/// state; Edit moves chapters out. Offline, Apple voice.
final class BookFolderUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testBookScreen() throws {
        let app = launchLibrary()
        openFolder(app, "The Demo Book")
        XCTAssertTrue(find(app, "folderScreen").exists, "a folder's screen")
        XCTAssertTrue(app.buttons["folderEdit"].exists, "with Edit")

        let titlePage = libraryRow(app, "Title Page")
        XCTAssertTrue(titlePage.waitForExistence(timeout: 5))
        XCTAssertTrue((titlePage.value as? String)?.contains("Skipped") == true, "front matter: skipped")
        XCTAssertFalse(libraryCell(app, "Title Page").buttons["Play"].exists, "and no ▶")
        // Dimmed: its title stands out from the row less than a chapter's does.
        let chapter = libraryRow(app, "Chapter 1: The Harbor")
        XCTAssertTrue(chapter.waitForExistence(timeout: 5))
        let shot = XCUIScreen.main.screenshot()
        let dimmed = try XCTUnwrap(ScreenColor.textContrast(in: shot, region: titlePage.frame))
        let normal = try XCTUnwrap(ScreenColor.textContrast(in: shot, region: chapter.frame))
        XCTAssertLessThan(dimmed, normal * 0.75, "the title page is dimmed: \(dimmed):1 against a chapter's \(normal):1")

        libraryRow(app, "Chapter 2: The Lighthouse").tap()
        let close = app.buttons["readerClose"]
        XCTAssertTrue(close.waitForExistence(timeout: 10), "the chapter's Reader")
        XCTAssertEqual(close.label, "Back to Library")
        close.tap()
        XCTAssertTrue(eventually(5) { !close.exists })

        let play = app.buttons["folderContinue"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        XCTAssertEqual(play.label, "Play")
        play.tap()
        let bar = app.buttons["nowPlayingBarPlayPause"]
        XCTAssertTrue(bar.waitForExistence(timeout: 10))
        XCTAssertTrue(eventually(10) { bar.label == "Pause" }, "playing")
        XCTAssertTrue(find(app, "nowPlayingBarOpen").label.contains("Chapter 1: The Harbor"), "chapter 1, not the title page")
        XCTAssertTrue(eventually(5) { play.label == "Playing, 1 of 3" }, "got \(play.label)")
        XCTAssertEqual(play.value as? String, "Pause", "the book's button is the playing state")
        play.tap()
        XCTAssertTrue(eventually(5) { bar.label == "Resume" || bar.label == "Play" }, "paused from the book")
    }

    /// Part-way through the book (its place on chapter 2, at the third paragraph; chapter 1
    /// finished), Continue plays chapter 2 from that paragraph, not the book from its start.
    func testContinueResumesTheBookAtItsPlace() throws {
        let app = launchLibrary(["-seedDemoBookPlace", "2"])
        openFolder(app, "The Demo Book")
        let play = app.buttons["folderContinue"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        XCTAssertTrue(play.label.hasPrefix("Continue") && play.label.contains("2 of 3"), "got \(play.label)")
        play.tap()
        let bar = app.buttons["nowPlayingBarPlayPause"]
        XCTAssertTrue(bar.waitForExistence(timeout: 10))
        XCTAssertTrue(eventually(10) { bar.label == "Pause" }, "playing")
        bar.tap()
        XCTAssertTrue(eventually(5) { bar.label == "Resume" || bar.label == "Play" }, "paused")
        XCTAssertTrue(eventually(5) { play.label.contains("2 of 3") }, "the book's button: \(play.label)")

        find(app, "nowPlayingBarOpen").tap()
        XCTAssertTrue(app.staticTexts["Chapter 2: The Lighthouse"].waitForExistence(timeout: 5), "Now Playing: chapter 2")
        let scrubber = find(app, "readerScrubber")
        XCTAssertTrue(scrubber.waitForExistence(timeout: 5))
        XCTAssertEqual((scrubber.value as? String)?.hasPrefix("Paragraph 3 of"), true,
                       "from its place, got \(scrubber.value ?? "nil")")
    }

    /// A book's and a folder's header blocks share the cards' edges: the bar spans the content
    /// width, its percent and time left sit on one line under it, and the play buttons' row runs
    /// edge to edge.
    func testHeaderBlocksShareTheCardsEdges() throws {
        let app = launchLibrary(["-seedDemoBookPlace", "2"])
        openFolder(app, "The Demo Book")
        assertHeaderEdges(app, play: "folderContinue", fromStart: "folderPlayFromStart", row: "Chapter 1: The Harbor")
        app.navigationBars["The Demo Book"].buttons.firstMatch.tap()
        XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 5))
        openFolder(app, "Demo Finance")
        assertHeaderEdges(app, play: "folderContinue", fromStart: "folderPlayFromStart", row: "Index Funds")
    }

    /// Edit on a book moves a chapter out, as on any folder; the book plays on without it.
    func testEditMovesAChapterOutOfTheBook() throws {
        let app = launchLibrary()
        openFolder(app, "The Demo Book")
        app.buttons["folderEdit"].tap()
        libraryRow(app, "Chapter 3: The Tide").tap()
        app.buttons["editMove"].tap()
        pickInMoveTree(app, "Demo Finance")
        app.buttons["folderEdit"].tap()
        XCTAssertTrue(eventually(5) { !self.libraryRow(app, "Chapter 3: The Tide").exists }, "moved out of the book")
        XCTAssertTrue(libraryRow(app, "Chapter 2: The Lighthouse").exists, "the rest stay")
        XCTAssertTrue(eventually(5) { app.buttons["folderContinue"].label == "Play" })
        app.navigationBars["The Demo Book"].buttons.firstMatch.tap()
        XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 5))
        openFolder(app, "Demo Finance")
        XCTAssertTrue(libraryRow(app, "Chapter 3: The Tide").waitForExistence(timeout: 5), "in Demo Finance")
    }

    private func assertHeaderEdges(_ app: XCUIApplication, play: String, fromStart: String, row: String,
                                   file: StaticString = #filePath, line: UInt = #line) {
        let progress = find(app, "folderHeaderProgress")
        XCTAssertTrue(progress.waitForExistence(timeout: 5), "the progress block", file: file, line: line)
        XCTAssertFalse(progress.label.contains("·"), "no dot: \(progress.label)", file: file, line: line)
        let card = libraryCell(app, row)
        XCTAssertTrue(card.waitForExistence(timeout: 5), file: file, line: line)
        let bar = progress.frame, continueButton = app.buttons[play].frame, startButton = app.buttons[fromStart].frame
        let cardFrame = card.frame
        for (name, edge) in [("bar", bar.minX), ("Continue", continueButton.minX)] {
            XCTAssertEqual(edge, cardFrame.minX, accuracy: 1, "\(name) leading edge on the card's", file: file, line: line)
        }
        for (name, edge) in [("bar", bar.maxX), ("Play from Start", startButton.maxX)] {
            XCTAssertEqual(edge, cardFrame.maxX, accuracy: 1, "\(name) trailing edge on the card's", file: file, line: line)
        }
        XCTAssertEqual(continueButton.midY, startButton.midY, accuracy: 1, "the buttons share a row", file: file, line: line)
        // The bar (3 pt), a gap and one caption line; two lines would be over 40 pt.
        XCTAssertLessThan(bar.height, 36, "percent and time left on one line, got \(bar.height) pt", file: file, line: line)
    }
}
