import SwiftData
import XCTest
@testable import Reader

/// Pages through `LibraryStore`: one page per address in every state, save / link / play /
/// remove / delete, and what each does to the audio and to playback.
@MainActor
final class LibraryStoreTests: XCTestCase {
    private var env: LibraryTestEnvironment!
    private var library: LibraryStore { env.library }

    override func setUp() async throws { env = try LibraryTestEnvironment() }
    override func tearDown() async throws { env.cleanUp() }

    private let day: TimeInterval = 24 * 3600

    func testOnePagePerCanonicalURLWhateverItsState() throws {
        let url = URL(string: "https://example.com/story")!
        library.addLink(url: url, title: "Story", artwork: nil, in: library.favorites())
        library.recordPlayback(env.article("https://example.com/story?utm_source=x"))
        library.save(env.article("https://EXAMPLE.com/story#comments"))
        XCTAssertIdentical(library.addFavorite(url: URL(string: "https://example.com/story/")!, title: nil, artwork: nil),
                           library.page(url: url))
        XCTAssertEqual(env.pages().count, 1)
        XCTAssertEqual(library.page(url: url)?.key, ArticleIdentity.articleKey(url: url))
    }

    func testLegacyKeyedPageIsFoundByAddressAndKeepsItsKey() {
        let legacyKey = UUID()
        let page = library.save(env.article("https://example.com/old", key: legacyKey))
        XCTAssertEqual(page.key, legacyKey)
        let reopened = library.readerArticle(url: URL(string: "https://example.com/old?fbclid=1")!,
                                             extracted: env.article("https://example.com/old").extracted)
        XCTAssertEqual(reopened.id, legacyKey, "the browser reuses the page's key, so its audio")
    }

    func testSaveOnALinkTurnsItSavedInPlace() throws {
        let favorites = library.favorites()
        let link = library.addLink(url: URL(string: "https://example.com/a")!, title: "A", artwork: nil, in: favorites)
        XCTAssertTrue(link.isLink)
        XCTAssertFalse(link.hasText)
        let saved = library.save(env.article("https://example.com/a", title: "Article A"))
        XCTAssertIdentical(saved, link)
        XCTAssertTrue(saved.isSavedToLibrary)
        XCTAssertIdentical(saved.folder, favorites, "it keeps its folder")
        XCTAssertEqual(saved.cachedListenParagraphs?.count, 2)
    }

    func testPlayingALinkKeepsItALinkWithATextCachePrunedAfter7Days() throws {
        let link = library.addLink(url: URL(string: "https://example.com/a")!, title: "A", artwork: nil, in: library.favorites())
        let played = library.recordPlayback(env.article("https://example.com/a"))
        XCTAssertIdentical(played, link)
        XCTAssertTrue(link.isLink, "listening doesn't save")
        XCTAssertTrue(link.hasText, "the text is kept as a cache")
        XCTAssertEqual(link.paragraphCount, 2)

        // Something else played since, so the link isn't the last-played page.
        env.now += 1
        library.recordPlayback(env.article("https://example.com/other"))
        env.now += 6 * day
        XCTAssertEqual(library.pruneUnsaved(), LibraryStore.PruneReport(), "kept for 7 days")
        env.now += 2 * day
        library.recordPlayback(env.article("https://example.com/latest"))
        let report = library.pruneUnsaved()
        XCTAssertEqual(report.clearedLinkCaches, 1)
        XCTAssertFalse(link.hasText, "the cache is cleared")
        XCTAssertNotNil(library.page(url: URL(string: "https://example.com/a")!), "the link stays")
    }

    func testAddLinkOnAnExistingPageReturnsIt() {
        let saved = library.save(env.article("https://example.com/a"))
        let link = library.addLink(url: URL(string: "https://example.com/a?utm_campaign=z")!, title: "Other", artwork: nil, in: nil)
        XCTAssertIdentical(link, saved)
        XCTAssertTrue(link.isSaved, "unchanged")
    }

    func testAPageNeverLeavesABookOrSeries() throws {
        let book = Folder(name: "Book", kind: .book)
        env.context.insert(book)
        let chapter = library.addLink(url: URL(string: "https://example.com/ch1")!, title: "Ch 1", artwork: nil, in: book)
        let other = try library.makeFolder(name: "Elsewhere", in: nil)

        XCTAssertThrowsError(try library.move([.page(chapter)], to: other)) {
            XCTAssertEqual($0 as? LibraryTreeError, .leavesFixedFolder)
        }
        library.save(env.article("https://example.com/ch1"), in: other)
        XCTAssertIdentical(chapter.folder, book, "save into another folder keeps it in the book")
        XCTAssertNil(library.addFavorite(url: URL(string: "https://example.com/ch1")!, title: nil, artwork: nil))
        XCTAssertIdentical(chapter.folder, book)
        library.remove(chapter)
        XCTAssertIdentical(chapter.folder, book, "remove isn't for chapters")
        XCTAssertNotNil(chapter.addedAt)
    }

    func testDeletingABooksPlaceRepointsItToTheChapterBefore() throws {
        let book = Folder(name: "Book", kind: .book)
        env.context.insert(book)
        let chapters = (1...3).map {
            library.addLink(url: URL(string: "https://example.com/ch\($0)")!, title: "Ch \($0)", artwork: nil, in: book)
        }
        book.currentPageKey = chapters[1].key
        library.delete(chapters[1])
        XCTAssertEqual(book.currentPageKey, chapters[0].key)
        library.delete(chapters[0])
        XCTAssertNil(book.currentPageKey, "none before the first")
    }

    func testDeletingThePlayingPageStopsPlaybackFirstAndRemovesItsAudio() throws {
        let page = library.save(env.article("https://example.com/a"))
        let key = try XCTUnwrap(page.key)
        try env.storeAudio(key, paragraphs: page.cachedListenParagraphs ?? [])
        env.playingKey = key
        library.delete(page)
        XCTAssertEqual(env.stoppedKeys, [key])
        XCTAssertFalse(env.cache.hasCache(for: key))
        XCTAssertNil(library.page(key: key))
    }

    func testRecordPlaybackKeepsAPageNotInTheLibraryThenSaveSetsIt() throws {
        let article = env.article("https://example.com/played")
        let page = library.recordPlayback(article)
        XCTAssertNil(page.addedAt, "not in the Library")
        XCTAssertTrue(page.isSaved && page.hasText, "with its text, so it survives a relaunch")
        XCTAssertFalse(page.isSavedToLibrary)
        XCTAssertEqual(page.lastPlayedAt, env.now)
        XCTAssertTrue(try env.context.fetch(LibraryQueries.inLibrary).isEmpty)
        XCTAssertTrue(try env.context.fetch(LibraryQueries.loosePages(sort: .newest)).isEmpty, "not in the Saved list")

        env.now += 60
        let saved = library.save(article)
        XCTAssertIdentical(saved, page)
        XCTAssertEqual(saved.addedAt, env.now)
        XCTAssertTrue(saved.isSavedToLibrary)
        XCTAssertEqual(try env.context.fetch(LibraryQueries.loosePages(sort: .newest)).count, 1)
    }

    func testRemoveKeepsAudioEphemeralAndRemovesALinkOutright() throws {
        let page = library.save(env.article("https://example.com/a"))
        let key = try XCTUnwrap(page.key)
        try env.storeAudio(key, paragraphs: page.cachedListenParagraphs ?? [])
        library.remove(page)
        XCTAssertNil(page.addedAt)
        XCTAssertNil(page.folder)
        XCTAssertTrue(env.cache.hasCache(for: key), "the audio stays…")
        XCTAssertEqual(env.cache.loadMeta(for: key)?.kind, .ephemeral, "…on the ephemeral TTL")
        XCTAssertNotNil(library.page(key: key))

        let link = library.addLink(url: URL(string: "https://example.com/link")!, title: "L", artwork: nil, in: library.favorites())
        library.remove(link)
        XCTAssertNil(library.page(url: URL(string: "https://example.com/link")!), "a link is deleted")
    }

    func testUnsaveKeepsAFavoriteAsALinkAndRemovesALoosePage() throws {
        let favorite = library.save(env.article("https://example.com/fav"), in: library.favorites())
        library.unsave(favorite)
        XCTAssertTrue(favorite.isLink)
        XCTAssertEqual(favorite.folder?.kind, .favorites, "still a favorite")
        XCTAssertFalse(favorite.hasText, "never played: no cache to keep")

        let loose = library.save(env.article("https://example.com/loose"))
        library.unsave(loose)
        XCTAssertNil(loose.addedAt)
        XCTAssertFalse(loose.isSavedToLibrary)
    }

    func testDeleteRemovesAudio() throws {
        let page = library.save(env.article("https://example.com/a"))
        let key = try XCTUnwrap(page.key)
        try env.storeAudio(key, paragraphs: page.cachedListenParagraphs ?? [])
        library.delete(page)
        XCTAssertFalse(env.cache.hasCache(for: key))
        XCTAssertTrue(env.stoppedKeys.isEmpty, "nothing was playing")
    }

    func testPruneDeletesOldUnsavedPagesButKeepsTheLastPlayed() throws {
        let older = library.recordPlayback(env.article("https://example.com/older"))
        env.now += 60
        let last = library.recordPlayback(env.article("https://example.com/last"))
        env.now += 60
        let saved = library.save(env.article("https://example.com/saved"))
        env.now += 30 * day

        let report = library.pruneUnsaved()
        XCTAssertEqual(report.deletedPages, 1)
        XCTAssertNil(library.page(url: URL(string: "https://example.com/older")!))
        XCTAssertNotNil(library.page(url: URL(string: "https://example.com/last")!), "the last-played page is kept")
        XCTAssertNotNil(library.page(url: URL(string: "https://example.com/saved")!), "saved pages are never pruned")
        _ = (older, last, saved)
    }

    func testFinishedAndPositionAreRecordedAndAReplayClearsFinished() throws {
        let page = library.save(env.article("https://example.com/a"))
        let key = try XCTUnwrap(page.key)
        library.recordPosition(key: key, paragraph: 1, utf16Offset: 30)
        XCTAssertEqual(page.positionParagraph, 1)
        XCTAssertEqual(page.positionUTF16, 30)
        library.recordFinished(key: key)
        XCTAssertNotNil(page.finishedAt)
        library.recordPlaybackStarted(key: key)
        XCTAssertNil(page.finishedAt, "starting it again puts it back in progress")
    }
}
