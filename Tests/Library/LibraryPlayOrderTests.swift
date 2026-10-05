import SwiftData
import XCTest
@testable import Reader

/// A book's or series' chapters in play order: by `sortKey`, skipped ones kept and flagged, link
/// chapters included.
@MainActor
final class LibraryPlayOrderTests: XCTestCase {
    private var env: LibraryTestEnvironment!
    private var library: LibraryStore { env.library }

    override func setUp() async throws { env = try LibraryTestEnvironment() }
    override func tearDown() async throws { env.cleanUp() }

    private func chapter(_ n: Int, in folder: Folder, sortKey: Double, saved: Bool) -> Page {
        let page = Page(key: UUID(), title: "Chapter \(n)", byline: "", urlString: "https://example.com/c\(n)",
                        contentState: saved ? .saved : .link, addedAt: env.now, sortKey: sortKey)
        env.context.insert(page)
        page.setFolder(folder)
        return page
    }

    func testChaptersPlayBySortKeyWithSkippedOnesKeptAndFlagged() throws {
        let book = Folder(name: "Book", kind: .book)
        env.context.insert(book)
        let front = chapter(0, in: book, sortKey: 0, saved: true)
        front.skipsInPlayback = true
        _ = chapter(3, in: book, sortKey: 3, saved: true)
        _ = chapter(1, in: book, sortKey: 1, saved: true)
        // Inserted between 1 and 3 later: one fractional key.
        _ = chapter(2, in: book, sortKey: 1.5, saved: true)
        try env.context.save()

        let order = library.playOrder(of: book)
        XCTAssertEqual(order.map(\.title), ["Chapter 0", "Chapter 1", "Chapter 2", "Chapter 3"])
        XCTAssertEqual(order.map(\.skipsInPlayback), [true, false, false, false])
    }

    func testASeriesIncludesItsLinkChapters() throws {
        let series = Folder(name: "Serial", kind: .series)
        env.context.insert(series)
        _ = chapter(1, in: series, sortKey: 0, saved: true)
        _ = chapter(2, in: series, sortKey: 1, saved: false)
        _ = chapter(3, in: series, sortKey: 2, saved: false)
        try env.context.save()

        let order = library.playOrder(of: series)
        XCTAssertEqual(order.map(\.title), ["Chapter 1", "Chapter 2", "Chapter 3"])
        XCTAssertEqual(order.map(\.contentState), [.saved, .link, .link])
        XCTAssertEqual(series.pageSort, .manual, "books and series keep source order")
        library.setSort(.title, for: series)
        XCTAssertEqual(series.pageSort, .manual)
    }
}
