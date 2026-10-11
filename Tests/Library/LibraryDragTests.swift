import SwiftData
import SwiftUI
import XCTest
@testable import MeridianReader

/// Drag to file and reorder (decision D15): the refusals a drop shares with Move, placing rows
/// between rows (the order becomes Manual, numbered as it was shown), where a drop lands, and
/// what a drag over a row aims at.
@MainActor
final class LibraryDragTests: XCTestCase {
    private var env: LibraryTestEnvironment!
    private var library: LibraryStore { env.library }

    override func setUp() async throws { env = try LibraryTestEnvironment() }
    override func tearDown() async throws { env.cleanUp() }

    private func savedPage(_ title: String, in folder: Folder?) throws -> Page {
        env.now = env.now.addingTimeInterval(60)
        return try library.save(env.article("https://example.com/\(title)", title: title), placement: .folder(folder))
    }

    private func book(in parent: Folder? = nil) throws -> (Folder, Page) {
        let book = Folder(name: "Book", kind: .book)
        env.context.insert(book)
        book.parent = parent
        let chapter = Page(key: UUID(), title: "Chapter 1", byline: "", urlString: nil, contentState: .saved,
                           addedAt: env.now, sortKey: 0)
        env.context.insert(chapter)
        chapter.setFolder(book)
        try env.context.save()
        return (book, chapter)
    }

    // MARK: - Refusals

    func testADropIsRefusedWhereMoveIsRefused() throws {
        let outer = try library.makeFolder(name: "Outer", in: nil)
        let inner = try library.makeFolder(name: "Inner", in: outer)
        let page = try savedPage("p", in: nil)
        let (book, chapter) = try book()

        XCTAssertNil(library.moveRefusal(.page(page), to: outer), "a page onto a folder")
        XCTAssertNil(library.moveRefusal(.folder(inner), to: nil), "a folder to the top level")
        XCTAssertNil(library.moveRefusal(.folder(book), to: outer), "a book itself can be filed")
        XCTAssertNil(library.moveRefusal(.page(page), to: library.favorites()), "a page onto Favorites")

        XCTAssertEqual(library.moveRefusal(.page(page), to: book), .fixedDestination, "a book takes no drops")
        XCTAssertEqual(library.moveRefusal(.folder(inner), to: book), .fixedDestination)
        XCTAssertEqual(library.moveRefusal(.folder(outer), to: outer), .cycle, "a folder onto itself")
        XCTAssertEqual(library.moveRefusal(.folder(outer), to: inner), .cycle, "a folder into its own subfolder")
        XCTAssertEqual(library.moveRefusal(.page(chapter), to: nil), .leavesFixedFolder, "a chapter never leaves its book")
        XCTAssertEqual(library.moveRefusal(.folder(library.favorites()), to: outer), .favoritesIsPinned)
    }

    func testPlacingIsRefusedInABookAndOutOfIt() throws {
        let (book, chapter) = try book()
        let page = try savedPage("p", in: nil)
        XCTAssertThrowsError(try library.arrange([page], in: book, before: chapter, shownIn: .manual)) {
            XCTAssertEqual($0 as? LibraryTreeError, .fixedDestination)
        }
        XCTAssertThrowsError(try library.arrange([chapter], in: book, before: nil, shownIn: .manual),
                             "a book's order is its source's")
        XCTAssertThrowsError(try library.arrange([chapter], in: nil, before: page, shownIn: .newest)) {
            XCTAssertEqual($0 as? LibraryTreeError, .leavesFixedFolder)
        }
        XCTAssertNil(page.folder, "nothing changed")
        XCTAssertIdentical(chapter.folder, book)

        let outer = try library.makeFolder(name: "Outer", in: nil)
        let inner = try library.makeFolder(name: "Inner", in: outer)
        XCTAssertThrowsError(try library.arrange([outer], in: outer, before: inner)) {
            XCTAssertEqual($0 as? LibraryTreeError, .cycle)
        }
        XCTAssertNil(outer.parent)
    }

    // MARK: - Placing between rows

    func testPlacingAPageMakesTheOrderManualNumberedAsShown() throws {
        let folder = try library.makeFolder(name: "F", in: nil)
        let a = try savedPage("a", in: folder)
        let b = try savedPage("b", in: folder)
        let c = try savedPage("c", in: folder)
        // Stored order (Manual) the reverse of the order added.
        (a.sortKey, b.sortKey, c.sortKey) = (2, 1, 0)
        try library.setSort(.newest, for: folder)
        XCTAssertEqual(library.pages(in: folder).map(\.title), ["c", "b", "a"], "shown newest first")

        // a dragged to just before b, as shown.
        try library.arrange([a], in: folder, before: b, shownIn: .newest)
        XCTAssertEqual(folder.pageSort, .manual)
        XCTAssertEqual(library.pages(in: folder).map(\.title), ["c", "a", "b"], "where it was let go, in the order shown")
    }

    func testPlacingAPageFromAnotherFolderFilesItThere() throws {
        let source = try library.makeFolder(name: "Source", in: nil)
        let target = try library.makeFolder(name: "Target", in: nil)
        let moving = try savedPage("moving", in: source)
        let x = try savedPage("x", in: target)
        let y = try savedPage("y", in: target)
        library.recordPlaybackStarted(moving)
        XCTAssertEqual(source.currentPageKey, moving.listenKey)

        try library.arrange([moving], in: target, before: y, shownIn: .manual)
        XCTAssertIdentical(moving.folder, target)
        XCTAssertEqual(library.pages(in: target).map(\.title), ["x", "moving", "y"])
        XCTAssertNil(source.currentPageKey, "the folder it left has no place on it")
        XCTAssertEqual(x.folderID, target.id)
    }

    func testPlacingAPageAtTheTopLevel() throws {
        let a = try savedPage("a", in: nil)
        let b = try savedPage("b", in: nil)
        try library.arrange([a], in: nil, before: nil, shownIn: .newest)
        XCTAssertEqual(library.loosePages(sort: .manual).map(\.title), ["b", "a"])
        XCTAssertIdentical(library.loosePages(sort: .manual).first, b)
    }

    func testPlacingAFolderBesideAnother() throws {
        _ = library.favorites()
        let a = try library.makeFolder(name: "A", in: nil)
        let b = try library.makeFolder(name: "B", in: nil)
        let c = try library.makeFolder(name: "C", in: a)
        try library.arrange([c], in: nil, before: a)
        XCTAssertNil(c.parent, "out of A, to the top level")
        XCTAssertEqual(library.topLevelFolders().map(\.displayName), ["Favorites", "C", "A", "B"],
                       "Favorites stays first")
    }

    // MARK: - Where a drop lands

    private final class Item {
        let name: String
        init(_ name: String) { self.name = name }
    }

    private func name(_ placement: LibraryDropSlot.Placement<Item>) -> String {
        switch placement {
        case .unchanged: "unchanged"
        case .before(let item): item?.name ?? "end"
        }
    }

    func testWhereADropBetweenRowsLands() {
        let (a, b, c) = (Item("a"), Item("b"), Item("c"))
        let rows = [a, b, c]
        XCTAssertEqual(name(LibraryDropSlot.placement(of: c, beside: a, edge: .top, siblings: rows)), "a")
        XCTAssertEqual(name(LibraryDropSlot.placement(of: a, beside: c, edge: .bottom, siblings: rows)), "end")
        XCTAssertEqual(name(LibraryDropSlot.placement(of: a, beside: b, edge: .bottom, siblings: rows)), "c")
        XCTAssertEqual(name(LibraryDropSlot.placement(of: b, beside: b, edge: .top, siblings: rows)), "unchanged")
        XCTAssertEqual(name(LibraryDropSlot.placement(of: b, beside: a, edge: .bottom, siblings: rows)), "unchanged",
                       "just below the row above it: where it is")
        XCTAssertEqual(name(LibraryDropSlot.placement(of: b, beside: c, edge: .top, siblings: rows)), "unchanged")
        let other = Item("other")
        XCTAssertEqual(name(LibraryDropSlot.placement(of: other, beside: c, edge: .bottom, siblings: rows)), "end",
                       "a row from elsewhere")
    }

    func testWhatADragOverARowAimsAt() {
        let folder = UUID(), other = UUID(), page = UUID(), otherPage = UUID()
        func aim(_ dragging: LibraryItemID, _ row: LibraryItemID, _ fraction: CGFloat, takes: Bool = true,
                 beside: Bool = true) -> LibraryDropAim {
            LibraryDropAim.aim(dragging: dragging, over: row, fraction: fraction, takesInto: takes, besideAllowed: beside)
        }
        XCTAssertEqual(aim(.page(page), .folder(folder), 0.1), .into(folder), "a page goes into a folder, anywhere on it")
        XCTAssertEqual(aim(.page(page), .folder(folder), 0.5, takes: false), .refusedInto(folder), "a book refuses it")
        XCTAssertEqual(aim(.folder(other), .folder(folder), 0.1), .beside(.folder(folder), .top))
        XCTAssertEqual(aim(.folder(other), .folder(folder), 0.9), .beside(.folder(folder), .bottom))
        XCTAssertEqual(aim(.folder(other), .folder(folder), 0.5), .into(folder), "a folder's middle files it inside")
        XCTAssertEqual(aim(.folder(other), .folder(folder), 0.1, beside: false), .into(folder))
        XCTAssertEqual(aim(.page(page), .page(otherPage), 0.3), .beside(.page(otherPage), .top))
        XCTAssertEqual(aim(.page(page), .page(otherPage), 0.7), .beside(.page(otherPage), .bottom))
        XCTAssertEqual(aim(.page(page), .page(otherPage), 0.7, beside: false), .nothing, "a page played without saving")
        XCTAssertEqual(aim(.folder(folder), .page(page), 0.5), .nothing, "folders don't go among pages")
    }
}
