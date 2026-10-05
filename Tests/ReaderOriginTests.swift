import XCTest
@testable import Reader

/// The Reader sheet returns to the surface underneath (the browser as it was, or the library),
/// and its back pill names it. The Reader never shows what you hear: opening the page that is
/// playing opens Now Playing, which presents over everything without touching the surface.
@MainActor
final class ReaderOriginTests: XCTestCase {
    private let pageURL = URL(string: "https://example.com/post")!

    private func article(id: UUID = UUID()) -> ReaderArticle {
        ReaderArticle(id: id, url: pageURL,
                      extracted: ExtractedArticle(title: "Post", siteName: nil, cleanedHTML: "<p>Hello there.</p>",
                                                  plainText: "Hello there.", excerpt: ""))
    }

    func testOpenedOverTheBrowserGoesBackToIt() {
        let shell = ShellState()
        shell.web.load(pageURL)
        shell.openReader(article())
        XCTAssertEqual(shell.reader?.origin, .browser)
        XCTAssertEqual(shell.reader?.origin.backTitle, "Browser")
        shell.closeReader()
        XCTAssertNil(shell.reader)
        XCTAssertTrue(shell.isBrowsing)
        XCTAssertEqual(shell.web.currentURL, pageURL, "the page is still loaded")
    }

    func testOpenedOverTheLibraryGoesBackToIt() {
        let shell = ShellState()
        shell.openLibrary()
        shell.openReader(article())
        XCTAssertEqual(shell.reader?.origin, .library)
        XCTAssertEqual(shell.reader?.origin.backTitle, "Library")
        shell.closeReader()
        XCTAssertTrue(shell.isInLibrary, "still the library")
    }

    func testThePageYouHearOpensAsNowPlaying() {
        let playing = UUID()
        let shell = ShellState(isHearing: { $0 == .page(playing) })
        shell.openReader(article(id: playing))
        XCTAssertNil(shell.reader, "no Reader of the playing page")
        XCTAssertTrue(shell.isNowPlayingPresented)
    }

    func testNowPlayingKeepsTheSurfaceAndAnotherPagesReader() {
        let shell = ShellState()
        shell.openLibrary()
        shell.openReader(article())
        shell.showNowPlaying()
        XCTAssertTrue(shell.isNowPlayingPresented)
        XCTAssertTrue(shell.isInLibrary, "the library stays underneath")
        XCTAssertNotNil(shell.reader, "a Reader of another page stays under Now Playing")
        shell.hideNowPlaying()
        XCTAssertFalse(shell.isNowPlayingPresented)
        XCTAssertEqual(shell.reader?.origin, .library, "back to the same screen")
    }

    func testListenTurnsTheReaderIntoNowPlayingWhereItWas() {
        let shell = ShellState()
        shell.openReader(article())
        shell.turnReaderIntoNowPlaying(scrollOffset: 240)
        XCTAssertNil(shell.reader)
        XCTAssertTrue(shell.isNowPlayingPresented)
        XCTAssertEqual(shell.nowPlayingOpensAt, 240)
        shell.hideNowPlaying()
        XCTAssertNil(shell.nowPlayingOpensAt)
        XCTAssertTrue(shell.isBrowsing)
    }

    func testGoingToAPageClosesTheSheets() {
        let shell = ShellState()
        shell.openReader(article())
        shell.showNowPlaying()
        shell.navigate(to: pageURL)
        XCTAssertNil(shell.reader)
        XCTAssertFalse(shell.isNowPlayingPresented)
    }

    // MARK: - A close that lands late

    /// A Reader's close arrives after its animation. If the shell removed that Reader meanwhile
    /// and opened another (or replaced it outright), the late close leaves the new one.
    func testALateReaderCloseLeavesANewerReader() throws {
        let shell = ShellState()
        let a = article(), b = article(), c = article()
        shell.openReader(a)
        let first = try XCTUnwrap(shell.reader).presentation
        shell.openLibrary()          // the shell removes A while its close animates
        shell.openReader(b)
        shell.readerDidClose(first)  // A's close lands
        XCTAssertEqual(shell.reader?.article.id, b.id, "B stays")

        let second = try XCTUnwrap(shell.reader).presentation
        shell.openReader(c)          // replaced outright
        XCTAssertNotEqual(shell.reader?.presentation, second)
        shell.readerDidClose(second)
        XCTAssertEqual(shell.reader?.article.id, c.id, "C stays")

        shell.readerDidClose(try XCTUnwrap(shell.reader).presentation)
        XCTAssertNil(shell.reader, "its own close closes it")
    }

    func testAReaderUpdatedInPlaceIsTheSameShowing() throws {
        let shell = ShellState()
        let a = article()
        shell.openReader(a)
        let showing = try XCTUnwrap(shell.reader).presentation
        shell.updateReader(id: a.id) { $0.faviconData = Data([1]) }
        shell.readerDidClose(showing)
        XCTAssertNil(shell.reader)
    }

    func testALateNowPlayingCloseLeavesANewerShowing() throws {
        let shell = ShellState()
        shell.showNowPlaying()
        let first = try XCTUnwrap(shell.nowPlayingPresentation)
        shell.showNowPlaying()
        XCTAssertEqual(shell.nowPlayingPresentation, first, "already up: the same showing")

        shell.openLibrary()          // the shell takes it down while its close animates
        shell.showNowPlaying()
        shell.nowPlayingDidClose(first)
        XCTAssertTrue(shell.isNowPlayingPresented, "the newer Now Playing stays")

        shell.nowPlayingDidClose(try XCTUnwrap(shell.nowPlayingPresentation))
        XCTAssertFalse(shell.isNowPlayingPresented, "its own close closes it")
    }
}
