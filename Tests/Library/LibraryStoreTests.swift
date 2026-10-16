import SwiftData
import XCTest
@testable import MeridianReader

/// Pages through `LibraryStore`: one page per address in every state, save / link / play /
/// remove / delete, and what each does to the audio and to playback.
@MainActor
final class LibraryStoreTests: XCTestCase {
    private var env: LibraryTestEnvironment!
    private var library: LibraryStore { env.library }

    override func setUp() async throws { env = try LibraryTestEnvironment() }
    override func tearDown() async throws { env.cleanUp() }

    private let day: TimeInterval = 24 * 3600

    func testFavoritesAreIndependentFlagsAndDoNotMovePagesOrFolders() throws {
        let folder = try library.makeFolder(name: "Finance", in: nil)
        let page = try library.save(env.article("https://example.com/rates"), placement: .folder(folder))

        _ = try library.addFavorite(url: page.url!, title: page.title, artwork: nil)
        try library.toggleFavorite(folder)

        XCTAssertTrue(page.isFavorite)
        XCTAssertTrue(folder.isFavorite)
        XCTAssertIdentical(page.folder, folder, "favoriting does not move the page")
        try library.removeFavorite(page)
        XCTAssertFalse(page.isFavorite)
        XCTAssertIdentical(page.folder, folder, "unfavoriting does not move the page")
    }

    func testLegacyFavoritesMigrationKeepsItemsAndRemovesPinnedFolder() throws {
        let legacy = env.legacyFavoritesFolder()
        let page = try library.addLink(url: URL(string: "https://example.com/saved-link")!, title: "Saved link",
                                       artwork: nil, in: legacy)
        let child = try library.makeFolder(name: "Serials", in: legacy)
        let nestedPage = try library.addLink(url: URL(string: "https://example.com/serial")!, title: "Serial",
                                             artwork: nil, in: child)
        let duplicateLegacy = Folder(name: "", kind: .favorites)
        library.context.insert(duplicateLegacy)
        let duplicatePage = try library.addLink(url: URL(string: "https://example.com/second-link")!, title: "Second link",
                                                artwork: nil, in: duplicateLegacy)

        library.migrateFavoritesFolder()

        XCTAssertNil(library.folder(id: legacy.id), "the special folder was removed")
        XCTAssertNil(library.folder(id: duplicateLegacy.id), "all legacy copies are removed")
        XCTAssertTrue(page.isFavorite)
        XCTAssertNil(page.folder, "direct pages move to the root")
        XCTAssertTrue(child.isFavorite)
        XCTAssertNil(child.parent, "existing subfolders remain available at root")
        XCTAssertTrue(nestedPage.isFavorite)
        XCTAssertIdentical(nestedPage.folder, child, "nested structure remains intact")
        XCTAssertTrue(duplicatePage.isFavorite)
        XCTAssertNil(duplicatePage.folder)
    }

    func testOnePagePerCanonicalURLWhateverItsState() throws {
        let url = URL(string: "https://example.com/story")!
        try library.addLink(url: url, title: "Story", artwork: nil, in: nil)
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

    /// A web page counts its words as a chapter does: each Chinese or Japanese character is one.
    func testAWebPageCountsWordsAsAChapterDoes() throws {
        let page = try library.save(env.article("https://example.com/tokyo", paragraphs: ["東京は晴れ。 Sunny today."]))
        XCTAssertEqual(page.wordCount, 7)
    }

    func testSaveOnALinkTurnsItSavedInPlace() throws {
        let reading = try library.makeFolder(name: "Reading", in: nil)
        let link = try library.addLink(url: URL(string: "https://example.com/a")!, title: "A", artwork: nil, in: reading)
        XCTAssertTrue(link.isLink)
        XCTAssertFalse(link.hasText)
        let saved = try library.save(env.article("https://example.com/a", title: "Article A"))
        XCTAssertIdentical(saved, link)
        XCTAssertTrue(saved.isSavedToLibrary)
        XCTAssertIdentical(saved.folder, reading, "it keeps its folder")
        XCTAssertEqual(saved.cachedListenParagraphs?.count, 2)
    }

    func testPlayingALinkKeepsItALinkWithATextCachePrunedAfter7Days() throws {
        let link = try library.addLink(url: URL(string: "https://example.com/a")!, title: "A", artwork: nil,
                                       in: try library.makeFolder(name: "Links", in: nil))
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

    /// A chapter is a page like any other: it moves out of its book, is saved into another
    /// folder, starred in place, and removed from the Library; other pages move in. Its book's
    /// place moves off it as it leaves.
    func testAChapterLeavesItsBookAsAnyPageAndPagesMoveIn() throws {
        let book = Folder(name: "Book", kind: .book)
        env.context.insert(book)
        let chapters = try (1...4).map {
            try library.save(env.article("https://example.com/ch\($0)", title: "Ch \($0)"), placement: .folder(book))
        }
        let other = try library.makeFolder(name: "Elsewhere", in: nil)
        book.currentPageKey = chapters[1].key

        try library.move([.page(chapters[1])], to: other)
        XCTAssertIdentical(chapters[1].folder, other, "moved out")
        XCTAssertEqual(book.currentPageKey, chapters[0].key, "the book's place moves to the page before")
        try library.save(env.article("https://example.com/ch3"), placement: .folder(other))
        XCTAssertIdentical(chapters[2].folder, other, "saved into another folder")
        try library.addFavorite(url: URL(string: "https://example.com/ch4")!, title: nil, artwork: nil)
        XCTAssertTrue(LibraryStore.isFavorite(chapters[3]), "starred without changing location")
        try library.remove([chapters[0]])
        XCTAssertNil(chapters[0].folder)
        XCTAssertNil(chapters[0].addedAt, "out of the Library")
        XCTAssertNil(book.currentPageKey, "none left before it")

        let article = try library.save(env.article("https://example.com/article"))
        try library.move([.page(article)], to: book)
        XCTAssertEqual(Set(library.pages(in: book).map(\.title)), Set([chapters[3].title, article.title]), "a book is an ordinary folder")
        let inner = try library.makeFolder(name: "Notes", in: book)
        XCTAssertIdentical(inner.parent, book, "and subfolders")
    }

    /// Favorites are independent of folder location, including for a series chapter.
    func testFavoriteSeriesChapterKeepsItsLocation() throws {
        let series = Folder(name: "Serial", kind: .series)
        env.context.insert(series)
        let savedURL = URL(string: "https://example.com/serial/1")!
        let linkURL = URL(string: "https://example.com/serial/2")!
        let saved = try library.save(env.article(savedURL.absoluteString, title: "Ch 1"))
        saved.setFolder(series)
        let link = try library.addLink(url: linkURL, title: "Ch 2", artwork: nil, in: series)
        XCTAssertFalse(LibraryStore.isFavorite(saved), "location alone does not favorite a page")
        try library.addFavorite(url: savedURL, title: nil, artwork: nil)
        XCTAssertTrue(LibraryStore.isFavorite(saved))
        XCTAssertIdentical(library.favorite(for: savedURL), saved, "☆ removes it")

        try library.removeFavorite(saved)
        XCTAssertIdentical(saved.folder, series, "removing a favorite does not move the page")
        XCTAssertTrue(saved.isSavedToLibrary)
        XCTAssertNil(library.favorite(for: linkURL), "an unstarred link can be starred in place")
        try library.addFavorite(url: linkURL, title: nil, artwork: nil)
        XCTAssertTrue(link.isFavorite)
        XCTAssertIdentical(link.folder, series)
    }

    /// *Library (no folder)* in the Move tree files the page in no folder, out of the folder or
    /// book it was in; an ordinary save keeps it where it is.
    func testPickingNoFolderTakesALinkOutOfItsFolderAndAnOrdinarySaveKeepsIt() throws {
        let reading = try library.makeFolder(name: "Reading", in: nil)
        try library.addLink(url: URL(string: "https://example.com/kept")!, title: "Kept", artwork: nil, in: reading)
        let kept = try library.save(env.article("https://example.com/kept"))
        XCTAssertIdentical(kept.folder, reading, "an ordinary save keeps its folder")

        try library.addLink(url: URL(string: "https://example.com/out")!, title: "Out", artwork: nil, in: reading)
        let out = try library.save(env.article("https://example.com/out"), placement: .folder(nil))
        XCTAssertNil(out.folder, "picked: no folder")
        XCTAssertTrue(out.isSavedToLibrary)
        XCTAssertFalse(LibraryStore.isFavorite(out))

        let book = Folder(name: "Book", kind: .book)
        env.context.insert(book)
        let chapter = try library.addLink(url: URL(string: "https://example.com/ch")!, title: "Ch", artwork: nil, in: book)
        try library.save(env.article("https://example.com/ch"))
        XCTAssertIdentical(chapter.folder, book, "an ordinary save keeps a chapter in its book")
        try library.save(env.article("https://example.com/ch"), placement: .folder(nil))
        XCTAssertNil(chapter.folder, "picked: out of the book (decision D19)")
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
        XCTAssertTrue(env.pages().filter(\.isInLibrary).isEmpty)
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

        let link = try library.addLink(url: URL(string: "https://example.com/link")!, title: "L", artwork: nil,
                                       in: try library.makeFolder(name: "Links", in: nil))
        try library.remove([link])
        XCTAssertNil(library.page(url: URL(string: "https://example.com/link")!), "a link is deleted")
    }

    /// A link that was played holds that play's text: removing it keeps it, in no list (out of
    /// the Library and Favorites, and not "Not saved"), pruned 7 days after its last play like
    /// any page out of the Library.
    func testRemovingAPlayedLinkKeepsItOutOfEveryListUntilThePrune() throws {
        let url = URL(string: "https://example.com/played-link")!
        let link = try library.addLink(url: url, title: "Played link", artwork: nil, in: try library.makeFolder(name: "Links", in: nil))
        library.recordPlayback(env.article(url.absoluteString))
        let key = try XCTUnwrap(link.key)
        try env.storeAudio(key, paragraphs: link.cachedListenParagraphs ?? [])
        XCTAssertTrue(link.isLink && link.hasText)

        try library.remove([link])
        let page = try XCTUnwrap(library.page(url: url), "kept: it holds the text of a play")
        XCTAssertIdentical(page, link)
        XCTAssertFalse(page.isInLibrary)
        XCTAssertNil(page.folder, "out of its folder")
        XCTAssertTrue(library.favoritePages().isEmpty)
        XCTAssertTrue(page.hasText)
        XCTAssertEqual(page.cachedListenParagraphs?.count, 2)
        XCTAssertNotNil(page.lastPlayedAt)
        XCTAssertEqual(env.cache.loadMeta(for: key)?.kind, .ephemeral, "its audio is on the ephemeral TTL")
        XCTAssertTrue(try env.context.fetch(LibraryQueries.playedNotSaved).isEmpty, "not back as Not saved")

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

    func testUnsaveKeepsAFavoriteAsALinkAndRemovesALoosePageOrAChapter() throws {
        let url = URL(string: "https://example.com/fav")!
        let favorite = try library.save(env.article(url.absoluteString))
        try library.addFavorite(url: url, title: favorite.title, artwork: nil)
        try library.unsave(favorite)
        XCTAssertTrue(favorite.isLink)
        XCTAssertNil(favorite.folder, "its location does not change")
        XCTAssertTrue(favorite.isFavorite, "unsaving preserves the independent favorite flag")
        XCTAssertFalse(favorite.hasText, "never played: no cache to keep")

        let loose = try library.save(env.article("https://example.com/loose"))
        try library.unsave(loose)
        XCTAssertNil(loose.addedAt)
        XCTAssertFalse(loose.isSavedToLibrary)

        let book = Folder(name: "Book", kind: .book)
        env.context.insert(book)
        let chapter = Page(key: UUID(), title: "Ch 1", byline: "", urlString: nil, contentState: .saved, addedAt: env.now)
        env.context.insert(chapter)
        chapter.setFolder(book)
        try library.unsave(chapter)
        XCTAssertNil(chapter.folder, "no address to keep as a link: it leaves the Library")
        XCTAssertNil(chapter.addedAt)
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
