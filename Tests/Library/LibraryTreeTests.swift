import SwiftData
import XCTest
@testable import MeridianReader

/// The folder tree: nesting, moves and their refusals, both kinds of folder delete, Favorites'
/// rules, and the fractional order.
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

    func testMoveRefusesACycleABookDestinationAndAPageLeavingABook() throws {
        let outer = try library.makeFolder(name: "Outer", in: nil)
        let inner = try library.makeFolder(name: "Inner", in: outer)
        XCTAssertThrowsError(try library.move([.folder(outer)], to: inner)) { XCTAssertEqual($0 as? LibraryTreeError, .cycle) }
        XCTAssertThrowsError(try library.move([.folder(outer)], to: outer)) { XCTAssertEqual($0 as? LibraryTreeError, .cycle) }

        let book = Folder(name: "Book", kind: .book)
        env.context.insert(book)
        let loose = try savedPage("loose", in: nil)
        XCTAssertThrowsError(try library.move([.page(loose)], to: book)) {
            XCTAssertEqual($0 as? LibraryTreeError, .fixedDestination)
        }
        XCTAssertThrowsError(try library.move([.folder(inner)], to: book)) {
            XCTAssertEqual($0 as? LibraryTreeError, .fixedDestination)
        }
        XCTAssertThrowsError(try library.makeFolder(name: "Inside a book", in: book))

        let chapter = try library.addLink(url: URL(string: "https://example.com/ch")!, title: "Ch", artwork: nil, in: book)
        XCTAssertThrowsError(try library.move([.page(loose), .page(chapter)], to: outer)) {
            XCTAssertEqual($0 as? LibraryTreeError, .leavesFixedFolder)
        }
        XCTAssertNil(loose.folder, "a refused move changes nothing")
        XCTAssertIdentical(inner.parent, outer)

        try library.move([.folder(inner), .page(loose)], to: nil)
        XCTAssertNil(inner.parent)
        XCTAssertNil(loose.folderID)
        try library.move([.folder(book)], to: outer)
        XCTAssertIdentical(book.parent, outer, "a book itself can be moved")
    }

    func testDeleteFolderOnlyMovesItsContentsUpOneLevelInOrder() throws {
        let parent = try library.makeFolder(name: "Parent", in: nil)
        let existing = try savedPage("existing", in: parent)
        let doomed = try library.makeFolder(name: "Doomed", in: parent)
        let sub1 = try library.makeFolder(name: "Sub 1", in: doomed)
        let sub2 = try library.makeFolder(name: "Sub 2", in: doomed)
        let pages = try ["p1", "p2", "p3"].map { try savedPage($0, in: doomed) }
        let key = try XCTUnwrap(pages[0].key)
        try env.storeAudio(key, paragraphs: pages[0].cachedListenParagraphs ?? [])

        try library.deleteFolder(doomed, keepContents: true)
        XCTAssertFalse(env.folders().contains { $0.name == "Doomed" })
        XCTAssertEqual(library.subfolders(of: parent).map(\.name), ["Sub 1", "Sub 2"])
        XCTAssertEqual(library.pages(in: parent).map(\.title), ["existing", "p1", "p2", "p3"],
                       "after the parent's own pages, in their order")
        XCTAssertTrue(env.cache.hasCache(for: key), "nothing's audio is touched")
        _ = (existing, sub1, sub2)

        // At the top level, contents go to the top level.
        try library.deleteFolder(parent, keepContents: true)
        XCTAssertEqual(Set(library.topLevelFolders().map(\.name)), ["Sub 1", "Sub 2"])
        XCTAssertEqual(try env.context.fetch(LibraryQueries.loosePages(sort: .manual)).map(\.title), ["existing", "p1", "p2", "p3"])
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
        XCTAssertEqual(library.contentsCount(of: shelf).folders, 2)
        XCTAssertEqual(library.contentsCount(of: shelf).pages, 2)
        env.playingKey = chapter.key

        try library.deleteFolder(shelf, keepContents: false)
        XCTAssertTrue(env.folders().filter { $0.kind != .favorites }.isEmpty)
        XCTAssertTrue(env.pages().isEmpty)
        for key in keys { XCTAssertFalse(env.cache.hasCache(for: key)) }
        XCTAssertEqual(env.stoppedKeys, [keys[0]], "the playing chapter stopped first")
    }

    /// A plain folder and a book deleted together, keeping contents: the folder's page moves up,
    /// the book goes with its chapter and the chapter's audio (a chapter never outlives its
    /// book). Two books deleted together, keeping contents, go whole too.
    func testDeletingFoldersKeepingContentsStillDeletesBooksWhole() throws {
        let shelf = try library.makeFolder(name: "Shelf", in: nil)
        let inner = try savedPage("inner", in: shelf)
        let books = try (1...3).map { n -> (Folder, Page) in
            let book = Folder(name: "Book \(n)", kind: n == 3 ? .series : .book)
            env.context.insert(book)
            let chapter = try library.save(env.article("https://example.com/book\(n)/ch1", title: "Ch 1"))
            chapter.setFolder(book)
            return (book, chapter)
        }
        for (_, chapter) in books { try env.storeAudio(chapter.key!, paragraphs: chapter.cachedListenParagraphs ?? []) }
        let keys = books.map { $0.1.key! }

        try library.deleteFolders([shelf, books[0].0], keepContents: true)
        XCTAssertNil(inner.folder, "the folder's page moved up")
        XCTAssertNotNil(library.page(key: inner.key!))
        XCTAssertNil(library.page(key: keys[0]), "the book's chapter went with it")
        XCTAssertFalse(env.cache.hasCache(for: keys[0]), "and its audio")

        try library.deleteFolders([books[1].0, books[2].0], keepContents: true)
        XCTAssertTrue(env.folders().filter { $0.kind != .favorites }.isEmpty)
        XCTAssertEqual(env.pages().map(\.key), [inner.key])
        for key in keys { XCTAssertFalse(env.cache.hasCache(for: key)) }
    }

    func testFavoritesCantBeDeletedRenamedOrMovedDown() throws {
        let favorites = library.favorites()
        let other = try library.makeFolder(name: "Other", in: nil)
        XCTAssertThrowsError(try library.deleteFolder(favorites, keepContents: true))
        XCTAssertThrowsError(try library.deleteFolder(favorites, keepContents: false))
        XCTAssertThrowsError(try library.rename(favorites, to: "Mine"))
        XCTAssertThrowsError(try library.move([.folder(favorites)], to: other))
        XCTAssertIdentical(library.favorites(), favorites, "still the one Favorites")
        XCTAssertEqual(library.topLevelFolders().first?.kind, .favorites, "pinned first")
        XCTAssertEqual(favorites.displayName, "Favorites")
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
