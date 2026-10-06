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
        try library.addLink(url: url, title: "Story", artwork: nil, in: library.favorites())
        library.recordPlayback(env.article("https://example.com/story?utm_source=x"))
        try library.save(env.article("https://EXAMPLE.com/story#comments"))
        XCTAssertIdentical(try library.addFavorite(url: URL(string: "https://example.com/story/")!, title: nil, artwork: nil),
                           library.page(url: url))
        XCTAssertEqual(env.pages().count, 1)
        XCTAssertEqual(library.page(url: url)?.key, ArticleIdentity.articleKey(url: url))
    }

    func testLegacyKeyedPageIsFoundByAddressAndKeepsItsKey() throws {
        let legacyKey = UUID()
        let page = try library.save(env.article("https://example.com/old", key: legacyKey))
        XCTAssertEqual(page.key, legacyKey)
        let reopened = library.readerArticle(url: URL(string: "https://example.com/old?fbclid=1")!,
                                             extracted: env.article("https://example.com/old").extracted)
        XCTAssertEqual(reopened.id, legacyKey, "the browser reuses the page's key, so its audio")
    }

    func testSaveOnALinkTurnsItSavedInPlace() throws {
        let favorites = library.favorites()
        let link = try library.addLink(url: URL(string: "https://example.com/a")!, title: "A", artwork: nil, in: favorites)
        XCTAssertTrue(link.isLink)
        XCTAssertFalse(link.hasText)
        let saved = try library.save(env.article("https://example.com/a", title: "Article A"))
        XCTAssertIdentical(saved, link)
        XCTAssertTrue(saved.isSavedToLibrary)
        XCTAssertIdentical(saved.folder, favorites, "it keeps its folder")
        XCTAssertEqual(saved.cachedListenParagraphs?.count, 2)
    }

    func testPlayingALinkKeepsItALinkWithATextCachePrunedAfter7Days() throws {
        let link = try library.addLink(url: URL(string: "https://example.com/a")!, title: "A", artwork: nil, in: library.favorites())
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

    func testAddLinkOnAnExistingPageReturnsIt() throws {
        let saved = try library.save(env.article("https://example.com/a"))
        let link = try library.addLink(url: URL(string: "https://example.com/a?utm_campaign=z")!, title: "Other", artwork: nil, in: nil)
        XCTAssertIdentical(link, saved)
        XCTAssertTrue(link.isSaved, "unchanged")
    }

    func testAPageNeverLeavesABookOrSeries() throws {
        let book = Folder(name: "Book", kind: .book)
        env.context.insert(book)
        let chapter = try library.addLink(url: URL(string: "https://example.com/ch1")!, title: "Ch 1", artwork: nil, in: book)
        let other = try library.makeFolder(name: "Elsewhere", in: nil)

        XCTAssertThrowsError(try library.move([.page(chapter)], to: other)) {
            XCTAssertEqual($0 as? LibraryTreeError, .leavesFixedFolder)
        }
        try library.save(env.article("https://example.com/ch1"), placement: .folder(other))
        XCTAssertIdentical(chapter.folder, book, "save into another folder keeps it in the book")
        XCTAssertNil(try library.addFavorite(url: URL(string: "https://example.com/ch1")!, title: nil, artwork: nil))
        XCTAssertIdentical(chapter.folder, book)
        try library.remove([chapter])
        XCTAssertIdentical(chapter.folder, book, "remove isn't for chapters")
        XCTAssertNotNil(chapter.addedAt)
    }

    /// A series in Favorites makes its chapters favorites, but ☆ on one never takes it out of
    /// the series (it offers to move the series out instead), whether it is saved or a link, and
    /// the series' place stays on it.
    func testRemovingAFavoriteChapterNeverDetachesItFromItsSeries() async throws {
        let series = Folder(name: "Serial", kind: .series)
        env.context.insert(series)
        series.parent = library.favorites()
        let savedURL = URL(string: "https://example.com/serial/1")!
        let linkURL = URL(string: "https://example.com/serial/2")!
        let saved = try library.save(env.article(savedURL.absoluteString, title: "Ch 1"))
        saved.setFolder(series)
        let link = try library.addLink(url: linkURL, title: "Ch 2", artwork: nil, in: series)
        series.currentPageKey = saved.key
        XCTAssertTrue(LibraryStore.isFavorite(saved), "in Favorites through its series")

        for (url, chapter) in [(savedURL, saved), (linkURL, link)] {
            guard case .moveBookOut(let source) = library.favoriteRequest(for: url) else {
                return XCTFail("☆ on \(chapter.title) offers to move the series out")
            }
            XCTAssertIdentical(source, series)
            try library.removeFavorite(chapter)
            try await library.toggleFavorite(url: url, title: nil, artwork: nil) { nil }
            XCTAssertIdentical(chapter.folder, series, "\(chapter.title) stays in the series")
            XCTAssertFalse(chapter.isDeleted)
        }
        XCTAssertTrue(saved.isSaved)
        XCTAssertEqual(series.currentPageKey, saved.key, "the series' place is still its chapter")

        try library.move([.folder(series)], to: nil)
        guard case .moveBook = library.favoriteRequest(for: savedURL) else { return XCTFail("out of Favorites: move it in") }
    }

    /// *Library (no folder)* in the Move tree files the page in no folder, out of Favorites;
    /// an ordinary save keeps it where it is; a chapter stays in its book either way.
    func testPickingNoFolderTakesALinkOutOfFavoritesAndAnOrdinarySaveKeepsIt() throws {
        let favorites = library.favorites()
        try library.addLink(url: URL(string: "https://example.com/kept")!, title: "Kept", artwork: nil, in: favorites)
        let kept = try library.save(env.article("https://example.com/kept"))
        XCTAssertIdentical(kept.folder, favorites, "an ordinary save keeps its folder")

        try library.addLink(url: URL(string: "https://example.com/out")!, title: "Out", artwork: nil, in: favorites)
        let out = try library.save(env.article("https://example.com/out"), placement: .folder(nil))
        XCTAssertNil(out.folder, "picked: no folder")
        XCTAssertTrue(out.isSavedToLibrary)
        XCTAssertFalse(LibraryStore.isFavorite(out))

        let book = Folder(name: "Book", kind: .book)
        env.context.insert(book)
        let chapter = try library.addLink(url: URL(string: "https://example.com/ch")!, title: "Ch", artwork: nil, in: book)
        try library.save(env.article("https://example.com/ch"), placement: .folder(nil))
        XCTAssertIdentical(chapter.folder, book)
    }

    func testDeletingABooksPlaceRepointsItToTheChapterBefore() throws {
        let book = Folder(name: "Book", kind: .book)
        env.context.insert(book)
        let chapters = try (1...3).map {
            try library.addLink(url: URL(string: "https://example.com/ch\($0)")!, title: "Ch \($0)", artwork: nil, in: book)
        }
        book.currentPageKey = chapters[1].key
        library.delete(chapters[1])
        XCTAssertEqual(book.currentPageKey, chapters[0].key)
        library.delete(chapters[0])
        XCTAssertNil(book.currentPageKey, "none before the first")
    }

    func testDeletingThePlayingPageStopsPlaybackFirstAndRemovesItsAudio() throws {
        let page = try library.save(env.article("https://example.com/a"))
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
        let saved = try library.save(article)
        XCTAssertIdentical(saved, page)
        XCTAssertEqual(saved.addedAt, env.now)
        XCTAssertTrue(saved.isSavedToLibrary)
        XCTAssertEqual(try env.context.fetch(LibraryQueries.loosePages(sort: .newest)).count, 1)
    }

    func testRemoveKeepsAudioEphemeralAndRemovesALinkOutright() throws {
        let page = try library.save(env.article("https://example.com/a"))
        let key = try XCTUnwrap(page.key)
        try env.storeAudio(key, paragraphs: page.cachedListenParagraphs ?? [])
        try library.remove([page])
        XCTAssertNil(page.addedAt)
        XCTAssertNil(page.folder)
        XCTAssertTrue(env.cache.hasCache(for: key), "the audio stays…")
        XCTAssertEqual(env.cache.loadMeta(for: key)?.kind, .ephemeral, "…on the ephemeral TTL")
        XCTAssertNotNil(library.page(key: key))

        let link = try library.addLink(url: URL(string: "https://example.com/link")!, title: "L", artwork: nil, in: library.favorites())
        try library.remove([link])
        XCTAssertNil(library.page(url: URL(string: "https://example.com/link")!), "a link is deleted")
    }

    /// A link that was played holds that play's text: removing it keeps it as a page played
    /// without saving (out of the Library and Favorites, still in Continue), pruned 7 days after
    /// its last play like any other.
    func testRemovingAPlayedLinkKeepsItAsAPlayedPageUntilThePrune() throws {
        let url = URL(string: "https://example.com/played-link")!
        let link = try library.addLink(url: url, title: "Played link", artwork: nil, in: library.favorites())
        library.recordPlayback(env.article(url.absoluteString))
        let key = try XCTUnwrap(link.key)
        try env.storeAudio(key, paragraphs: link.cachedListenParagraphs ?? [])
        XCTAssertTrue(link.isLink && link.hasText)

        try library.remove([link])
        let page = try XCTUnwrap(library.page(url: url), "kept: it holds the text of a play")
        XCTAssertIdentical(page, link)
        XCTAssertFalse(page.isInLibrary)
        XCTAssertNil(page.folder, "out of Favorites")
        XCTAssertTrue(library.favoritePages().isEmpty)
        XCTAssertTrue(page.hasText)
        XCTAssertEqual(page.cachedListenParagraphs?.count, 2)
        XCTAssertNotNil(page.lastPlayedAt)
        XCTAssertEqual(env.cache.loadMeta(for: key)?.kind, .ephemeral, "its audio is on the ephemeral TTL")
        let recent = try env.context.fetch(LibraryQueries.recentlyPlayed)
        XCTAssertEqual(LibraryQueries.continuePages(recent: recent, undated: []).map(\.key), [key], "still in Continue")

        // Another page played since, so this one isn't the last played.
        env.now += 1
        library.recordPlayback(env.article("https://example.com/other"))
        env.now += 6 * day
        XCTAssertEqual(library.pruneUnsaved().deletedPages, 0)
        XCTAssertNotNil(library.page(url: url), "kept for 7 days")
        env.now += 2 * day
        library.recordPlayback(env.article("https://example.com/latest"))
        XCTAssertEqual(library.pruneUnsaved().deletedPages, 2, "it and the other page are pruned")
        XCTAssertNil(library.page(url: url))
    }

    func testUnsaveKeepsAFavoriteAsALinkAndRemovesALoosePage() throws {
        let favorite = try library.save(env.article("https://example.com/fav"), placement: .folder(library.favorites()))
        try library.unsave(favorite)
        XCTAssertTrue(favorite.isLink)
        XCTAssertEqual(favorite.folder?.kind, .favorites, "still a favorite")
        XCTAssertFalse(favorite.hasText, "never played: no cache to keep")

        let loose = try library.save(env.article("https://example.com/loose"))
        try library.unsave(loose)
        XCTAssertNil(loose.addedAt)
        XCTAssertFalse(loose.isSavedToLibrary)
    }

    func testDeleteRemovesAudio() throws {
        let page = try library.save(env.article("https://example.com/a"))
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
        let saved = try library.save(env.article("https://example.com/saved"))
        env.now += 30 * day

        let report = library.pruneUnsaved()
        XCTAssertEqual(report.deletedPages, 1)
        XCTAssertNil(library.page(url: URL(string: "https://example.com/older")!))
        XCTAssertNotNil(library.page(url: URL(string: "https://example.com/last")!), "the last-played page is kept")
        XCTAssertNotNil(library.page(url: URL(string: "https://example.com/saved")!), "saved pages are never pruned")
        _ = (older, last, saved)
    }

    func testFinishedAndPositionAreRecordedAndAReplayClearsFinished() throws {
        let page = try library.save(env.article("https://example.com/a"))
        library.recordPosition(page, paragraph: 1, utf16Offset: 30)
        XCTAssertEqual(page.positionParagraph, 1)
        XCTAssertEqual(page.positionUTF16, 30)
        library.recordFinished(page)
        XCTAssertNotNil(page.finishedAt)
        library.recordPlaybackStarted(page)
        XCTAssertNil(page.finishedAt, "starting it again puts it back in progress")
    }
}
