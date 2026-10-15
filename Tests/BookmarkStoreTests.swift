import XCTest
import UIKit
@testable import MeridianReader

/// Favorites are independent page flags (`LibraryStore+Favorites`): toggled from ⋯, deduped by
/// canonical URL, renamed, removed, with a tile-sized icon when one can be found.
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

    func testTitleFallsBackToHostAndRenameRemoveWithoutMovingPages() throws {
        let a = try XCTUnwrap(library.addFavorite(url: URL(string: "https://a.example/")!, title: nil, artwork: nil))
        let b = try XCTUnwrap(library.addFavorite(url: URL(string: "https://b.example/")!, title: "B", artwork: nil))
        let c = try XCTUnwrap(library.addFavorite(url: URL(string: "https://c.example/")!, title: "C", artwork: nil))
        XCTAssertEqual(a.title, "a.example")
        try library.renameFavorite(a, to: "  Alpha ")
        try library.renameFavorite(b, to: "   ") // ignored
        XCTAssertEqual(Set(library.favoritePages().map(\.title)), ["Alpha", "B", "C"])
        XCTAssertNil(a.folder)
        XCTAssertNil(b.folder)
        XCTAssertNil(c.folder)
        try library.removeFavorite(b)
        XCTAssertEqual(Set(library.favoritePages().map(\.title)), ["Alpha", "C"])
        XCTAssertNil(library.favorite(for: URL(string: "http://localhost/")), "non-matching")
        XCTAssertNil(library.favorite(for: URL(string: "about:blank")))
    }

    /// One page per address: favoriting a saved page leaves it in its current location.
    func testFavoritingASavedPageDoesNotMoveIt() throws {
        let saved = try library.save(env.article("https://example.com/saved"))
        let favorite = try library.addFavorite(url: URL(string: "https://example.com/saved")!, title: "Other title", artwork: nil)
        XCTAssertIdentical(favorite, saved)
        XCTAssertTrue(saved.isFavorite)
        XCTAssertTrue(saved.isSavedToLibrary)
        XCTAssertTrue(try env.context.fetch(LibraryQueries.loosePages(sort: .newest)).contains { $0.key == saved.key })

        try library.removeFavorite(saved)
        XCTAssertNil(saved.folder)
        XCTAssertTrue(saved.isSavedToLibrary)
        XCTAssertEqual(try env.context.fetch(LibraryQueries.loosePages(sort: .newest)).map(\.title), [saved.title])
    }

    /// ☆ on a page played without saving puts it in the Library with its played text: it is in
    /// the Favorites tab (☆ shows filled), and the 7-day prune of unsaved pages keeps it.
    /// Unstarring it later leaves it in the Library.
    func testFavoritingAPagePlayedButNotSavedPutsItInTheLibraryAndFavorites() throws {
        let url = URL(string: "https://example.com/played")!
        let played = library.recordPlayback(env.article(url.absoluteString))
        let other = library.recordPlayback(env.article("https://example.com/other"))
        XCTAssertNil(played.addedAt)
        try library.addFavorite(url: url, title: nil, artwork: nil)
        XCTAssertTrue(played.isSaved, "favoriting does not replace its played text")
        XCTAssertNotNil(played.addedAt, "in the Library")
        XCTAssertNil(played.folder, "where it was: loose")
        XCTAssertIdentical(library.favorite(for: url), played, "☆ filled")
        XCTAssertEqual(try env.context.fetch(LibraryQueries.favoritePages).map(\.key), [played.key], "the Favorites tab")
        XCTAssertEqual(try env.context.fetch(LibraryQueries.loosePages(sort: .newest)).map(\.key), [played.key])
        XCTAssertFalse(try env.context.fetch(LibraryQueries.playedNotSaved).contains { $0 === played }, "no longer Not saved")

        env.now += 30 * 24 * 3600
        _ = library.recordPlayback(env.article("https://example.com/later")) // the last played is always kept
        library.pruneUnsaved()
        XCTAssertNotNil(library.page(url: url), "a favorite is never pruned")
        XCTAssertNil(library.page(url: URL(string: "https://example.com/other")!), "an unsaved page is")
        _ = other

        try library.removeFavorite(played)
        XCTAssertNil(library.favorite(for: url))
        XCTAssertTrue(played.isInLibrary, "unstarring keeps it")
    }

    /// ☆ on a page that is nowhere yet makes a link in the Library; unstarring keeps the link.
    func testUnstarringALinkStarCreatedKeepsIt() throws {
        let url = URL(string: "https://example.com/new")!
        let link = try library.addFavorite(url: url, title: "New", artwork: nil)
        XCTAssertTrue(link.isLink)
        XCTAssertTrue(link.isInLibrary)
        try library.removeFavorite(link)
        XCTAssertFalse(link.isFavorite)
        XCTAssertIdentical(library.page(url: url), link, "still there")
        XCTAssertTrue(link.isInLibrary)
    }

    /// Remove from Library takes a favorite out of Favorites too: no star is left on a page the
    /// Favorites tab can't show.
    func testRemovingAFavoriteFromTheLibraryClearsItsStar() throws {
        let url = URL(string: "https://example.com/saved")!
        let saved = try library.save(env.article(url.absoluteString))
        try library.addFavorite(url: url, title: nil, artwork: nil)
        XCTAssertNotNil(library.favorite(for: url))
        try library.remove([saved])
        XCTAssertFalse(saved.isInLibrary)
        XCTAssertFalse(saved.isFavorite)
        XCTAssertNil(library.favorite(for: url))
        XCTAssertTrue(library.favoritePages().isEmpty)
    }
}
