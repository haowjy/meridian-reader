import SwiftData
import XCTest
@testable import MeridianReader

/// The copy from saved articles, bookmarks and listen history into the library: same keys, audio
/// found where it is, Favorites in the bookmarks' order, copy-once by the receipts saved with the
/// copy, and nothing legacy ever written.
@MainActor
final class LibraryMigrationTests: XCTestCase {
    private var env: LibraryTestEnvironment!
    private var library: LibraryStore { env.library }

    override func setUp() async throws { env = try LibraryTestEnvironment() }
    override func tearDown() async throws { env.cleanUp() }

    private let day: TimeInterval = 24 * 3600
    private func date(_ days: Double) -> Date { Date(timeIntervalSince1970: 1_700_000_000 + days * day) }

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
        XCTAssertTrue(report.saved)

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
        XCTAssertTrue(PageProgress.isPartWay(page), "part-way: its row shows the time left")
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
        try library.removeFavorite(XCTUnwrap(library.page(url: URL(string: "https://example.com/fav")!)))
        env.makeLibrary().migrateLegacy()
        XCTAssertNil(library.page(url: URL(string: "https://example.com/1")!), "a deleted page never comes back")
        XCTAssertNil(library.page(url: URL(string: "https://example.com/fav")!), "nor a removed favorite")
        XCTAssertEqual(env.pages().count, 1)
    }

    /// What was copied is recorded with the copy itself: even when nothing beside the store files
    /// can be written, a page deleted, unsaved or removed from Favorites after the copy stays that
    /// way after a relaunch from a fresh container on the same files.
    func testTheCopyIsRecordedWithItSoNothingRemovedComesBackAfterARelaunch() throws {
        env.cleanUp()
        env = try LibraryTestEnvironment(fileBacked: true)
        env.legacyRow("https://example.com/deleted", title: "Deleted", savedAt: date(0))
        env.legacyRow("https://example.com/unsaved", title: "Unsaved", savedAt: date(1))
        env.legacyRow("https://example.com/kept", title: "Kept", savedAt: date(2))
        try env.writeBookmarks([SiteBookmark(urlString: "https://example.com/fav", title: "Fav", host: "example.com")])
        // Only the store folder (and the folders already there) take new files.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: env.dir.path)

        library.migrateLegacy()
        XCTAssertEqual(env.pages().count, 4)
        library.delete(try XCTUnwrap(library.page(url: URL(string: "https://example.com/deleted")!)))
        try library.unsave(XCTUnwrap(library.page(url: URL(string: "https://example.com/unsaved")!)))
        try library.removeFavorite(XCTUnwrap(library.page(url: URL(string: "https://example.com/fav")!)))

        try env.relaunch()
        let report = library.migrateLegacy()
        XCTAssertEqual(report.copiedArticles + report.copiedBookmarks, 0, "everything was recorded as copied")
        XCTAssertNil(library.page(url: URL(string: "https://example.com/deleted")!), "a deleted page stays deleted")
        XCTAssertEqual(library.page(url: URL(string: "https://example.com/unsaved")!)?.isInLibrary, false,
                       "an unsaved page stays out of the Library")
        XCTAssertNil(library.page(url: URL(string: "https://example.com/fav")!), "a removed favorite stays removed")
        XCTAssertEqual(try env.context.fetch(LibraryQueries.inLibrary).map(\.title), ["Kept"])
    }

    /// An empty bookmarks file (no bytes, or an empty list) copies no favorites, isn't an error,
    /// and stays as it was; the saved rows are copied as usual.
    func testAnEmptyBookmarksFileCopiesNothingAndStaysAsItWas() throws {
        env.legacyRow("https://example.com/1", savedAt: date(0))
        for bytes in [Data(), Data("[]".utf8)] {
            try FileManager.default.createDirectory(at: env.legacy.bookmarksURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try bytes.write(to: env.legacy.bookmarksURL)
            let report = env.makeLibrary().migrateLegacy()
            XCTAssertFalse(report.bookmarksUnreadable, "\(bytes.count) bytes")
            XCTAssertEqual(report.copiedBookmarks, 0)
            XCTAssertTrue(library.favoritePages().isEmpty)
            XCTAssertEqual(try Data(contentsOf: env.legacy.bookmarksURL), bytes)
        }
        XCTAssertNotNil(library.page(url: URL(string: "https://example.com/1")!))
    }

    /// A bookmarks file that doesn't decode: logged, nothing copied or recorded from it, its
    /// bytes left untouched, the saved rows copied. If it becomes readable later (the previous
    /// build wrote it during a rollback), its bookmarks are copied then.
    func testACorruptBookmarksFileIsLeftAloneAndNothingIsLost() throws {
        env.cleanUp()
        env = try LibraryTestEnvironment(fileBacked: true)
        env.legacyRow("https://example.com/1", savedAt: date(0))
        let corrupt = Data("[{\"urlString\": \"https://example.com/fav\", \"tit".utf8)
        try FileManager.default.createDirectory(at: env.legacy.bookmarksURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try corrupt.write(to: env.legacy.bookmarksURL)

        let report = library.migrateLegacy()
        XCTAssertTrue(report.bookmarksUnreadable)
        XCTAssertTrue(report.saved)
        XCTAssertEqual(report.copiedArticles, 1, "the saved rows still come over")
        XCTAssertEqual(report.copiedBookmarks, 0)
        XCTAssertEqual(try Data(contentsOf: env.legacy.bookmarksURL), corrupt, "the bytes are untouched")
        XCTAssertFalse(env.receipts().contains { $0.source == .bookmark }, "nothing recorded from it")

        try env.writeBookmarks([SiteBookmark(urlString: "https://example.com/fav", title: "Fav", host: "example.com")])
        let later = env.makeLibrary().migrateLegacy()
        XCTAssertFalse(later.bookmarksUnreadable)
        XCTAssertEqual(later.copiedBookmarks, 1)
        XCTAssertEqual(library.favoritePages().map(\.title), ["Fav"])

        // Copied once: removed, it stays removed when the next launch migrates from the files.
        try library.removeFavorite(XCTUnwrap(library.page(url: URL(string: "https://example.com/fav")!)))
        try env.relaunch()
        let again = library.migrateLegacy()
        XCTAssertEqual(again.copiedArticles + again.copiedBookmarks, 0)
        XCTAssertTrue(library.favoritePages().isEmpty, "the removed favorite stays removed")
        XCTAssertNil(library.page(url: URL(string: "https://example.com/fav")!))
    }

    /// A rollback: the previous build ran in between and saved or bookmarked something new.
    func testRowsAndBookmarksAddedAfterTheFirstRunAreCopied() throws {
        env.legacyRow("https://example.com/1", savedAt: date(0))
        let fav = SiteBookmark(urlString: "https://example.com/fav", title: "Fav", host: "example.com")
        try env.writeBookmarks([fav])
        library.migrateLegacy()
        // Removed in this build.
        try library.removeFavorite(XCTUnwrap(library.page(url: URL(string: "https://example.com/fav")!)))

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

    /// The pages and their receipts are one save: when it fails, a relaunch from disk finds
    /// neither, and copies again; once it succeeds, what was deleted after it stays deleted.
    func testWhenTheSaveFailsNothingIsCopiedOrRecordedAndTheNextLaunchCopies() throws {
        struct SaveFailed: Error {}
        env.cleanUp()
        env = try LibraryTestEnvironment(fileBacked: true)
        env.legacyRow("https://example.com/1", title: "One", savedAt: date(0))
        env.legacyRow("https://example.com/2", title: "Two", savedAt: date(1))
        try env.writeBookmarks([SiteBookmark(urlString: "https://example.com/fav", title: "Fav", host: "example.com")])
        library.saveContext = { _ in throw SaveFailed() }

        let failed = library.migrateLegacy()
        XCTAssertFalse(failed.saved)
        XCTAssertTrue(env.pages().isEmpty, "nothing half-copied stays behind")
        XCTAssertTrue(env.receipts().isEmpty)

        try env.relaunch()
        XCTAssertTrue(env.pages().isEmpty, "nothing reached the store")
        XCTAssertTrue(env.receipts().isEmpty)
        let retried = library.migrateLegacy()
        XCTAssertTrue(retried.saved)
        XCTAssertEqual(retried.copiedArticles, 2)
        XCTAssertEqual(retried.copiedBookmarks, 1)
        XCTAssertEqual(env.receipts().count, 3)

        library.delete(try XCTUnwrap(library.page(url: URL(string: "https://example.com/1")!)))
        try library.unsave(XCTUnwrap(library.page(url: URL(string: "https://example.com/2")!)))
        try library.removeFavorite(XCTUnwrap(library.page(url: URL(string: "https://example.com/fav")!)))
        try env.relaunch()
        let again = library.migrateLegacy()
        XCTAssertEqual(again.copiedArticles + again.copiedBookmarks, 0)
        XCTAssertNil(library.page(url: URL(string: "https://example.com/1")!))
        XCTAssertEqual(library.page(url: URL(string: "https://example.com/2")!)?.isInLibrary, false)
        XCTAssertNil(library.page(url: URL(string: "https://example.com/fav")!))
    }

    #if DEBUG
    func testRerunLibraryMigrationCopiesEverythingAgain() throws {
        env.legacyRow("https://example.com/1", savedAt: date(0))
        library.migrateLegacy()
        library.delete(try XCTUnwrap(library.page(url: URL(string: "https://example.com/1")!)))
        library.resetForMigrationRerun()
        XCTAssertTrue(env.pages().isEmpty)
        XCTAssertTrue(env.receipts().isEmpty)
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
        try library.save(env.article("https://example.com/1", title: "Edited"))
        library.delete(page)

        XCTAssertEqual(try env.context.fetch(FetchDescriptor<SavedArticle>()).map(\.id), [row.id], "the row is still there")
        XCTAssertEqual(row.title, "Legacy")
        XCTAssertEqual(row.playbackParagraphIndex, 2)
        XCTAssertEqual(try Data(contentsOf: env.legacy.bookmarksURL), bookmarksBefore)
        XCTAssertEqual(env.defaults.data(forKey: ListenHistory.storageKey), historyBefore)
    }
}
