import XCTest
import UIKit
@testable import Reader

/// Bookmarks are Favorites' pages (`LibraryStore+Favorites`): toggled from ⋯, deduped by
/// canonical URL, renamed, reordered, removed, with a tile-sized icon when one can be found.
@MainActor
final class BookmarkStoreTests: XCTestCase {
    private var env: LibraryTestEnvironment!
    private var library: LibraryStore { env.library }

    override func setUp() async throws { env = try LibraryTestEnvironment() }
    override func tearDown() async throws { env.cleanUp() }

    private func png(side: CGFloat) -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: {
            let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f
        }()).pngData { ctx in UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: side, height: side)) }
    }

    func testToggleAddsWithABetterIconThenRemoves() async throws {
        let url = URL(string: "https://example.com/story")!
        let tile = png(side: 64)
        try await library.toggleFavorite(url: url, title: "Story", artwork: png(side: 16)) { tile }
        XCTAssertEqual(library.favorite(for: url)?.artworkData, tile, "a 16 px icon is upgraded to a tile-sized one")

        try await library.toggleFavorite(url: url, title: "Story", artwork: nil) { XCTFail("not asked when removing"); return nil }
        XCTAssertNil(library.favorite(for: url))

        try await library.toggleFavorite(url: url, title: "Story", artwork: tile) { XCTFail("already tile-sized"); return nil }
        XCTAssertEqual(library.favorite(for: url)?.artworkData, tile)
    }

    func testOfferArtworkNeverReplacesAUsableIconWithASmallerOne() throws {
        let tile = png(side: 64)
        let page = try XCTUnwrap(library.addFavorite(url: URL(string: "https://example.com/")!, title: nil, artwork: tile))
        library.offerArtwork(png(side: 16), for: page)
        XCTAssertEqual(library.favoritePages().first?.artworkData, tile)
    }

    func testAddDedupesByCanonicalURLAndPersists() throws {
        let a = try XCTUnwrap(library.addFavorite(url: URL(string: "https://www.example.com/stories/1")!, title: " Story ", artwork: nil))
        let again = try library.addFavorite(url: URL(string: "https://www.example.com/stories/1?utm_source=x#top")!,
                                        title: "Other", artwork: nil)
        XCTAssertIdentical(a, again, "same page → one favorite")
        XCTAssertEqual(library.favoritePages().count, 1)
        XCTAssertEqual(a.title, "Story")
        XCTAssertNotNil(library.favorite(for: URL(string: "https://www.example.com/stories/1?utm_medium=y")))

        let relaunched = env.makeLibrary()
        XCTAssertEqual(relaunched.favoritePages().map(\.title), ["Story"], "kept in the library store")
    }

    func testTitleFallsBackToHostAndRenameMoveRemove() throws {
        let a = try XCTUnwrap(library.addFavorite(url: URL(string: "https://a.example/")!, title: nil, artwork: nil))
        let b = try XCTUnwrap(library.addFavorite(url: URL(string: "https://b.example/")!, title: "B", artwork: nil))
        let c = try XCTUnwrap(library.addFavorite(url: URL(string: "https://c.example/")!, title: "C", artwork: nil))
        XCTAssertEqual(a.title, "a.example")
        try library.renameFavorite(a, to: "  Alpha ")
        try library.renameFavorite(b, to: "   ") // ignored
        XCTAssertEqual(library.favoritePages().map(\.title), ["Alpha", "B", "C"])
        try library.reorder([c], in: library.favorites(), before: a)
        XCTAssertEqual(library.favoritePages().map(\.title), ["C", "Alpha", "B"])
        try library.reorder([c], in: library.favorites(), before: nil)
        XCTAssertEqual(library.favoritePages().map(\.title), ["Alpha", "B", "C"])
        try library.removeFavorite(b)
        XCTAssertEqual(library.favoritePages().map(\.title), ["Alpha", "C"])
        XCTAssertNil(library.favorite(for: URL(string: "http://localhost/")), "non-matching")
        XCTAssertNil(library.favorite(for: URL(string: "about:blank")))
    }

    /// One page per address: bookmarking a saved page files it in Favorites; removing the
    /// bookmark puts it back with the pages in no folder, still saved.
    func testBookmarkingASavedPageFilesItInFavorites() throws {
        let saved = try library.save(env.article("https://example.com/saved"))
        let favorite = try library.addFavorite(url: URL(string: "https://example.com/saved")!, title: "Other title", artwork: nil)
        XCTAssertIdentical(favorite, saved)
        XCTAssertEqual(saved.folder?.kind, .favorites)
        XCTAssertTrue(saved.isSavedToLibrary)
        XCTAssertTrue(try env.context.fetch(LibraryQueries.loosePages(sort: .newest)).isEmpty, "not in the Saved list")

        try library.removeFavorite(saved)
        XCTAssertNil(saved.folder)
        XCTAssertTrue(saved.isSavedToLibrary)
        XCTAssertEqual(try env.context.fetch(LibraryQueries.loosePages(sort: .newest)).map(\.title), [saved.title])
    }

    func testBookmarkingAPagePlayedButNotSavedMakesItALink() throws {
        let played = library.recordPlayback(env.article("https://example.com/played"))
        XCTAssertNil(played.addedAt)
        try library.addFavorite(url: URL(string: "https://example.com/played")!, title: nil, artwork: nil)
        XCTAssertTrue(played.isLink, "Favorites doesn't save")
        XCTAssertNotNil(played.addedAt)
        XCTAssertEqual(played.folder?.kind, .favorites)
    }
}
