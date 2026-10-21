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




    // MARK: - Removed






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


}
