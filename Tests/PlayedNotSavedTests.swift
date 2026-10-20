import SwiftData
import XCTest
@testable import MeridianReader

/// Pages played without saving (decision D5): the Library home's Recent tab, most recently
/// played first (`LibraryQueries.recent`), never Everything, and *Save to Library* puts one in
/// the Library. A page removed from the Library is in no list, not even this one, nor the bar's
/// resume, until it is saved or listened to again (`Article.removedAt`); if you hear it, it stops;
/// and it keeps its star, which keeps it in Favorites.
@MainActor
final class PlayedNotSavedTests: XCTestCase {
    private var env: LibraryTestEnvironment!
    private var library: LibraryStore { env.library }

    override func setUp() async throws { env = try LibraryTestEnvironment() }
    override func tearDown() async throws { env.cleanUp() }

    private struct SaveFailed: Error {}

    private func recent() throws -> [Article] { try env.context.fetch(LibraryQueries.recent) }

    /// Every list a page can be in (`LibraryQueries`), by the lists' own fetches.
    private func lists(holding article: Article) throws -> [String] {
        let lists: [(String, FetchDescriptor<Article>)] = [
            ("Pages", LibraryQueries.looseArticles(sort: .newest)),
            ("Search", LibraryQueries.searchArticles(article.title, in: .everything)),
            ("Favorites", LibraryQueries.favoriteArticles), ("Recent", LibraryQueries.recent),
            ("Recent search", LibraryQueries.searchArticles(article.title, in: .recent)),
            ("Suggestions", LibraryQueries.savedInLibrary),
        ]
        return try lists.filter { try env.context.fetch($0.1).contains { $0 === article } }.map(\.0)
    }

    func testEveryPlayedArticleShowsMostRecentFirstAndStaysOutOfTheLibrary() throws {
        var played: [UUID] = []
        for i in 0..<5 {
            env.now = Date(timeIntervalSince1970: 1_800_000_000 + Double(i) * 60)
            played.append(env.library.recordPlayback(env.article("https://example.com/played-\(i)")).listenKey)
        }
        let articles = try recent()
        XCTAssertEqual(articles.map(\.listenKey), Array(played.reversed()), "every one, most recent first")
        XCTAssertTrue(articles.allSatisfy { !$0.isInLibrary && $0.folder == nil }, "listed, not saved or moved")
        XCTAssertTrue(try env.context.fetch(LibraryQueries.looseArticles(sort: .newest)).isEmpty,
                      "the saved pages' query doesn't list them")
    }

    func testSavedArticlesLinksAndChaptersStayOut() throws {
        let context = env.context
        func article(_ title: String, state: ArticleContentState = .saved, added: Date? = nil) -> Article {
            let article = Article(key: UUID(), title: title, byline: "example.com", urlString: "https://example.com/\(title)",
                            contentState: state, addedAt: added)
            context.insert(article)
            article.lastPlayedAt = env.now
            return article
        }
        _ = article("saved", added: env.now)
        _ = article("link", state: .link)
        let book = Folder(name: "Book", kind: .book)
        context.insert(book)
        article("chapter").setFolder(book)
        let neverPlayed = article("never played")
        neverPlayed.lastPlayedAt = nil
        _ = article("played")
        try context.save()
        // Recent lists everything played, saved pages included (C104); links and chapters stay out.
        XCTAssertEqual(Set(try recent().map(\.title)), ["played", "saved"])
        XCTAssertEqual(try recent().map(LibraryQueries.isInRecent), [true, true], "the one-page check agrees")
    }

    /// *Save* in the row's menu (`LibraryActions.save`) saves the page's own copy of itself: into
    /// the top level, the same page.
    func testSavingItsOwnCopyMovesItIntoTheArticles() throws {
        let article = env.library.recordPlayback(env.article("https://example.com/keep-me"))
        XCTAssertEqual(try recent().count, 1)
        try env.library.save(ReaderArticle(article: article))
        XCTAssertTrue(article.isSavedToLibrary)
        XCTAssertEqual(try recent().map(\.listenKey), [article.listenKey], "still in Recent: it was played (C104)")
        XCTAssertEqual(try env.context.fetch(LibraryQueries.looseArticles(sort: .newest)).map(\.listenKey), [article.listenKey],
                       "in Pages, the same page")
    }

    // MARK: - Removed

    /// *Remove from Library* on a page that was played (a saved page, starred, part-way): out of
    /// every list it was in, not back in Recent, and not the bar's to resume. It is kept, its
    /// text and place with it, for a listen to it again.
    func testRemovingAPlayedArticleTakesItOutOfEveryList() throws {
        let url = URL(string: "https://example.com/heard")!
        let article = try library.save(env.article(url.absoluteString))
        try library.addFavorite(url: url, title: nil, artwork: nil)
        env.now += 60
        library.recordPlaybackStarted(article)
        library.recordPosition(article, paragraph: 1, utf16Offset: 3)
        XCTAssertEqual(try lists(holding: article), ["Pages", "Search", "Favorites", "Recent", "Recent search", "Suggestions"])

        env.now += 60
        try library.remove([article])
        XCTAssertEqual(try lists(holding: article), [], "in no list: Favorites shows only saved pages (C104)")
        XCTAssertEqual(article.removedAt, env.now)
        XCTAssertTrue(article.isFavorite, "the star stays")
        XCTAssertIdentical(library.article(url: url), article, "kept")
        XCTAssertTrue(article.hasText)
        XCTAssertEqual(article.positionParagraph, 1)
        XCTAssertFalse(try env.context.fetch(LibraryQueries.lastPlayed).contains { $0 === article }, "the bar doesn't resume it")
    }

    /// The page you hear, removed (🔖 or ⋯ in Now Playing, the bar's long-press): playback is told
    /// to stop it, and a session a waiting merge would move onto it, once the remove is saved
    /// (`stopPlaybackIfPlaying`); a remove that can't be saved leaves it playing.
    func testRemovingTheArticleYouHearStopsItOnceTheRemoveIsSaved() throws {
        let readerArticle = env.article("https://example.com/playing")
        let article = try library.save(readerArticle)
        library.recordPlayback(readerArticle)
        let merged = UUID() // a page merged into it, its merge waiting: a session on it moves onto the page
        env.context.insert(LibraryAudioWork(sequence: 0, kind: .merge, key: article.listenKey, fromKey: merged,
                                            paragraphs: [], sourceParagraphs: []))
        try env.context.save()
        var stopped: [UUID] = []
        library.stopPlaybackIfPlaying = { key in
            XCTAssertFalse(article.hasChanges, "the remove is saved first")
            XCTAssertNotNil(article.removedAt)
            stopped.append(key)
        }

        library.saveContext = { _ in throw SaveFailed() }
        XCTAssertThrowsError(try library.remove([article]))
        XCTAssertEqual(stopped, [], "a remove that can't be saved plays on")

        library.saveContext = { try $0.save() }
        try library.remove([article])
        XCTAssertEqual(stopped, [article.listenKey, merged], "with the session its waiting merge would move onto it")
    }

    /// Listened to again from its article (🎧, the Reader's Listen), a removed page is played
    /// without saving again, like any page you listen to: Recent lists it (Everything doesn't).
    func testListeningToARemovedArticleAgainListsItInRecent() throws {
        let readerArticle = env.article("https://example.com/heard-again")
        let article = try library.save(readerArticle)
        library.recordPlayback(readerArticle)
        try library.remove([article])

        env.now += 60
        XCTAssertIdentical(library.recordPlayback(readerArticle), article, "the same page")
        XCTAssertEqual(try lists(holding: article), ["Recent", "Recent search"])
        XCTAssertNil(article.removedAt)
    }

    /// That listen, while saves fail, outlasts a failed edit's rollback: once a save works, the
    /// page is in Recent, not removed (`PendingListening`).
    func testListeningToARemovedArticleWhileSavesFailListsItThroughARollback() throws {
        let readerArticle = env.article("https://example.com/heard-while-failing")
        let article = try library.save(readerArticle)
        let other = try library.save(env.article("https://example.com/other"))
        library.recordPlayback(readerArticle)
        try library.remove([article])

        env.now += 60
        library.saveContext = { _ in throw SaveFailed() }
        library.recordPlayback(readerArticle)
        XCTAssertThrowsError(try library.remove([other]), "a failed edit rolls back")
        XCTAssertEqual(try lists(holding: article), ["Recent", "Recent search"], "the listen is written again")

        library.saveContext = { try $0.save() }
        XCTAssertTrue(library.commit("test"))
        XCTAssertEqual(try lists(holding: article), ["Recent", "Recent search"])
        XCTAssertNil(article.removedAt)
    }

    /// Saved again, a removed page is back in the Library (*Pages*); removed again, it is out.
    func testSavingARemovedArticleBringsItBackAndRemovingItAgainTakesItOut() throws {
        let readerArticle = env.article("https://example.com/again")
        let article = try library.save(readerArticle)
        library.recordPlayback(readerArticle)
        try library.remove([article])

        env.now += 60
        try library.save(ReaderArticle(article: article))
        XCTAssertEqual(try lists(holding: article), ["Pages", "Search", "Recent", "Recent search", "Suggestions"])

        env.now += 60
        try library.remove([article])
        XCTAssertEqual(try lists(holding: article), [])
        XCTAssertEqual(article.removedAt, env.now)
    }

    /// A remove that can't be saved changes nothing: it throws, the page is in the lists it was
    /// in, and isn't marked removed.
    func testARemoveThatCantBeSavedLeavesTheArticleInItsLists() throws {
        let readerArticle = env.article("https://example.com/kept")
        let article = try library.save(readerArticle)
        library.recordPlayback(readerArticle)
        library.saveContext = { _ in throw SaveFailed() }

        XCTAssertThrowsError(try library.remove([article])) { XCTAssertEqual($0 as? LibraryStoreError, .saveFailed) }
        XCTAssertEqual(try lists(holding: article), ["Pages", "Search", "Recent", "Recent search", "Suggestions"], "where it was")
        XCTAssertNil(article.removedAt)
        XCTAssertNotNil(article.addedAt)
    }

    /// Remove is one operation from every path, and never clears the star, and the star is
    /// independent of the Library: a starred page in a folder and a starred link (☆ made it) leave
    /// their folder and every Library list but stay in Favorites, and the prune keeps them.
    /// Unstarred, a removed page is in no list, and the prune deletes it.
    func testARemovedFavoriteStaysInFavoritesUntilUnstarred() throws {
        let folder = try library.makeFolder(name: "Essays", in: nil)
        let article = try library.save(env.article("https://example.com/starred"), placement: .folder(folder))
        try library.addFavorite(article)
        let link = try library.addFavorite(url: URL(string: "https://example.com/link")!, title: "Link", artwork: nil)
        XCTAssertEqual(try lists(holding: article), ["Search", "Favorites", "Suggestions"])

        try library.remove([article, link])
        XCTAssertNil(article.folder, "out of its folder")
        env.now += 30 * 24 * 3600
        library.pruneUnsaved()
        for removed in [article, link] {
            XCTAssertFalse(removed.isDeleted, "the prune keeps a starred page")
            XCTAssertEqual(try lists(holding: removed), [], "out of the Library, so out of Favorites (C104)")
            XCTAssertTrue(removed.isFavorite, "the star stays")
        }

        try library.removeFavorite(article)
        XCTAssertEqual(try lists(holding: article), [], "unstarred: in no list")
        library.pruneUnsaved()
        XCTAssertNil(library.article(url: URL(string: "https://example.com/starred")!), "and pruned")
    }

    /// Starring a page played without saving saves it to the Library's top level (C104):
    /// Favorites lists only saved pages.
    func testStarringAPlayedArticleSavesIt() throws {
        let article = env.library.recordPlayback(env.article("https://example.com/star-me"))
        XCTAssertFalse(article.isInLibrary)
        try library.addFavorite(article)
        XCTAssertTrue(article.isInLibrary)
        XCTAssertNil(article.folder)
        XCTAssertEqual(try lists(holding: article), ["Pages", "Search", "Favorites", "Recent", "Recent search", "Suggestions"])
    }
}
