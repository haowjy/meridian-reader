import SwiftData
import XCTest
@testable import MeridianReader

/// Pages played without saving (decision D5): the top of the Library's *Pages*, marked "Not
/// saved", most recently played first (`LibraryQueries.playedNotSaved`), and *Save* puts one in
/// the Library.
@MainActor
final class PlayedNotSavedTests: XCTestCase {
    private var env: LibraryTestEnvironment!

    override func setUp() async throws { env = try LibraryTestEnvironment() }
    override func tearDown() async throws { env.cleanUp() }

    private func notSaved() throws -> [Page] { try env.context.fetch(LibraryQueries.playedNotSaved) }

    func testEveryPlayedPageShowsMostRecentFirstAndStaysOutOfTheLibrary() throws {
        var played: [UUID] = []
        for i in 0..<5 {
            env.now = Date(timeIntervalSince1970: 1_800_000_000 + Double(i) * 60)
            played.append(env.library.recordPlayback(env.article("https://example.com/played-\(i)")).listenKey)
        }
        let pages = try notSaved()
        XCTAssertEqual(pages.map(\.listenKey), Array(played.reversed()), "every one, most recent first")
        XCTAssertTrue(pages.allSatisfy { !$0.isInLibrary && $0.folder == nil }, "listed, not saved or moved")
        XCTAssertTrue(try env.context.fetch(LibraryQueries.loosePages(sort: .newest)).isEmpty,
                      "the saved pages' query doesn't list them")
    }

    func testSavedPagesLinksAndChaptersStayOut() throws {
        let context = env.context
        func page(_ title: String, state: PageContentState = .saved, added: Date? = nil) -> Page {
            let page = Page(key: UUID(), title: title, byline: "example.com", urlString: "https://example.com/\(title)",
                            contentState: state, addedAt: added)
            context.insert(page)
            page.lastPlayedAt = env.now
            return page
        }
        _ = page("saved", added: env.now)
        _ = page("link", state: .link)
        let book = Folder(name: "Book", kind: .book)
        context.insert(book)
        page("chapter").setFolder(book)
        let neverPlayed = page("never played")
        neverPlayed.lastPlayedAt = nil
        _ = page("played")
        try context.save()
        XCTAssertEqual(try notSaved().map(\.title), ["played"])
    }

    /// *Save* in the row's menu (`LibraryActions.save`) saves the page's own copy of itself: into
    /// the top level, the same page.
    func testSavingItsOwnCopyMovesItIntoThePages() throws {
        let page = env.library.recordPlayback(env.article("https://example.com/keep-me"))
        XCTAssertEqual(try notSaved().count, 1)
        try env.library.save(ReaderArticle(page: page))
        XCTAssertTrue(page.isSavedToLibrary)
        XCTAssertTrue(try notSaved().isEmpty, "no longer Not saved")
        XCTAssertEqual(try env.context.fetch(LibraryQueries.loosePages(sort: .newest)).map(\.listenKey), [page.listenKey],
                       "in Pages, the same page")
    }
}
