import SwiftData
import XCTest
@testable import MeridianReader

/// The folder tree: nesting, moves and their refusals, both kinds of folder delete, Favorites'
/// rules, and the fractional order. Books and series follow every folder rule (decision D19).
@MainActor
final class LibraryTreeTests: XCTestCase {
    private var env: LibraryTestEnvironment!
    private var library: LibraryStore { env.library }

    override func setUp() async throws { env = try LibraryTestEnvironment() }
    override func tearDown() async throws { env.cleanUp() }

    private func savedPage(_ path: String, in folder: Folder?) throws -> Page {
        try library.save(env.article("https://example.com/\(path)", title: path), placement: .folder(folder))
    }

    func testFoldersNestToDepthFive() throws {
        var parent: Folder?
        var chain: [Folder] = []
        for level in 1...5 {
            let folder = try library.makeFolder(name: "Level \(level)", in: parent)
            chain.append(folder)
            parent = folder
        }
        let deepest = try XCTUnwrap(parent)
        XCTAssertEqual(deepest.depth, 5)
        XCTAssertEqual(deepest.ancestors.map(\.name), ["Level 4", "Level 3", "Level 2", "Level 1"])
        let page = try savedPage("deep", in: deepest)
        XCTAssertIdentical(page.folder, deepest)
        XCTAssertEqual(page.folderID, deepest.id)
        XCTAssertEqual(library.subfolders(of: chain[2]).map(\.name), ["Level 4"])
    }

    /// Moves refuse only a cycle (and Favorites below the top level): a book or series takes
    /// pages and subfolders, and its chapters move out (decision D19). A refused move changes
    /// nothing.
    func testMoveRefusesACycleAndABookTakesAnyMove() throws {
        let outer = try library.makeFolder(name: "Outer", in: nil)
        let inner = try library.makeFolder(name: "Inner", in: outer)
        XCTAssertThrowsError(try library.move([.folder(outer)], to: inner)) { XCTAssertEqual($0 as? LibraryTreeError, .cycle) }
        XCTAssertThrowsError(try library.move([.folder(outer)], to: outer)) { XCTAssertEqual($0 as? LibraryTreeError, .cycle) }
        let loose = try savedPage("loose", in: nil)
        XCTAssertThrowsError(try library.move([.page(loose), .folder(outer)], to: inner)) {
            XCTAssertEqual($0 as? LibraryTreeError, .cycle)
        }
        XCTAssertNil(loose.folder, "a refused move changes nothing")
        XCTAssertIdentical(outer.parent, nil)

        let book = Folder(name: "Book", kind: .book)
        env.context.insert(book)
        let chapter = try library.addLink(url: URL(string: "https://example.com/ch")!, title: "Ch", artwork: nil, in: book)
        try library.move([.page(loose), .folder(inner)], to: book)
        XCTAssertIdentical(loose.folder, book, "a page into a book")
        XCTAssertIdentical(inner.parent, book, "a folder into a book")
        let made = try library.makeFolder(name: "Inside a book", in: book)
        XCTAssertIdentical(made.parent, book)
        try library.move([.page(chapter)], to: outer)
        XCTAssertIdentical(chapter.folder, outer, "a chapter out of its book")
        try library.move([.folder(book)], to: outer)
        XCTAssertIdentical(book.parent, outer, "a book itself can be moved")
        XCTAssertThrowsError(try library.move([.folder(outer)], to: book)) { XCTAssertEqual($0 as? LibraryTreeError, .cycle) }
    }

    /// A book's order is yours: its sort changes, and pages are placed among its chapters.
    func testABooksOrderIsYours() throws {
        let book = Folder(name: "Book", kind: .book)
        env.context.insert(book)
        let chapters = try (1...3).map {
            try library.addLink(url: URL(string: "https://example.com/ch\($0)")!, title: "Ch \($0)", artwork: nil, in: book)
        }
        let article = try savedPage("Article", in: nil)
        try library.arrange([chapters[2], article], in: book, before: chapters[0], shownIn: .manual)
        XCTAssertEqual(library.pages(in: book).map(\.title), ["Ch 3", "Article", "Ch 1", "Ch 2"])
        try library.setSort(.title, for: book)
        XCTAssertEqual(book.pageSort, .title)
        XCTAssertEqual(library.pages(in: book).map(\.title), ["Article", "Ch 1", "Ch 2", "Ch 3"], "it plays in its sort")
    }

    func testDeleteFolderAndContentsDeletesNestedBooksAndTheirAudio() throws {
        let shelf = try library.makeFolder(name: "Shelf", in: nil)
        let nested = try library.makeFolder(name: "Nested", in: shelf)
        let book = Folder(name: "Book", kind: .book)
        env.context.insert(book)
        book.parent = nested
        let chapter = try library.save(env.article("https://example.com/ch1", title: "Ch 1"))
        chapter.setFolder(book)
        let page = try savedPage("on-shelf", in: shelf)
        let keys = [chapter.key!, page.key!]
        for (key, p) in zip(keys, [chapter, page]) { try env.storeAudio(key, paragraphs: p.cachedListenParagraphs ?? []) }
        XCTAssertEqual(library.contents(of: shelf).folders, 2)
        XCTAssertEqual(library.contents(of: shelf).pages, 2)
        env.playingKey = chapter.key

        try library.deleteFolder(shelf)
        XCTAssertTrue(env.folders().filter { $0.kind != .favorites }.isEmpty)
        XCTAssertTrue(env.pages().isEmpty)
        for key in keys { XCTAssertFalse(env.cache.hasCache(for: key)) }
        XCTAssertEqual(env.stoppedKeys, [keys[0]], "the playing chapter stopped first")
    }

    func testLegacyFavoritesFolderHasOrdinaryFolderRules() throws {
        let favorites = env.legacyFavoritesFolder()
        let other = try library.makeFolder(name: "Other", in: nil)
        try library.rename(favorites, to: "Mine")
        try library.move([.folder(favorites)], to: other)
        XCTAssertEqual(favorites.name, "Mine")
        XCTAssertIdentical(favorites.parent, other)
    }

    func testReorderWritesFractionalKeysAndRenumbersWhenTheGapIsTiny() throws {
        let folder = try library.makeFolder(name: "F", in: nil)
        let pages = try ["a", "b", "c", "d"].map { try savedPage($0, in: folder) }
        try library.arrange([pages[3]], in: folder, before: pages[1], shownIn: .manual)
        XCTAssertEqual(library.pages(in: folder).map(\.title), ["a", "d", "b", "c"])
        try library.arrange([pages[0]], in: folder, before: nil, shownIn: .manual)
        XCTAssertEqual(library.pages(in: folder).map(\.title), ["d", "b", "c", "a"])
        for _ in 0..<80 {
            try library.arrange([pages[2]], in: folder, before: pages[1], shownIn: .manual)
            try library.arrange([pages[1]], in: folder, before: pages[2], shownIn: .manual)
        }
        XCTAssertEqual(library.pages(in: folder).map(\.title), ["d", "b", "c", "a"], "many moves never collide")
        let keys = library.pages(in: folder).map(\.sortKey)
        XCTAssertEqual(Set(keys).count, keys.count)
    }
}
