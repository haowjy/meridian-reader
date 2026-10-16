import SwiftData
import XCTest
@testable import MeridianReader

/// A folder you made (and Favorites) plays like a book (decision D15): its pages in its order,
/// page to page, skipping links; the page that last played is its place, which Continue resumes;
/// what plays from it says so.
@MainActor
final class LibraryFolderPlaybackTests: XCTestCase {
    private var env: LibraryTestEnvironment!
    private var library: LibraryStore { env.library }

    override func setUp() async throws { env = try LibraryTestEnvironment() }
    override func tearDown() async throws { env.cleanUp() }

    /// A saved page in `folder`, added a minute after the last.
    private func savedPage(_ title: String, in folder: Folder?) throws -> Page {
        env.now = env.now.addingTimeInterval(60)
        return try library.save(env.article("https://example.com/\(title)", title: title), placement: .folder(folder))
    }

    private func keys(_ pages: [Page]) -> [UUID] { pages.map(\.listenKey) }

    func testAFolderCarriesOnPageToPageInItsOrderSkippingLinks() throws {
        let folder = try library.makeFolder(name: "Finance", in: nil)
        let a = try savedPage("a", in: folder)
        env.now = env.now.addingTimeInterval(60)
        let link = try library.addLink(url: URL(string: "https://example.com/link")!, title: "link", artwork: nil, in: folder)
        let b = try savedPage("b", in: folder)
        let c = try savedPage("c", in: folder)

        XCTAssertEqual(library.folder(containing: a.listenKey), PlaybackFolder(id: folder.id, name: "Finance", isBookOrSeries: false))
        let chapters = library.chapters(of: folder.id)
        XCTAssertEqual(chapters.map(\.key), keys([a, link, b, c]), "Manual: the order it was filed in")
        XCTAssertEqual(chapters.map(\.skipsInPlayback), [false, true, false, false], "a link has nothing to play")
        XCTAssertEqual(ChapterAdvance.after(a.listenKey, in: chapters), .ready(b.listenKey), "past the link")
        XCTAssertEqual(ChapterAdvance.after(b.listenKey, in: chapters), .ready(c.listenKey))
        XCTAssertEqual(ChapterAdvance.after(c.listenKey, in: chapters), .none, "the end of the folder")

        try library.setSort(.newest, for: folder)
        XCTAssertEqual(library.chapters(of: folder.id).map(\.key), keys([c, b, link, a]), "the folder's sort is its order")
        XCTAssertEqual(ChapterAdvance.after(c.listenKey, in: library.chapters(of: folder.id)), .ready(b.listenKey))
    }

    func testThePageThatPlaysIsTheFoldersPlaceAndContinueResumesIt() throws {
        let folder = try library.makeFolder(name: "Finance", in: nil)
        let a = try savedPage("a", in: folder)
        let b = try savedPage("b", in: folder)
        _ = try savedPage("c", in: folder)

        library.recordPlaybackStarted(b)
        library.recordPosition(b, paragraph: 1, utf16Offset: 0)
        XCTAssertEqual(folder.currentPageKey, b.listenKey, "the recorder stores the folder's place")
        XCTAssertNotNil(folder.lastPlayedAt)
        let start = try XCTUnwrap(library.continueStart(of: folder))
        XCTAssertIdentical(start.page, b)
        XCTAssertEqual(start.spot.paragraph, 1, "at its spot")

        library.recordFinished(b)
        XCTAssertNil(folder.finishedAt, "a page still follows")
        XCTAssertEqual(library.continueStart(of: folder)?.page.listenKey, library.pages(in: folder)[2].listenKey,
                       "a finished place: Continue goes on to the next page")

        try library.move([.page(b)], to: nil)
        XCTAssertEqual(folder.currentPageKey, a.listenKey, "a place filed elsewhere moves to the page before it")
    }

    func testWithNoPlaceContinueResumesTheFirstPageWhereItWasHeard() throws {
        let folder = try library.makeFolder(name: "Finance", in: nil)
        let a = try savedPage("a", in: folder)
        _ = try savedPage("b", in: folder)
        a.positionParagraph = 1
        folder.currentPageKey = nil

        let start = try XCTUnwrap(library.continueStart(of: folder))
        XCTAssertIdentical(start.page, a)
        XCTAssertEqual(start.spot.paragraph, 1)
    }

    func testTheLastPageFinishedFinishesTheFolder() throws {
        let folder = try library.makeFolder(name: "Finance", in: nil)
        _ = try savedPage("a", in: folder)
        let b = try savedPage("b", in: folder)
        library.recordPlaybackStarted(b)
        library.recordFinished(b)
        XCTAssertNotNil(folder.finishedAt)
        XCTAssertEqual(library.continueStart(of: folder)?.page.title, "a", "a finished folder starts again")
        XCTAssertNil(folder.finishedAt)
    }

    func testAPageOfAFolderPlaysFromItAndABookChapterShowsItsBook() throws {
        let folder = try library.makeFolder(name: "Finance", in: nil)
        let page = try savedPage("a", in: folder)
        let session = SpeechSession.page(page)
        XCTAssertEqual(session.folder, PlaybackFolder(id: folder.id, name: "Finance", isBookOrSeries: false))
        XCTAssertEqual(session.site, page.byline, "a folder you made doesn't stand in for the page's site")

        let loose = try savedPage("loose", in: nil)
        XCTAssertNil(SpeechSession.page(loose).folder, "a page in no folder plays to its end")
        XCTAssertNil(library.folder(containing: loose.listenKey))
    }
}
