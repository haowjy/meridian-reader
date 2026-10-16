import SwiftData
import SwiftUI
import XCTest
@testable import MeridianReader

/// "This page" is answered one way: the page for its address first, then its key. 🔖's look (the
/// live lookup, `PageLookup`), the store's `savedPage` and what tapping 🔖 does all follow it,
/// even while two pages hold one address (before the launch dedupe merges them).
@MainActor
final class PageActionsTests: XCTestCase {
    private var env: LibraryTestEnvironment!
    private var library: LibraryStore { env.library }
    private var shell: ShellState!
    private var downloads: DownloadCenter!
    private let address = "https://example.com/story"

    override func setUp() async throws {
        env = try LibraryTestEnvironment()
        shell = ShellState()
        downloads = DownloadCenter(library: library, tts: env.tts,
                                   store: DownloadListStore(url: env.dir.appending(path: "Downloads.json")),
                                   fetch: { _ in throw URLError(.notConnectedToInternet) }, save: { _ in UUID() })
    }

    override func tearDown() async throws { env.cleanUp() }

    /// The article as the Reader holds it: the address's key (the newer page's).
    private var article: ReaderArticle { env.article(address, title: "Story") }
    private var canonical: String { ArticleIdentity.canonicalURLString(from: address) }

    /// An older page for the address under a random key (a save from before identity v2), and a
    /// newer one under the address's key; `savedOlder` says which of the two is saved.
    private func twoPages(savedOlder: Bool) throws -> (older: Page, newer: Page) {
        let older = Page(key: UUID(), title: "Story", byline: "example.com", urlString: address,
                         contentState: savedOlder ? .saved : .link, addedAt: env.now - 100, sortKey: 0)
        let newer = Page(key: article.id, title: "Story", byline: "example.com", urlString: address,
                         contentState: savedOlder ? .link : .saved, addedAt: env.now, sortKey: 1)
        env.context.insert(older)
        env.context.insert(newer)
        try env.context.save()
        return (older, newer)
    }

    /// What 🔖 shows: the lookup's two one-row queries, as `PageLookup` runs them.
    private func shownPage() throws -> Page? {
        PageLookup<EmptyView>.page(byAddress: try env.context.fetch(PageLookup<EmptyView>.byAddress(canonical)).first,
                                   byKey: try env.context.fetch(LibraryQueries.page(key: article.id)).first)
    }

    private func actions() throws -> PageActions {
        PageActions(article: article, page: try shownPage(), library: library, shell: shell, speech: env.speech.speech,
                    downloads: downloads)
    }

    func testTheLookupAndTheStoreFindTheSamePage() throws {
        let (older, _) = try twoPages(savedOlder: false)
        XCTAssertIdentical(try shownPage(), older, "the address first")
        XCTAssertIdentical(library.page(key: article.id, canonicalURL: canonical), older)
        XCTAssertNil(library.savedPage(key: article.id, canonicalURL: canonical))
    }

    /// The page for the address isn't saved (the other one is): 🔖 is empty, and a tap saves it.
    func testAnUnsavedPageForTheAddressShowsUnsavedAndATapSavesIt() throws {
        let (older, _) = try twoPages(savedOlder: false)
        XCTAssertFalse(try actions().isSaved)

        try actions().toggleSaved()
        XCTAssertTrue(older.isSavedToLibrary, "the page 🔖 showed was saved")
        XCTAssertTrue(try actions().isSaved, "and 🔖 shows it")
        XCTAssertNil(shell.toast, "nothing went wrong")
    }

    /// The page for the address is saved (the other one isn't): 🔖 is filled, and a tap removes it.
    func testASavedPageForTheAddressShowsSavedAndATapRemovesIt() throws {
        let (older, _) = try twoPages(savedOlder: true)
        XCTAssertTrue(try actions().isSaved)

        try actions().toggleSaved()
        XCTAssertFalse(older.isSavedToLibrary, "the page 🔖 showed was removed")
        XCTAssertFalse(try actions().isSaved, "and 🔖 shows it")
    }

    /// ☆ follows the Library's gate: a chapter with no web address in the Library can be starred.
    func testAChapterInTheLibraryCanBeStarred() throws {
        let chapter = Page(key: UUID(), title: "Chapter 1", byline: "An Author", urlString: nil, contentState: .saved,
                           addedAt: env.now, sortKey: 0)
        env.context.insert(chapter)
        try env.context.save()
        let reading = ReaderArticle(page: chapter)
        let actions = PageActions(article: reading, page: chapter, library: library, shell: shell, speech: env.speech.speech,
                                  downloads: downloads)
        XCTAssertTrue(actions.canFavorite)
        XCTAssertTrue(actions.readerMenu().canFavorite)

        actions.toggleFavorite()
        XCTAssertTrue(LibraryStore.isFavorite(chapter))
        XCTAssertEqual(shell.toast?.message, "Added to Favorites")
    }
}
