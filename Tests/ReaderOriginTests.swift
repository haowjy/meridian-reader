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
}
