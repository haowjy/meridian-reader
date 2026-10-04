import SwiftData
import XCTest
@testable import Reader

/// The copy from saved articles, bookmarks and listen history into the library: same keys, audio
/// found where it is, Favorites in the bookmarks' order, copy-once by the ledger, and nothing
/// legacy ever written.
@MainActor
final class LibraryMigrationTests: XCTestCase {
    private var env: LibraryTestEnvironment!
    private var library: LibraryStore { env.library }

    override func setUp() async throws { env = try LibraryTestEnvironment() }
    override func tearDown() async throws { env.cleanUp() }

    private let day: TimeInterval = 24 * 3600
    private func date(_ days: Double) -> Date { Date(timeIntervalSince1970: 1_700_000_000 + days * day) }

    private func continuePages() throws -> [Page] {
        LibraryQueries.continuePages(recent: try env.context.fetch(LibraryQueries.recentlyPlayed),
                                     undated: try env.context.fetch(LibraryQueries.undatedInProgress))
    }

    func testLegacyRandomIDRowKeepsItsKeyAudioHistoryAndCrashResume() throws {
        let legacyID = UUID() // a pre-identity-v2 random id, not the URL's key
        let url = "https://example.com/story?utm_source=feed"
        XCTAssertNotEqual(legacyID, ArticleIdentity.articleKey(canonicalURL: ArticleIdentity.canonicalURLString(from: url)))
        let paragraphs = ["One is here.", "Two is here.", "Three is here."]
        env.legacyRow(url, id: legacyID, title: "Story", savedAt: date(0), paragraphs: paragraphs, position: 1,
                      favicon: Data([7, 7]))
        try env.storeAudio(legacyID, paragraphs: paragraphs)
        let indexBefore = try Data(contentsOf: env.cache.indexURL(for: legacyID))
        env.writeHistory([legacyID: (at: date(3).timeIntervalSince1970, done: false)])
        ListenResumePointStore.shared.save(article: legacyID, paragraph: 2, at: date(3))

        let report = library.migrateLegacy()
        XCTAssertEqual(report.copiedArticles, 1)
        XCTAssertTrue(report.ledgerWritten)

        let page = try XCTUnwrap(library.page(key: legacyID), "the page keeps the row's id as its key")
        XCTAssertEqual(page.title, "Story")
        XCTAssertEqual(page.canonicalURL, "https://example.com/story")
        XCTAssertTrue(page.isSavedToLibrary)
        XCTAssertNil(page.folder)
        XCTAssertEqual(page.positionParagraph, 1)
        XCTAssertEqual(page.paragraphCount, 3)
        XCTAssertEqual(page.cachedListenParagraphs, paragraphs)
        XCTAssertEqual(page.artworkData, Data([7, 7]))
        XCTAssertEqual(page.addedAt, date(0))
        XCTAssertEqual(page.lastPlayedAt, date(3), "listen history folded in")
        XCTAssertNil(page.finishedAt)
        XCTAssertIdentical(library.page(url: URL(string: "https://example.com/story#top")!), page,
                           "found by address, whatever its key")

        XCTAssertTrue(env.cache.hasCache(for: legacyID), "the audio is found under the same key")
        XCTAssertEqual(try Data(contentsOf: env.cache.indexURL(for: legacyID)), indexBefore, "and wasn't rewritten")
        XCTAssertEqual(try continuePages().map(\.key), [legacyID], "in Continue")
        let target = try XCTUnwrap(ListenResumePointStore.shared.load())
        XCTAssertIdentical(library.page(matching: target), page, "crash resume finds it")
        let oldMarker = ListenResumeTarget(articleKey: String(legacyID.uuidString.prefix(8)), paragraph: 2, at: date(3))
        XCTAssertIdentical(library.page(matching: oldMarker), page, "and by an old 8-character crash marker")
    }

    func testBookmarksBecomeFavoritesInFileOrderWithASavedPageAtItsBookmarksPlace() throws {
        let savedID = UUID()
        env.legacyRow("https://example.com/b", id: savedID, title: "Saved B", savedAt: date(0))
        let bookmarks = [
            SiteBookmark(urlString: "https://example.com/a", title: "A", host: "example.com", faviconData: Data([1]), createdAt: date(1)),
            SiteBookmark(urlString: "https://example.com/b/?utm_medium=x", title: "B", host: "example.com", createdAt: date(2)),
            SiteBookmark(urlString: "https://example.org/", title: "C", host: "example.org", createdAt: date(3)),
        ]
        try env.writeBookmarks(bookmarks)

        let report = library.migrateLegacy()
        XCTAssertEqual(report.copiedBookmarks, 3)
        XCTAssertEqual(report.savedIntoFavorites, 1)

        let favorites = library.favoritePages()
        XCTAssertEqual(favorites.map(\.title), ["A", "Saved B", "C"], "file order; the saved page at its bookmark's place")
        XCTAssertEqual(favorites.map(\.contentState), [.link, .saved, .link])
        XCTAssertEqual(favorites[1].key, savedID, "the saved page itself, keeping its key and text")
        XCTAssertEqual(favorites[0].key, ArticleIdentity.articleKey(canonicalURL: "https://example.com/a"))
        XCTAssertEqual(favorites[0].artworkData, Data([1]))
        XCTAssertEqual(favorites[0].addedAt, date(1))
        XCTAssertEqual(env.pages().count, 3, "one page per address")
        XCTAssertTrue(try env.context.fetch(LibraryQueries.loosePages(sort: .newest)).isEmpty,
                      "the saved page shows in Favorites, not the Saved list")
        XCTAssertEqual(library.topLevelFolders().map(\.kind), [.favorites])
    }

    func testRunningTwiceCopiesNothingMoreAndADeletedPageStaysDeleted() throws {
        env.legacyRow("https://example.com/1", savedAt: date(0))
        env.legacyRow("https://example.com/2", savedAt: date(1))
        try env.writeBookmarks([SiteBookmark(urlString: "https://example.com/fav", title: "Fav", host: "example.com")])
        library.migrateLegacy()
        XCTAssertEqual(env.pages().count, 3)
        XCTAssertEqual(env.folders().count, 1)

        let again = env.makeLibrary().migrateLegacy()
        XCTAssertEqual(again.copiedArticles + again.copiedBookmarks, 0)
        XCTAssertEqual(env.pages().count, 3, "same counts")
        XCTAssertEqual(env.folders().count, 1)

        library.delete(try XCTUnwrap(library.page(url: URL(string: "https://example.com/1")!)))
        library.removeFavorite(try XCTUnwrap(library.page(url: URL(string: "https://example.com/fav")!)))
        env.makeLibrary().migrateLegacy()
        XCTAssertNil(library.page(url: URL(string: "https://example.com/1")!), "a deleted page never comes back")
        XCTAssertNil(library.page(url: URL(string: "https://example.com/fav")!), "nor a removed favorite")
        XCTAssertEqual(env.pages().count, 1)
    }

    /// A rollback: the previous build ran in between and saved or bookmarked something new.
    func testRowsAndBookmarksAddedAfterTheFirstRunAreCopied() throws {
        env.legacyRow("https://example.com/1", savedAt: date(0))
        let fav = SiteBookmark(urlString: "https://example.com/fav", title: "Fav", host: "example.com")
        try env.writeBookmarks([fav])
        library.migrateLegacy()
        // Removed in this build.
        library.removeFavorite(try XCTUnwrap(library.page(url: URL(string: "https://example.com/fav")!)))

        env.legacyRow("https://example.com/2", title: "During rollback", savedAt: date(5))
        // The old build's user also removed it and bookmarked it again (a new id).
        try env.writeBookmarks([
            SiteBookmark(urlString: "https://example.com/fav", title: "Fav again", host: "example.com"),
            SiteBookmark(urlString: "https://example.com/new", title: "New", host: "example.com"),
        ])

        let report = env.makeLibrary().migrateLegacy()
        XCTAssertEqual(report.copiedArticles, 1)
        XCTAssertEqual(report.copiedBookmarks, 2)
        XCTAssertEqual(library.page(url: URL(string: "https://example.com/2")!)?.title, "During rollback")
        XCTAssertEqual(library.favoritePages().map(\.title), ["Fav again", "New"])
    }

    /// Copied rows are frozen: launch maintenance after the copy never touches a copied page's
    /// audio again, and never rewrites the row, even one on older listen blocks.
    func testLaterLaunchesNeverTouchCopiedRowsOrTheirAudio() throws {
        let id = UUID()
        let paragraphs = ["Alpha sentence.", "Beta sentence."]
        let row = env.legacyRow("https://example.com/frozen", id: id, savedAt: date(0), paragraphs: paragraphs, position: 1)
        try env.storeAudio(id, paragraphs: paragraphs)
        library.migrateLegacy()
        library.dedupe()
        library.migrateParagraphLayout()
        let files = try FileManager.default.contentsOfDirectory(atPath: env.cache.directory(for: id).path).sorted()
        let index = try Data(contentsOf: env.cache.indexURL(for: id))

        // The old build made the row stale meanwhile (an older listen-blocks version).
        row.listenBlocksVersion = 2
        try env.context.save()
        let relaunch = env.makeLibrary()
        relaunch.migrateLegacy()
        relaunch.dedupe()
        XCTAssertEqual(relaunch.migrateParagraphLayout().articles, 0, "the copied page is current; the row isn't migrated")
        relaunch.pruneUnsaved()

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: env.cache.directory(for: id).path).sorted(), files)
        XCTAssertEqual(try Data(contentsOf: env.cache.indexURL(for: id)), index)
        XCTAssertEqual(row.listenBlocksVersion, 2, "the frozen row is left as the old build wrote it")
        XCTAssertEqual(row.playbackParagraphIndex, 1)
        XCTAssertEqual(env.pages().count, 1)
    }

    func testTheLedgerIsNotWrittenWhenTheSaveFails() throws {
        struct SaveFailed: Error {}
        env.legacyRow("https://example.com/1", savedAt: date(0))
        try env.writeBookmarks([SiteBookmark(urlString: "https://example.com/fav", title: "Fav", host: "example.com")])
        library.saveContext = { _ in throw SaveFailed() }

        let failed = library.migrateLegacy()
        XCTAssertFalse(failed.ledgerWritten)
        XCTAssertFalse(FileManager.default.fileExists(atPath: env.legacy.ledgerURL.path))
        XCTAssertTrue(env.pages().isEmpty, "nothing half-copied stays behind")

        library.saveContext = { try $0.save() }
        let retried = library.migrateLegacy()
        XCTAssertTrue(retried.ledgerWritten)
        XCTAssertEqual(retried.copiedArticles, 1)
        XCTAssertEqual(retried.copiedBookmarks, 1)
        XCTAssertEqual(env.pages().count, 2)
    }

    /// The app died after the copy was saved but before the ledger was written: the next
    /// launch copies again, and dedupe folds the copies (same keys) into the pages already there.
    func testACrashBeforeTheLedgerCopiesAgainWithoutDuplicates() throws {
        let id = UUID()
        env.legacyRow("https://example.com/1", id: id, savedAt: date(0), position: 2)
        try env.writeBookmarks([SiteBookmark(urlString: "https://example.com/fav", title: "Fav", host: "example.com")])
        library.migrateLegacy()
        try FileManager.default.removeItem(at: env.legacy.ledgerURL)

        let again = env.makeLibrary().migrateLegacy()
        XCTAssertEqual(again.copiedArticles, 1)
        XCTAssertEqual(again.copiedBookmarks, 1)
        XCTAssertEqual(again.mergedDuplicates, 1, "the row's second copy; the bookmark finds its page by address")
        XCTAssertEqual(env.pages().count, 2, "no duplicate pages")
        XCTAssertEqual(library.favoritePages().map(\.title), ["Fav"])
        XCTAssertEqual(library.page(key: id)?.positionParagraph, 2)
        XCTAssertTrue(again.ledgerWritten)
    }

    #if DEBUG
    func testRerunLibraryMigrationCopiesEverythingAgain() throws {
        env.legacyRow("https://example.com/1", savedAt: date(0))
        library.migrateLegacy()
        library.delete(try XCTUnwrap(library.page(url: URL(string: "https://example.com/1")!)))
        library.resetForMigrationRerun()
        XCTAssertTrue(env.pages().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: env.legacy.ledgerURL.path))
        XCTAssertEqual(library.migrateLegacy().copiedArticles, 1)
        XCTAssertNotNil(library.page(url: URL(string: "https://example.com/1")!))
    }
    #endif

    func testLegacyDataIsNeverWritten() throws {
        let row = env.legacyRow("https://example.com/1", savedAt: date(0), position: 2)
        let bookmarks = [SiteBookmark(urlString: "https://example.com/fav", title: "Fav", host: "example.com")]
        try env.writeBookmarks(bookmarks)
        let bookmarksBefore = try Data(contentsOf: env.legacy.bookmarksURL)
        env.writeHistory([row.id: (at: date(1).timeIntervalSince1970, done: true)])
        let historyBefore = env.defaults.data(forKey: ListenHistory.storageKey)

        library.migrateLegacy()
        let page = try XCTUnwrap(library.page(key: row.id))
        XCTAssertEqual(page.finishedAt, date(1), "finished history folded in")
        library.save(env.article("https://example.com/1", title: "Edited"))
        library.delete(page)

        XCTAssertEqual(try env.context.fetch(FetchDescriptor<SavedArticle>()).map(\.id), [row.id], "the row is still there")
        XCTAssertEqual(row.title, "Legacy")
        XCTAssertEqual(row.playbackParagraphIndex, 2)
        XCTAssertEqual(try Data(contentsOf: env.legacy.bookmarksURL), bookmarksBefore)
        XCTAssertEqual(env.defaults.data(forKey: ListenHistory.storageKey), historyBefore)
    }
}
