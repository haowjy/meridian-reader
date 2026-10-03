import XCTest
import UIKit
@testable import Reader

@MainActor
final class BookmarkStoreTests: XCTestCase {
    private var file: URL!

    override func setUp() async throws {
        file = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookmarkStoreTests-\(UUID().uuidString)/bookmarks.json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }

    private func png(side: CGFloat) -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: {
            let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f
        }()).pngData { ctx in UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: side, height: side)) }
    }

    func testToggleAddsWithABetterIconThenRemoves() async {
        let store = BookmarkStore(fileURL: file)
        let url = URL(string: "https://example.com/story")!
        let tile = png(side: 64)
        await store.toggle(url: url, title: "Story", faviconData: png(side: 16)) { tile }
        XCTAssertEqual(store.bookmark(for: url)?.faviconData, tile, "a 16 px icon is upgraded to a tile-sized one")

        await store.toggle(url: url, title: "Story", faviconData: nil) { XCTFail("not asked when removing"); return nil }
        XCTAssertNil(store.bookmark(for: url))

        await store.toggle(url: url, title: "Story", faviconData: tile) { XCTFail("already tile-sized"); return nil }
        XCTAssertEqual(store.bookmark(for: url)?.faviconData, tile)
    }

    func testOfferFaviconNeverReplacesAUsableIconWithASmallerOne() {
        let store = BookmarkStore(fileURL: file)
        let tile = png(side: 64)
        let b = store.add(url: URL(string: "https://example.com/")!, title: nil, faviconData: tile)
        store.offerFavicon(png(side: 16), for: b.id)
        XCTAssertEqual(store.bookmarks.first?.faviconData, tile)
    }

    func testAddDedupesByCanonicalURLAndPersists() {
        let store = BookmarkStore(fileURL: file)
        let a = store.add(url: URL(string: "https://www.example.com/stories/1")!, title: " Story ", faviconData: nil)
        let again = store.add(url: URL(string: "https://www.example.com/stories/1?utm_source=x#top")!,
                              title: "Other", faviconData: nil)
        XCTAssertEqual(a.id, again.id, "same page → one bookmark")
        XCTAssertEqual(store.bookmarks.count, 1)
        XCTAssertEqual(a.title, "Story")
        XCTAssertNotNil(store.bookmark(for: URL(string: "https://www.example.com/stories/1?utm_medium=y")))

        let reloaded = BookmarkStore(fileURL: file)
        XCTAssertEqual(reloaded.bookmarks, store.bookmarks, "persists to its own file")
    }

    func testTitleFallsBackToHostAndRenameMoveRemove() {
        let store = BookmarkStore(fileURL: file)
        let a = store.add(url: URL(string: "https://a.example/")!, title: nil, faviconData: nil)
        let b = store.add(url: URL(string: "https://b.example/")!, title: "B", faviconData: nil)
        let c = store.add(url: URL(string: "https://c.example/")!, title: "C", faviconData: nil)
        XCTAssertEqual(a.title, "a.example")
        store.rename(id: a.id, to: "  Alpha ")
        store.rename(id: b.id, to: "   ") // ignored
        XCTAssertEqual(store.bookmarks.map(\.title), ["Alpha", "B", "C"])
        store.move(fromOffsets: [2], toOffset: 0)
        XCTAssertEqual(store.bookmarks.map(\.id), [c.id, a.id, b.id])
        store.move(fromOffsets: [0], toOffset: 3)
        XCTAssertEqual(store.bookmarks.map(\.id), [a.id, b.id, c.id])
        store.remove(id: b.id)
        XCTAssertEqual(store.bookmarks.map(\.id), [a.id, c.id])
        XCTAssertNil(store.bookmark(for: URL(string: "http://localhost/")) , "non-matching")
        XCTAssertNil(store.bookmark(for: URL(string: "about:blank")))
    }
}
