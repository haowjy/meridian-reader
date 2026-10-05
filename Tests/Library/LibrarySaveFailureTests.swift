import SwiftData
import XCTest
@testable import Reader

/// A library edit whose save fails is rolled back and throws `LibraryStoreError.saveFailed`: the
/// models the screens hold read as before (relationships and order too), nothing waits in the
/// context for a later save, a relaunch finds the old state, and the caller reports no success.
@MainActor
final class LibrarySaveFailureTests: XCTestCase {
    private var env: LibraryTestEnvironment!
    private var library: LibraryStore { env.library }
    private var speech: TestSpeech?

    override func setUp() async throws { env = try LibraryTestEnvironment(fileBacked: true) }
    override func tearDown() async throws {
        speech?.tearDown()
        env.cleanUp()
    }

    private struct SaveFailed: Error {}
    private func failSaves() { library.saveContext = { _ in throw SaveFailed() } }
    private func allowSaves() { library.saveContext = { try $0.save() } }

    // MARK: Fixtures

    /// Fiction (Short stories; a, b, c), Essays (x), Archive, a page in no folder, and Favorites.
    private struct Shelves {
        let fiction, shortStories, essays, archive: Folder
        let a, b, c, x, loose: Page
    }

    private func shelves() throws -> Shelves {
        let fiction = try library.makeFolder(name: "Fiction", in: nil)
        let shortStories = try library.makeFolder(name: "Short stories", in: fiction)
        let essays = try library.makeFolder(name: "Essays", in: nil)
        let archive = try library.makeFolder(name: "Archive", in: nil)
        library.favorites()
        func saved(_ path: String, in folder: Folder?) -> Page {
            library.save(env.article("https://example.com/\(path)", title: path), placement: .folder(folder))
        }
        return Shelves(fiction: fiction, shortStories: shortStories, essays: essays, archive: archive,
                       a: saved("a", in: fiction), b: saved("b", in: fiction), c: saved("c", in: fiction),
                       x: saved("x", in: essays), loose: saved("loose", in: nil))
    }

    /// Every folder and page as the models read: placement, order, marks and names.
    private struct Snapshot: Equatable {
        struct FolderState: Equatable {
            var name: String
            var parent: UUID?
            var sortKey: Double
            var sort: String
            var finishedAt: Date?
            var children: Set<UUID>
            var pages: Set<UUID>
        }

        struct PageState: Equatable {
            var title: String
            var folder: UUID?
            var folderID: UUID?
            var sortKey: Double
            var state: String
            var addedAt: Date?
            var finishedAt: Date?
            var skips: Bool
        }

        var folders: [UUID: FolderState] = [:]
        var pages: [UUID: PageState] = [:]
    }

    private func snapshot() -> Snapshot {
        var shot = Snapshot()
        for f in env.folders() {
            shot.folders[f.id] = .init(name: f.name, parent: f.parent?.id, sortKey: f.sortKey, sort: f.pageSortRaw,
                                       finishedAt: f.finishedAt, children: Set((f.children ?? []).map(\.id)),
                                       pages: Set((f.pages ?? []).compactMap(\.key)))
        }
        for p in env.pages() {
            guard let key = p.key else { continue }
            shot.pages[key] = .init(title: p.title, folder: p.folder?.id, folderID: p.folderID, sortKey: p.sortKey,
                                    state: p.contentStateRaw, addedAt: p.addedAt, finishedAt: p.finishedAt,
                                    skips: p.skipsInPlayback)
        }
        return shot
    }

    private func titles(in folder: Folder) -> [String] { library.pages(in: folder).map(\.title) }

    private func contains(_ folder: Folder, _ page: Page) -> Bool { folder.pages?.contains { $0 === page } == true }

    private func moveRequest(_ shell: ShellState, file: StaticString = #filePath, line: UInt = #line) throws -> MoveRequest {
        guard case .moveTo(let request) = shell.sheet else {
            XCTFail("the Move tree is up", file: file, line: line)
            throw SaveFailed()
        }
        return request
    }

    // MARK: The store

    /// One page from Fiction to Essays: the move throws, the page the screen holds is back in
    /// Fiction at its place (both folders' page lists agree), nothing is left for a later save,
    /// and a relaunch after one finds it in Fiction.
    func testASingleMoveWhoseSaveFailsLeavesThePageWhereItWas() throws {
        let s = try shelves()
        let sortKey = s.b.sortKey
        let before = snapshot()
        failSaves()

        XCTAssertThrowsError(try library.move([.page(s.b)], to: s.essays)) {
            XCTAssertEqual($0 as? LibraryStoreError, .saveFailed)
        }
        XCTAssertIdentical(s.b.folder, s.fiction, "the page the screen holds is back in Fiction")
        XCTAssertEqual(s.b.folderID, s.fiction.id)
        XCTAssertEqual(s.b.sortKey, sortKey, "at its place")
        XCTAssertTrue(contains(s.fiction, s.b), "Fiction lists it")
        XCTAssertFalse(contains(s.essays, s.b), "Essays doesn't")
        XCTAssertFalse(env.context.hasChanges, "nothing waits for a later save")
        XCTAssertEqual(titles(in: s.fiction), ["a", "b", "c"])
        XCTAssertEqual(titles(in: s.essays), ["x"])
        XCTAssertEqual(snapshot(), before)

        allowSaves()
        try library.rename(s.archive, to: "Old")
        let (fictionID, archiveID, bKey) = (s.fiction.id, s.archive.id, try XCTUnwrap(s.b.key))
        try env.relaunch()
        let fiction = try XCTUnwrap(library.folder(id: fictionID))
        XCTAssertEqual(library.page(key: bKey)?.folder?.id, fictionID, "a later save didn't store the move")
        XCTAssertEqual(titles(in: fiction), ["a", "b", "c"])
        XCTAssertEqual(library.folder(id: archiveID)?.name, "Old", "the later save itself stored")
    }

    /// Edit's Move of folders and pages together, from two places: every item is back where it
    /// was, in its order, in memory and after a relaunch.
    func testABatchMoveWhoseSaveFailsLeavesEveryItemInItsPlaceAndOrder() throws {
        let s = try shelves()
        let topLevel = library.topLevelFolders().map(\.name)
        let before = snapshot()
        failSaves()

        XCTAssertThrowsError(try library.move([.folder(s.shortStories), .page(s.a), .page(s.c), .folder(s.archive), .page(s.loose)],
                                              to: s.essays)) {
            XCTAssertEqual($0 as? LibraryStoreError, .saveFailed)
        }
        XCTAssertIdentical(s.shortStories.parent, s.fiction)
        XCTAssertNil(s.archive.parent)
        XCTAssertNil(s.loose.folder)
        XCTAssertIdentical(s.a.folder, s.fiction)
        XCTAssertIdentical(s.c.folder, s.fiction)
        XCTAssertTrue(s.fiction.children?.contains { $0 === s.shortStories } == true, "Fiction still lists its subfolder")
        XCTAssertTrue(s.essays.children?.isEmpty ?? true, "Essays gained no subfolder")
        XCTAssertTrue(contains(s.fiction, s.a) && contains(s.fiction, s.c))
        XCTAssertEqual(s.essays.pages?.count, 1)
        XCTAssertFalse(env.context.hasChanges)
        XCTAssertEqual(titles(in: s.fiction), ["a", "b", "c"])
        XCTAssertEqual(library.topLevelFolders().map(\.name), topLevel)
        XCTAssertEqual(snapshot(), before)

        allowSaves()
        let fictionID = s.fiction.id
        try env.relaunch()
        XCTAssertEqual(snapshot(), before, "nothing reached the store")
        let fiction = try XCTUnwrap(library.folder(id: fictionID))
        XCTAssertEqual(library.subfolders(of: fiction).map(\.name), ["Short stories"])
        XCTAssertEqual(titles(in: fiction), ["a", "b", "c"])
        XCTAssertEqual(library.topLevelFolders().map(\.name), topLevel)
    }

    /// The rest of the Library's edits: each throws, changes nothing, leaves nothing for a later
    /// save, and a relaunch finds the library as it was.
    func testEveryOtherLibraryEditWhoseSaveFailsThrowsAndChangesNothing() throws {
        let s = try shelves()
        let favorite = try XCTUnwrap(library.addFavorite(url: URL(string: "https://example.com/fav")!, title: "Fav", artwork: nil))
        let book = Folder(name: "Novel", kind: .book)
        env.context.insert(book)
        let chapters = try (1...3).map {
            try library.addLink(url: URL(string: "https://example.com/novel/\($0)")!, title: "Ch \($0)", artwork: nil, in: book)
        }
        let before = snapshot()
        failSaves()

        let edits: [(String, () throws -> Void)] = [
            ("New Folder", { _ = try self.library.makeFolder(name: "New", in: s.fiction) }),
            ("Rename", { try self.library.rename(s.fiction, to: "Novels") }),
            ("Sort", { try self.library.setSort(.title, for: s.fiction) }),
            ("reorder pages", { try self.library.reorder([s.c], in: s.fiction, before: s.a) }),
            ("reorder folders", { try self.library.reorderFolders([s.archive], in: nil, before: s.fiction) }),
            ("Mark as Finished", { try self.library.setFinished([s.a, s.x, chapters[0]], true) }),
            ("Mark All Above as Finished", { try self.library.markAllAbove(chapters[2]) }),
            ("Skip in Playback", { try self.library.setSkipsInPlayback(chapters[0], true) }),
            ("Remove from Library", { try self.library.remove(s.loose) }),
            ("Remove a link", { try self.library.remove(favorite) }),
            ("unsave", { try self.library.unsave(s.x) }),
            ("☆ a new page", { _ = try self.library.addFavorite(url: URL(string: "https://example.com/new")!, title: nil, artwork: nil) }),
            ("☆ a saved page", { _ = try self.library.addFavorite(url: try XCTUnwrap(s.loose.url), title: nil, artwork: nil) }),
            ("Remove from Favorites", { try self.library.removeFavorite(favorite) }),
            ("Rename a favorite", { try self.library.renameFavorite(favorite, to: "Renamed") }),
            ("Delete Folder Only", { try self.library.deleteFolders([s.fiction], keepContents: true) }),
            ("Delete Folder and Contents", { try self.library.deleteFolders([s.essays], keepContents: false) }),
        ]
        for (name, edit) in edits {
            XCTAssertThrowsError(try edit(), name) { XCTAssertEqual($0 as? LibraryStoreError, .saveFailed, name) }
            XCTAssertFalse(env.context.hasChanges, "\(name): nothing waits for a later save")
            XCTAssertEqual(snapshot(), before, "\(name) changed nothing")
        }
        XCTAssertNil(s.loose.folder)
        XCTAssertTrue(s.x.isSaved)
        XCTAssertFalse(favorite.isDeleted)

        allowSaves()
        try env.relaunch()
        XCTAssertEqual(snapshot(), before, "nothing reached the store")
    }

    // MARK: The callers

    /// The Move tree (a row's *Move to…*, Edit's *Move…*, ⋯ → *Move…*): a move that wasn't saved
    /// isn't reported as done (Edit keeps its selection, a folder's own screen doesn't follow it)
    /// and a toast says so; once saves work, the same move is.
    func testTheMoveTreeReportsAMoveOnlyOnceItIsSaved() throws {
        let s = try shelves()
        let test = TestSpeech()
        speech = test
        let shell = ShellState()
        let actions = LibraryActions(library: library, speech: test.speech, shell: shell)
        var moved = 0

        actions.move([.folder(s.shortStories), .page(s.a)]) { moved += 1 }
        let failing = try moveRequest(shell)
        failSaves()
        failing.onPick(s.essays)
        XCTAssertEqual(moved, 0, "a move that wasn't saved isn't reported as done")
        XCTAssertEqual(shell.toast?.message, "Couldn’t move")
        XCTAssertIdentical(s.shortStories.parent, s.fiction)
        XCTAssertIdentical(s.a.folder, s.fiction)

        allowSaves()
        shell.dismissToast(try XCTUnwrap(shell.toast?.id))
        actions.move([.folder(s.shortStories), .page(s.a)]) { moved += 1 }
        try moveRequest(shell).onPick(s.essays)
        XCTAssertEqual(moved, 1)
        XCTAssertNil(shell.toast, "no failure this time")
        XCTAssertIdentical(s.shortStories.parent, s.essays)
        XCTAssertIdentical(s.a.folder, s.essays)
    }

    /// Marks and Remove from the rows and Edit's bar: false (Edit keeps its selection) and a
    /// toast when the save fails.
    func testRowEditsReportFailure() throws {
        let s = try shelves()
        let test = TestSpeech()
        speech = test
        let shell = ShellState()
        let actions = LibraryActions(library: library, speech: test.speech, shell: shell)
        failSaves()

        XCTAssertFalse(actions.setFinished([s.a, s.b], true))
        XCTAssertEqual(shell.toast?.message, "Couldn’t mark as finished")
        XCTAssertNil(s.a.finishedAt)
        XCTAssertFalse(actions.remove([s.loose, s.x]))
        XCTAssertEqual(shell.toast?.message, "Couldn’t remove")
        XCTAssertTrue(s.loose.isInLibrary)

        allowSaves()
        XCTAssertTrue(actions.setFinished([s.a], true))
        XCTAssertNotNil(s.a.finishedAt)
    }

    /// ☆'s moves (*Move Book to Favorites*, *Change Folder*) and ☆ itself: a failed save shows
    /// "Couldn’t …" in place of the success toast, and nothing moved.
    func testFavoritesSayAFailedSaveInsteadOfSuccess() throws {
        let s = try shelves()
        let shell = ShellState()
        let flow = FavoriteFlow(library: library, shell: shell)
        let book = Folder(name: "Novel", kind: .book)
        env.context.insert(book)
        let chapterURL = URL(string: "https://example.com/novel/1")!
        try library.addLink(url: chapterURL, title: "Ch 1", artwork: nil, in: book)

        flow.toggle(url: chapterURL, title: nil, artwork: nil) { nil }
        let moveBook = try XCTUnwrap(shell.prompt, "☆ on a chapter offers to move the book")
        failSaves()
        moveBook.confirm()
        XCTAssertEqual(shell.toast?.message, "Couldn’t move")
        XCTAssertNil(book.parent, "the book stays at the top level")

        let newURL = URL(string: "https://example.com/new")!
        flow.toggle(url: newURL, title: "New", artwork: nil) { nil }
        XCTAssertEqual(shell.toast?.message, "Couldn’t add to Favorites")
        XCTAssertNil(library.page(url: newURL))

        allowSaves()
        flow.toggle(url: newURL, title: "New", artwork: nil) { nil }
        XCTAssertEqual(shell.toast?.message, "Added to Favorites")
        let added = try XCTUnwrap(library.page(url: newURL))
        try XCTUnwrap(shell.toast?.action, "the toast offers Change Folder")()
        let changeFolder = try moveRequest(shell)
        failSaves()
        changeFolder.onPick(s.essays)
        XCTAssertEqual(shell.toast?.message, "Couldn’t move")
        XCTAssertIdentical(added.folder, library.favorites(), "still in Favorites")

        flow.toggle(url: newURL, title: nil, artwork: nil) { nil }
        XCTAssertEqual(shell.toast?.message, "Couldn’t remove from Favorites")
        XCTAssertTrue(LibraryStore.isFavorite(added))
    }
}
