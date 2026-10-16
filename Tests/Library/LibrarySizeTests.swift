import SwiftData
import XCTest
@testable import MeridianReader

/// A long series on a file-backed store: its play order and its folder screen's page fetch stay
/// under 100 ms each (iOS 17 has no `#Index`, so these are table scans on `folderID`).
@MainActor
final class LibrarySizeTests: XCTestCase {
    static let chapterCount = 2_000
    static let budget: TimeInterval = 0.100

    private var env: LibraryTestEnvironment!

    override func setUp() async throws { env = try LibraryTestEnvironment(fileBacked: true) }

    override func tearDown() async throws { env.cleanUp() }

    private func time(_ label: String, _ work: () -> Int) -> TimeInterval {
        let start = Date()
        let count = work()
        let elapsed = Date().timeIntervalSince(start)
        print("[LibrarySize] \(label): \(count) pages in \(String(format: "%.1f", elapsed * 1000)) ms")
        return elapsed
    }

    func testTwoThousandChapterSeriesPlayOrderAndFolderFetchUnder100ms() throws {
        let seed = ModelContext(env.container)
        let series = Folder(name: "A Long Serial", kind: .series)
        seed.insert(series)
        // Chapters inserted out of order, so the sort is real work.
        for i in (0..<Self.chapterCount).shuffled() {
            let url = "https://example.com/serial/chapter-\(i)"
            let page = Page(key: ArticleIdentity.articleKey(canonicalURL: url), title: "Chapter \(i + 1)",
                            byline: "example.com", urlString: url, contentState: .link, addedAt: .now,
                            sortKey: Double(i))
            seed.insert(page)
            page.setFolder(series)
        }
        // Other pages in the store, outside the series.
        for i in 0..<500 {
            seed.insert(Page(key: UUID(), title: "Loose \(i)", byline: "example.com",
                             urlString: "https://example.com/loose/\(i)", contentState: .saved, addedAt: .now))
        }
        try seed.save()

        // The library's own context has fetched nothing yet: nothing cached in memory.
        let store: LibraryStore = env.library
        let folder = try XCTUnwrap(store.folder(id: series.id))

        var order: [Page] = []
        let cold = time("pages(in:) (cold)") { order = store.pages(in: folder); return order.count }
        XCTAssertEqual(order.count, Self.chapterCount)
        XCTAssertEqual(order.prefix(3).map(\.title), ["Chapter 1", "Chapter 2", "Chapter 3"])
        XCTAssertEqual(order.last?.title, "Chapter \(Self.chapterCount)")
        let warm = time("pages(in:) (warm)") { store.pages(in: folder).count }
        let fetch = time("folder page fetch") {
            (try? store.context.fetch(LibraryQueries.pages(inFolder: folder.id, sort: folder.pageSort)))?.count ?? 0
        }
        let titleSort = time("folder page fetch, title sort") {
            (try? store.context.fetch(LibraryQueries.pages(inFolder: folder.id, sort: .title)))?.count ?? 0
        }
        XCTAssertLessThan(cold, Self.budget, "pages(in:) cold")
        XCTAssertLessThan(warm, Self.budget, "pages(in:) warm")
        XCTAssertLessThan(fetch, Self.budget, "the folder's page fetch")
        XCTAssertLessThan(titleSort, Self.budget, "the folder's page fetch sorted by title")
    }
}
