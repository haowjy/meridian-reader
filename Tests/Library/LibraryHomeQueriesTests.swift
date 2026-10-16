import SwiftData
import XCTest
@testable import MeridianReader

/// The Library home's lists come from `LibraryQueries`: the starred folders at any depth, and the
/// search across the tree, which finds pages and folders in one order (pages by title, then
/// newest; folders by name).
@MainActor
final class LibraryHomeQueriesTests: XCTestCase {
    private var env: LibraryTestEnvironment!
    private var library: LibraryStore { env.library }

    override func setUp() async throws { env = try LibraryTestEnvironment() }
    override func tearDown() async throws { env.cleanUp() }

    func testFavoriteFoldersAreTheStarredOnesAtAnyDepth() throws {
        let finance = try library.makeFolder(name: "Finance", in: nil)
        let bonds = try library.makeFolder(name: "Bonds", in: finance)
        try library.makeFolder(name: "Taxes", in: finance)
        try library.toggleFavorite(bonds)
        XCTAssertEqual(try env.context.fetch(LibraryQueries.favoriteFolders).map(\.name), ["Bonds"])
    }

    func testSearchFindsPagesAcrossTheTreeInOneOrder() throws {
        let shelf = try library.makeFolder(name: "Shelf", in: nil)
        env.now = Date(timeIntervalSince1970: 1_800_000_000)
        let older = try library.save(env.article("https://example.com/b-old", title: "Harbor Notes"))
        env.now += 60
        let newer = try library.save(env.article("https://example.com/b-new", title: "Harbor Notes"))
        let filed = try library.save(env.article("https://example.com/a", title: "A harbor in winter"))
        try library.move([.page(filed)], to: shelf)
        let played = library.recordPlayback(env.article("https://example.com/played", title: "Harbor tides"))
        let removed = try library.save(env.article("https://example.com/removed", title: "Harbor removed"))
        try library.remove([removed])
        try library.save(env.article("https://example.com/other", title: "Something else"))

        let found = try env.context.fetch(LibraryQueries.searchPages("HARBOR", favoritesOnly: false))
        XCTAssertEqual(found.map(\.key), [filed.key, newer.key, older.key, played.key],
                       "by title, then newest first; a page played without saving too; not a removed page")

        try library.addFavorite(older)
        XCTAssertEqual(try env.context.fetch(LibraryQueries.searchPages("harbor", favoritesOnly: true)).map(\.key), [older.key],
                       "on Favorites, starred pages only")
    }

    func testSearchFindsFoldersByNameOrAuthor() throws {
        let finance = try library.makeFolder(name: "Finance", in: nil)
        let bonds = try library.makeFolder(name: "Bonds", in: finance)
        let novel = try library.makeFolder(name: "A Novel", in: nil)
        try library.setDetails(of: novel, name: "A Novel", byline: "Jane Bondsworth", cover: nil)
        XCTAssertEqual(try env.context.fetch(LibraryQueries.searchFolders("bonds", favoritesOnly: false)).map(\.name),
                       ["A Novel", "Bonds"], "by name, an author's name too")

        try library.toggleFavorite(bonds)
        XCTAssertEqual(try env.context.fetch(LibraryQueries.searchFolders("bonds", favoritesOnly: true)).map(\.name), ["Bonds"])
    }
}
