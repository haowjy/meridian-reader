import XCTest
@testable import MeridianReader

/// Save (🔖, ⋯ → Save to Folder…, *Save to Folder…*) whose save fails: it throws
/// `LibraryStoreError.saveFailed`, nothing is saved (in memory, after a later unrelated save, or
/// after a relaunch), nothing waits in the context, and the audio is left as it was: not marked
/// saved, not moved under another key.
@MainActor
final class ArticleSaveFailureTests: XCTestCase {
    private var env: LibraryTestEnvironment!
    /// Over the environment's file-backed store and its speech stack's audio, as in the app.
    private var library: LibraryStore { env.library }
    private var saver: ArticleSaveCoordinator { ArticleSaveCoordinator(library: library, speech: env.speech.speech) }
    private var cache: ArticleAudioCache { env.cache }

    override func setUp() async throws { env = try LibraryTestEnvironment(fileBacked: true) }

    override func tearDown() async throws { env.cleanUp() }

    private struct SaveFailed: Error {}
    private func failSaves() { library.saveContext = { _ in throw SaveFailed() } }
    private func allowSaves() { library.saveContext = { try $0.save() } }

    private func assertSaveFails(_ article: ReaderArticle, placement: SavePlacement = .keep,
                                 file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try saver.save(article, placement: placement), file: file, line: line) {
            XCTAssertEqual($0 as? LibraryStoreError, .saveFailed, file: file, line: line)
        }
        XCTAssertFalse(env.context.hasChanges, "nothing waits for a later save", file: file, line: line)
    }

    /// A page the library doesn't have (opened in the Reader, its audio warmed): no page is made,
    /// its audio stays ephemeral, and neither a later save nor a relaunch brings the page.
    func testAFailedSaveOfANewPageSavesNothing() throws {
        let article = env.article("https://example.com/new", title: "New")
        cache.markEphemeral(cacheKey: article.id)
        failSaves()

        assertSaveFails(article)
        XCTAssertNil(library.page(key: article.id, canonicalURL: article.origin.canonicalURL), "no page")
        XCTAssertEqual(cache.loadMeta(for: article.id)?.kind, .ephemeral, "its audio isn't marked saved")

        allowSaves()
        try library.makeFolder(name: "Later", in: nil)
        XCTAssertNil(library.page(key: article.id, canonicalURL: article.origin.canonicalURL), "a later save didn't make it")
        try env.relaunch()
        XCTAssertNil(env.library.page(key: article.id, canonicalURL: article.origin.canonicalURL), "nor is it there after a relaunch")
        XCTAssertTrue(env.folders().contains { $0.name == "Later" }, "the later save itself stored")
    }

    /// Save into another folder (⋯ → Save to Folder… on a saved page, *Save to Folder…* on a
    /// favorite link): a saved page stays in its folder, a link stays a link in Favorites, after
    /// a later save and after a relaunch.
    func testAFailedSaveIntoAnotherFolderLeavesThePageWhereItWas() throws {
        let fiction = try library.makeFolder(name: "Fiction", in: nil)
        let essays = try library.makeFolder(name: "Essays", in: nil)
        let story = env.article("https://example.com/story", title: "Story")
        let page = try library.save(story, placement: .folder(fiction))
        let favURL = URL(string: "https://example.com/fav")!
        let link = try XCTUnwrap(library.addFavorite(url: favURL, title: "Fav", artwork: nil))
        let (pageKey, linkKey, fictionID, essaysID) = (try XCTUnwrap(page.key), try XCTUnwrap(link.key), fiction.id, essays.id)
        failSaves()

        assertSaveFails(story, placement: .folder(essays))
        XCTAssertIdentical(page.folder, fiction, "still in Fiction")
        XCTAssertTrue(fiction.pages?.contains { $0 === page } == true, "Fiction lists it")
        XCTAssertTrue(essays.pages?.isEmpty ?? true, "Essays doesn't")

        assertSaveFails(env.article(favURL.absoluteString, title: "Fav"), placement: .folder(essays))
        XCTAssertTrue(link.isLink, "still a link")
        XCTAssertFalse(link.isSaved)
        XCTAssertTrue(LibraryStore.isFavorite(link), "still in Favorites")

        allowSaves()
        try library.rename(essays, to: "Notes")
        try env.relaunch()
        let reopened: LibraryStore = env.library
        XCTAssertEqual(reopened.page(key: pageKey)?.folder?.id, fictionID, "a later save didn't store the move")
        let fav = try XCTUnwrap(reopened.page(key: linkKey))
        XCTAssertTrue(fav.isLink && LibraryStore.isFavorite(fav), "nor the favorite's save")
        let notes = try XCTUnwrap(reopened.folder(id: essaysID))
        XCTAssertEqual(notes.name, "Notes", "the later save itself stored")
        XCTAssertTrue(reopened.pages(in: notes).isEmpty)
    }

    /// A page played but not saved, under an older key than the Reader's: a failed Save leaves it
    /// out of the Library, and the Reader's audio isn't moved under the page's key; once saves
    /// work, the same Save moves it and marks it saved.
    func testAFailedSaveOfAPlayedPageMovesNoAudio() throws {
        let olderKey = UUID()
        let url = "https://example.com/played"
        let played = library.recordPlayback(env.article(url, key: olderKey))
        let article = env.article(url)
        XCTAssertNotEqual(article.id, olderKey)
        cache.markEphemeral(cacheKey: article.id)
        failSaves()

        assertSaveFails(article)
        XCTAssertFalse(played.isInLibrary, "still not in the Library")
        XCTAssertTrue(cache.hasDirectory(for: article.id), "the audio stays under the Reader's key")
        XCTAssertFalse(cache.hasDirectory(for: olderKey), "not moved under the page's")

        allowSaves()
        XCTAssertEqual(try saver.save(article), olderKey, "once saves work, Save files it under the page's key")
        XCTAssertTrue(played.isSavedToLibrary)
        XCTAssertFalse(cache.hasDirectory(for: article.id))
        XCTAssertEqual(cache.loadMeta(for: olderKey)?.kind, .saved)
    }
}
