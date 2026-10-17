import SwiftData
import XCTest
@testable import MeridianReader

/// Pages played without saving (decision D5): the top of the Library's *Pages*, marked "Not
/// saved", most recently played first (`LibraryQueries.playedNotSaved`), and *Save* puts one in
/// the Library. A page removed from the Library is in no list, not even this one, as it plays on,
/// until it is saved or listened to again (`Page.removedAt`), and keeps its star, which keeps it
/// in Favorites.
@MainActor
final class PlayedNotSavedTests: XCTestCase {
    private var env: LibraryTestEnvironment!
    private var library: LibraryStore { env.library }

    override func setUp() async throws { env = try LibraryTestEnvironment() }
    override func tearDown() async throws { env.cleanUp() }

    private struct SaveFailed: Error {}

    private func notSaved() throws -> [Page] { try env.context.fetch(LibraryQueries.playedNotSaved) }

    /// Every list a page can be in (`LibraryQueries`), by the lists' own fetches.
    private func lists(holding page: Page) throws -> [String] {
        let lists: [(String, FetchDescriptor<Page>)] = [
            ("Pages", LibraryQueries.loosePages(sort: .newest)),
            ("Search", LibraryQueries.searchPages(page.title, favoritesOnly: false)),
            ("Favorites", LibraryQueries.favoritePages), ("Not saved", LibraryQueries.playedNotSaved),
            ("Suggestions", LibraryQueries.savedInLibrary),
        ]
        return try lists.filter { try env.context.fetch($0.1).contains { $0 === page } }.map(\.0)
    }

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

    // MARK: - Removed

    /// *Remove from Library* on a page that was played (a saved page, starred, part-way): out of
    /// every list it was in, and not back as "Not saved". It is still there for what plays: the
    /// bar resumes it, Now Playing has its text, and its audio is ephemeral.
    func testRemovingAPlayedPageTakesItOutOfEveryList() throws {
        let url = URL(string: "https://example.com/heard")!
        let page = try library.save(env.article(url.absoluteString))
        try library.addFavorite(url: url, title: nil, artwork: nil)
        env.now += 60
        library.recordPlaybackStarted(page)
        library.recordPosition(page, paragraph: 1, utf16Offset: 3)
        XCTAssertEqual(try lists(holding: page), ["Pages", "Search", "Favorites", "Suggestions"])

        env.now += 60
        try library.remove([page])
        XCTAssertEqual(try lists(holding: page), ["Favorites"], "in no Library list, Not saved included; starred, in Favorites")
        XCTAssertEqual(page.removedAt, env.now)
        XCTAssertTrue(page.isFavorite, "the star stays")
        XCTAssertIdentical(library.page(url: url), page, "kept for what plays")
        XCTAssertTrue(page.hasText)
        XCTAssertEqual(page.positionParagraph, 1)
        XCTAssertIdentical(try env.context.fetch(LibraryQueries.lastPlayed).first, page, "the bar still resumes it")
    }

    /// The page you hear, removed (🔖 in Now Playing): it plays on, is paused and resumed, and
    /// played to the end, and stays out of every list throughout.
    func testARemovedPageStaysOutOfEveryListAsItPlaysOn() throws {
        let article = env.article("https://example.com/playing")
        let page = try library.save(article)
        library.recordPlayback(article)
        try library.remove([page])
        XCTAssertEqual(try lists(holding: page), [])

        env.now += 60
        library.recordPosition(page, paragraph: 1, utf16Offset: 0)
        library.recordPlaybackStarted(page)
        library.recordFinished(page)
        XCTAssertEqual(try lists(holding: page), [], "playing on never lists it again")
        XCTAssertNotNil(page.lastPlayedAt)
    }

    /// Listened to again from its article (🎧, the Reader's Listen), a removed page is played
    /// without saving again, like any page you listen to: "Not saved" lists it.
    func testListeningToARemovedPageAgainListsItAsNotSaved() throws {
        let article = env.article("https://example.com/heard-again")
        let page = try library.save(article)
        library.recordPlayback(article)
        try library.remove([page])

        env.now += 60
        XCTAssertIdentical(library.recordPlayback(article), page, "the same page")
        XCTAssertEqual(try lists(holding: page), ["Search", "Not saved"])
        XCTAssertNil(page.removedAt)
    }

    /// That listen, while saves fail, outlasts a failed edit's rollback: once a save works, the
    /// page is "Not saved", not removed (`PendingListening`).
    func testListeningToARemovedPageWhileSavesFailListsItThroughARollback() throws {
        let article = env.article("https://example.com/heard-while-failing")
        let page = try library.save(article)
        let other = try library.save(env.article("https://example.com/other"))
        library.recordPlayback(article)
        try library.remove([page])

        env.now += 60
        library.saveContext = { _ in throw SaveFailed() }
        library.recordPlayback(article)
        XCTAssertThrowsError(try library.remove([other]), "a failed edit rolls back")
        XCTAssertEqual(try lists(holding: page), ["Search", "Not saved"], "the listen is written again")

        library.saveContext = { try $0.save() }
        XCTAssertTrue(library.commit("test"))
        XCTAssertEqual(try lists(holding: page), ["Search", "Not saved"])
        XCTAssertNil(page.removedAt)
    }

    /// Saved again, a removed page is back in the Library (*Pages*); removed again, it is out.
    func testSavingARemovedPageBringsItBackAndRemovingItAgainTakesItOut() throws {
        let article = env.article("https://example.com/again")
        let page = try library.save(article)
        library.recordPlayback(article)
        try library.remove([page])

        env.now += 60
        try library.save(ReaderArticle(page: page))
        XCTAssertEqual(try lists(holding: page), ["Pages", "Search", "Suggestions"])

        env.now += 60
        try library.remove([page])
        XCTAssertEqual(try lists(holding: page), [])
        XCTAssertEqual(page.removedAt, env.now)
    }

    /// A remove that can't be saved changes nothing: it throws, the page is in the lists it was
    /// in, and isn't marked removed.
    func testARemoveThatCantBeSavedLeavesThePageInItsLists() throws {
        let article = env.article("https://example.com/kept")
        let page = try library.save(article)
        library.recordPlayback(article)
        library.saveContext = { _ in throw SaveFailed() }

        XCTAssertThrowsError(try library.remove([page])) { XCTAssertEqual($0 as? LibraryStoreError, .saveFailed) }
        XCTAssertEqual(try lists(holding: page), ["Pages", "Search", "Suggestions"], "where it was")
        XCTAssertNil(page.removedAt)
        XCTAssertNotNil(page.addedAt)
    }

    /// Remove is one operation from every path, and never clears the star, and the star is
    /// independent of the Library: a starred page in a folder and a starred link (☆ made it) leave
    /// their folder and every Library list but stay in Favorites, and the prune keeps them.
    /// Unstarred, a removed page is in no list, and the prune deletes it.
    func testARemovedFavoriteStaysInFavoritesUntilUnstarred() throws {
        let folder = try library.makeFolder(name: "Essays", in: nil)
        let page = try library.save(env.article("https://example.com/starred"), placement: .folder(folder))
        try library.addFavorite(page)
        let link = try library.addFavorite(url: URL(string: "https://example.com/link")!, title: "Link", artwork: nil)
        XCTAssertEqual(try lists(holding: page), ["Search", "Favorites", "Suggestions"])

        try library.remove([page, link])
        XCTAssertNil(page.folder, "out of its folder")
        env.now += 30 * 24 * 3600
        library.pruneUnsaved()
        for removed in [page, link] {
            XCTAssertFalse(removed.isDeleted, "the prune keeps a starred page")
            XCTAssertEqual(try lists(holding: removed), ["Favorites"], "out of the Library, still in Favorites")
            XCTAssertTrue(removed.isFavorite, "the star stays")
        }

        try library.removeFavorite(page)
        XCTAssertEqual(try lists(holding: page), [], "unstarred: in no list")
        library.pruneUnsaved()
        XCTAssertNil(library.page(url: URL(string: "https://example.com/starred")!), "and pruned")
    }
}
