import SwiftData
import XCTest
@testable import MeridianReader

/// Every rule of the launch dedupe pass (the cases sync and a migration copy can make).
@MainActor
final class LibraryDedupeTests: XCTestCase {
    private var env: LibraryTestEnvironment!
    private var library: LibraryStore { env.library }

    override func setUp() async throws { env = try LibraryTestEnvironment() }
    override func tearDown() async throws { env.cleanUp() }

    private func page(_ url: String, key: UUID = UUID(), state: PageContentState = .saved, position: Int = 0,
                      added: Date? = nil, played: Date? = nil, in folder: Folder? = nil) -> Page {
        let p = Page(key: key, title: url, byline: "example.com", urlString: url, contentState: state,
                     addedAt: added ?? env.now, sortKey: 0)
        env.context.insert(p)
        p.positionParagraph = position
        p.lastPlayedAt = played
        p.setFolder(folder)
        return p
    }

    func testBookFoldersMergeBeforePages() throws {
        let older = Folder(name: "Book", kind: .book, createdAt: env.now)
        let newer = Folder(name: "Book (copy)", kind: .book, createdAt: env.now + 10)
        for f in [older, newer] { f.sourceIdentifier = "book-key"; env.context.insert(f) }
        let shared = UUID()
        _ = page("https://example.com/ch1", key: shared, in: older)
        let copy = page("https://example.com/ch1", key: shared, position: 4, played: env.now + 20, in: newer)
        let onlyInCopy = page("https://example.com/ch2", in: newer)
        newer.currentPageKey = shared
        try env.context.save()

        let report = library.dedupe()
        XCTAssertEqual(report.mergedFolders, 1)
        XCTAssertEqual(report.mergedPages, 1)
        XCTAssertEqual(env.folders().filter { $0.kind == .book }.map(\.name), ["Book"], "into the older folder")
        let pages = library.pages(in: older)
        XCTAssertEqual(pages.count, 2, "one page per key, none left split")
        XCTAssertTrue(pages.contains { $0 === copy } || pages.contains { $0.key == shared })
        XCTAssertIdentical(onlyInCopy.folder, older)
        XCTAssertEqual(older.currentPageKey, shared, "the place of the copy played later is kept")
        XCTAssertEqual(pages.first { $0.key == shared }?.positionParagraph, 4, "the furthest copy is the keeper")
    }

    /// The save fails: the folders and pages callers already hold read what the store holds,
    /// relationships included, without a fetch (every rolled-back change refreshes what it
    /// touched, `LibraryStore.rollBack`).
    func testAFailedSaveLeavesTheFoldersAndPagesHeldAsTheyWere() throws {
        struct SaveFailed: Error {}
        let older = Folder(name: "Book", kind: .book, createdAt: env.now)
        let newer = Folder(name: "Book (copy)", kind: .book, createdAt: env.now + 10)
        for f in [older, newer] { f.sourceIdentifier = "book-key"; env.context.insert(f) }
        let shared = UUID()
        let original = page("https://example.com/ch1", key: shared, in: older)
        let copy = page("https://example.com/ch1", key: shared, position: 4, played: env.now + 20, in: newer)
        let onlyInCopy = page("https://example.com/ch2", in: newer)
        newer.currentPageKey = shared
        try env.context.save()
        library.saveContext = { _ in throw SaveFailed() }

        XCTAssertEqual(library.dedupe().mergedFolders, 1)
        XCTAssertFalse(env.context.hasChanges)
        XCTAssertFalse(newer.isDeleted)
        XCTAssertNil(older.currentPageKey, "the older book's place")
        XCTAssertEqual((older.pages ?? []).map(\.key), [shared], "its pages")
        XCTAssertEqual(Set((newer.pages ?? []).map(\.key)), [shared, onlyInCopy.key], "the copy's")
        XCTAssertTrue(onlyInCopy.folder === newer)
        XCTAssertEqual(onlyInCopy.folderID, newer.id)
        XCTAssertTrue(copy.folder === newer)
        XCTAssertFalse(original.isDeleted)
        XCTAssertTrue(original.folder === older)
    }

    func testSavedBeatsLinkAtEqualPositionAndTheKeeperTakesWhatItLacks() throws {
        let reading = Folder(name: "Reading")
        env.context.insert(reading)
        let link = page("https://example.com/a", key: ArticleIdentity.articleKey(canonicalURL: "https://example.com/a"),
                        state: .link, added: env.now - 100, in: reading)
        link.artworkData = Data([5])
        let saved = page("https://example.com/a?utm_source=x", added: env.now)
        saved.canonicalURL = "https://example.com/a"
        saved.storeListenParagraphs(["Text one.", "Text two."])
        saved.cleanedHTML = "<p>Text one.</p><p>Text two.</p>"
        try env.storeAudio(link.key!, paragraph: 0, text: "Text one.")
        try env.context.save()

        XCTAssertEqual(library.dedupe().mergedPages, 1)
        let pages = env.pages()
        XCTAssertEqual(pages.count, 1)
        let keeper = try XCTUnwrap(pages.first)
        XCTAssertIdentical(keeper, saved, "saved beats link")
        XCTAssertEqual(keeper.artworkData, Data([5]), "missing content copied into the keeper")
        XCTAssertIdentical(keeper.folder, reading, "the keeper had no folder: it takes the other's")
        XCTAssertEqual(keeper.folderID, keeper.folder?.id)
        XCTAssertEqual(keeper.addedAt, env.now - 100, "the earliest add")
        XCTAssertTrue(env.cache.hasCache(for: saved.key!), "the other's audio merged into the keeper")
        XCTAssertFalse(env.cache.hasCache(for: link.key!))
    }

    /// The duplicate that loses was starred, finished and skipped: the keeper is too.
    func testTheKeeperTakesTheStarAndMarksOfTheDuplicateThatLoses() throws {
        let keeper = page("https://example.com/starred", position: 3)
        let loser = page("https://example.com/starred", position: 1)
        loser.isFavorite = true
        loser.finishedAt = env.now
        loser.skipsInPlayback = true
        try env.context.save()

        XCTAssertEqual(library.dedupe().mergedPages, 1)
        XCTAssertEqual(env.pages().map(\.positionParagraph), [3], "the furthest copy is kept")
        XCTAssertTrue(keeper.isFavorite, "the star of the copy that lost")
        XCTAssertEqual(keeper.finishedAt, env.now)
        XCTAssertTrue(keeper.skipsInPlayback)
    }

    func testKeeperOrderFurthestThenLatestPlayThenOlder() throws {
        let a = page("https://example.com/x", position: 2, added: env.now)
        let b = page("https://example.com/x", position: 5, added: env.now + 1)
        XCTAssertTrue(LibraryStore.betterKeeper(b, a), "furthest position")
        b.positionParagraph = 2
        a.lastPlayedAt = env.now + 50
        XCTAssertTrue(LibraryStore.betterKeeper(a, b), "latest play")
        a.lastPlayedAt = nil
        XCTAssertTrue(LibraryStore.betterKeeper(a, b), "older")
        let unsaved = page("https://example.com/x", added: nil)
        unsaved.addedAt = nil
        XCTAssertTrue(LibraryStore.betterKeeper(a, unsaved), "a page in the Library is older than one that isn't")
    }

    func testPlacesTheResumePointAndTheSessionFollowTheKeeper() throws {
        let series = Folder(name: "Serial", kind: .series)
        env.context.insert(series)
        let keeper = page("https://example.com/c1", position: 3, in: series)
        let extra = page("https://example.com/c1", position: 1)
        series.currentPageKey = extra.key
        env.tts.resumePoints.save(article: extra.key!, paragraph: 1)
        var merged: [(UUID, UUID)] = []
        library.keyMerged = { from, to, _ in merged.append((from, to)) }
        try env.context.save()

        library.dedupe()
        XCTAssertEqual(series.currentPageKey, keeper.key)
        XCTAssertEqual(env.tts.resumePoints.load()?.articleKey, keeper.key?.uuidString)
        XCTAssertEqual(merged.map(\.0), [extra.key!])
        XCTAssertEqual(merged.map(\.1), [keeper.key!])
        XCTAssertIdentical(keeper.folder, series, "a page in a series keeps it")
    }

    /// Crash recovery read its target at launch, before dedupe: when that page is merged away,
    /// the target in memory follows the resume file onto the kept page, on the same paragraph
    /// text even though the two pages' paragraphs differ, and in the text the kept page holds,
    /// so crash resume applies it there.
    func testTheCrashTargetReadAtLaunchFollowsTheKeeper() throws {
        let extra = page("https://example.com/c2", position: 0)
        let played = ["An intro.", "Alpha one.", "Beta two."]
        extra.storeListenParagraphs(played)
        let keeper = page("https://example.com/c2", position: 1)
        keeper.storeListenParagraphs(["Alpha one.", "Beta two."])
        let text = ArticleIdentity.contentFingerprint(paragraphs: played)
        env.tts.resumePoints.save(article: extra.key!, paragraph: 2, text: text, at: env.now)
        env.tts.pendingResume = ListenResumeTarget(articleKey: extra.key!.uuidString, paragraph: 2, text: text,
                                                   at: env.now, autoPlay: true)
        try env.context.save()

        XCTAssertEqual(library.dedupe().mergedPages, 1)
        let target = try XCTUnwrap(env.tts.takePendingResume())
        XCTAssertIdentical(library.page(matching: target), keeper, "launch resumes the kept page")
        XCTAssertEqual(target.paragraph, 1, "on \"Beta two.\", its paragraph there")
        XCTAssertTrue(library.holds(keeper, text: target.text), "in the text the kept page holds")
        XCTAssertTrue(target.autoPlay)
        let file = try XCTUnwrap(env.tts.resumePoints.load())
        XCTAssertEqual(file.articleKey, keeper.key?.uuidString)
        XCTAssertEqual(file.paragraph, 1)
        XCTAssertEqual(file.text, target.text)
    }

    /// The resume file and the crash target name a paragraph of other text than the merged page
    /// holds (a session that played on in an older text). The merge moves them to the kept page
    /// but doesn't map that paragraph through text it isn't in: they keep their paragraph and
    /// text, which the kept page doesn't hold, so crash resume won't apply it there.
    func testACrashTargetInOtherTextFollowsTheKeeperWithoutMapping() throws {
        let extra = page("https://example.com/c3", position: 0)
        extra.storeListenParagraphs(["An intro.", "Alpha one.", "Beta two."])
        let keeper = page("https://example.com/c3", position: 1)
        keeper.storeListenParagraphs(["Alpha one.", "Beta two."])
        let older = ArticleIdentity.contentFingerprint(paragraphs: ["An older intro.", "Older one.", "Older two."])
        env.tts.resumePoints.save(article: extra.key!, paragraph: 2, text: older, at: env.now)
        env.tts.pendingResume = ListenResumeTarget(articleKey: extra.key!.uuidString, paragraph: 2, text: older,
                                                   at: env.now, autoPlay: true)
        try env.context.save()

        XCTAssertEqual(library.dedupe().mergedPages, 1)
        let target = try XCTUnwrap(env.tts.takePendingResume())
        XCTAssertIdentical(library.page(matching: target), keeper, "it follows the kept page")
        XCTAssertEqual(target.paragraph, 2, "its paragraph unmapped")
        XCTAssertEqual(target.text, older, "still in the text it was played in")
        XCTAssertFalse(library.holds(keeper, text: target.text))
        let file = try XCTUnwrap(env.tts.resumePoints.load())
        XCTAssertEqual(file.articleKey, keeper.key?.uuidString)
        XCTAssertEqual(file.paragraph, 2)
        XCTAssertEqual(file.text, older)
    }

    func testCyclesAndFolderIDsAreRepaired() throws {
        let x = Folder(name: "X", createdAt: env.now)
        let y = Folder(name: "Y", createdAt: env.now + 1)
        env.context.insert(x)
        env.context.insert(y)
        x.parent = y
        y.parent = x
        let book = Folder(name: "Book", kind: .book)
        let shelf = Folder(name: "Shelf")
        let inside = Folder(name: "Inside")
        for f in [book, shelf, inside] { env.context.insert(f) }
        book.parent = shelf
        inside.parent = book
        let p = page("https://example.com/p", in: shelf)
        p.folderID = UUID() // disagrees with the relationship
        try env.context.save()

        let report = library.dedupe()
        XCTAssertEqual(report.brokenCycles, 1)
        XCTAssertNil(y.parent, "the newest folder in the cycle moves to the top level")
        XCTAssertIdentical(x.parent, y)
        XCTAssertIdentical(inside.parent, book, "a folder inside a book stays (decision D19)")
        XCTAssertEqual(p.folderID, shelf.id, "the relationship wins")
        XCTAssertEqual(library.dedupe(), LibraryStore.DedupeReport(), "idempotent")
    }
}
