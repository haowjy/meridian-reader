import SwiftData
import XCTest
@testable import MeridianReader

/// A library edit whose save fails is rolled back and throws `LibraryStoreError.saveFailed`: the
/// models the screens hold read as before (relationships and order too), nothing waits in the
/// context for a later save, a relaunch finds the old state, and the caller reports no success:
/// the Move tree stays up, and Edit keeps its selection.
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

    /// Fiction (Short stories; a, b, c), Essays (x), Archive, and a page in no folder.
    private struct Shelves {
        let fiction, shortStories, essays, archive: Folder
        let a, b, c, x, loose: Page
    }

    private func shelves() throws -> Shelves {
        let fiction = try library.makeFolder(name: "Fiction", in: nil)
        let shortStories = try library.makeFolder(name: "Short stories", in: fiction)
        let essays = try library.makeFolder(name: "Essays", in: nil)
        let archive = try library.makeFolder(name: "Archive", in: nil)
        func saved(_ path: String, in folder: Folder?) throws -> Page {
            try library.save(env.article("https://example.com/\(path)", title: path), placement: .folder(folder))
        }
        return Shelves(fiction: fiction, shortStories: shortStories, essays: essays, archive: archive,
                       a: try saved("a", in: fiction), b: try saved("b", in: fiction), c: try saved("c", in: fiction),
                       x: try saved("x", in: essays), loose: try saved("loose", in: nil))
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
            ("reorder pages", { try self.library.arrange([s.c], in: s.fiction, before: s.a, shownIn: .manual) }),
            ("reorder folders", { try self.library.arrange([s.archive], in: nil, before: s.fiction) }),
            ("Mark as Finished", { try self.library.setFinished([s.a, s.x, chapters[0]], true) }),
            ("Mark All Above as Finished", { try self.library.markAllAbove(chapters[2]) }),
            ("Skip in Playback", { try self.library.setSkipsInPlayback(chapters[0], true) }),
            ("Remove from Library", { try self.library.remove([s.loose]) }),
            ("Remove a link", { try self.library.remove([favorite]) }),
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

    /// A book played while saves fail: chapter 1 starts and finishes, then chapter 2 starts and
    /// moves on. A failed edit's rollback drops all of it; it is written again with the dates it
    /// was made at and in the order it played, so the book's place is chapter 2, chapter 1 stays
    /// finished and the book doesn't. Once saves work the next save stores it; the edit stays
    /// undone.
    func testABooksListeningIsWrittenAgainAfterARollbackInTheOrderItPlayed() throws {
        let book = Folder(name: "Book", kind: .book)
        env.context.insert(book)
        let urls = ["https://example.com/ch1", "https://example.com/ch2"]
        let chapters = try urls.map { try library.addLink(url: URL(string: $0)!, title: $0, artwork: nil, in: book) }
        for url in urls { try library.save(env.article(url)) }
        let (one, two) = (chapters[0], chapters[1])
        let (oneKey, twoKey) = (try XCTUnwrap(one.key), try XCTUnwrap(two.key))
        let start = env.now
        failSaves()
        library.recordPlaybackStarted(one)
        env.now = start.addingTimeInterval(60)
        library.recordFinished(one)
        env.now = start.addingTimeInterval(61)
        library.recordPlaybackStarted(two)
        library.recordPosition(two, paragraph: 1, utf16Offset: 3)

        env.now = start.addingTimeInterval(120)
        XCTAssertThrowsError(try library.makeFolder(name: "Later", in: nil))
        func check(_ library: LibraryStore, _ when: String) throws {
            let book = try XCTUnwrap(library.page(key: oneKey)?.folder, when)
            XCTAssertEqual(book.currentPageKey, twoKey, "\(when): the chapter that started last is the place")
            XCTAssertEqual(book.lastPlayedAt, start.addingTimeInterval(61), when)
            XCTAssertNil(book.finishedAt, "\(when): a chapter is still to play")
            XCTAssertEqual(library.page(key: oneKey)?.finishedAt, start.addingTimeInterval(60), when)
            let two = try XCTUnwrap(library.page(key: twoKey), when)
            XCTAssertEqual(two.lastPlayedAt, start.addingTimeInterval(61), when)
            XCTAssertNil(two.finishedAt, when)
            XCTAssertEqual(two.positionParagraph, 1, when)
            XCTAssertEqual(two.positionUTF16, 3, when)
        }
        try check(library, "after the rollback")

        allowSaves()
        library.commit("next")
        try env.relaunch()
        try check(env.library, "after a relaunch")
        XCTAssertFalse(env.folders().contains { $0.name == "Later" }, "the failed edit stays undone")
    }

    /// *Mark as Finished* and *Mark as Unfinished* whose saves fail, on pages played while saves
    /// fail: each mark stays undone, and the listening written before it is written again (one
    /// page at its spot and unfinished, the other finished). Once saves work the next save stores
    /// that listening, and a relaunch agrees; neither mark reached the store.
    func testMarksThatFailKeepTheListeningWrittenBeforeThem() throws {
        let a = try library.save(env.article("https://example.com/a"))
        let b = try library.save(env.article("https://example.com/b"))
        let (aKey, bKey) = (try XCTUnwrap(a.key), try XCTUnwrap(b.key))
        let start = env.now
        failSaves()
        library.recordPlaybackStarted(a)
        library.recordPosition(a, paragraph: 1, utf16Offset: 4)
        env.now = start.addingTimeInterval(30)
        library.recordPlaybackStarted(b)
        env.now = start.addingTimeInterval(90)
        library.recordFinished(b)

        env.now = start.addingTimeInterval(120)
        XCTAssertThrowsError(try library.setFinished([a], true), "Mark as Finished")
        XCTAssertThrowsError(try library.setFinished([b], false), "Mark as Unfinished")
        func check(_ library: LibraryStore, _ when: String) throws {
            let a = try XCTUnwrap(library.page(key: aKey), when)
            XCTAssertNil(a.finishedAt, "\(when): Mark as Finished stays undone")
            XCTAssertEqual(a.lastPlayedAt, start, when)
            XCTAssertEqual(a.positionParagraph, 1, when)
            XCTAssertEqual(a.positionUTF16, 4, when)
            let b = try XCTUnwrap(library.page(key: bKey), when)
            XCTAssertEqual(b.finishedAt, start.addingTimeInterval(90), "\(when): Mark as Unfinished stays undone")
            XCTAssertEqual(b.lastPlayedAt, start.addingTimeInterval(90), when)
        }
        try check(library, "after the rollbacks")

        allowSaves()
        library.commit("next")
        try env.relaunch()
        try check(env.library, "after a relaunch")
    }

    /// Continue on a finished book restarts it while saves fail: the restart's own save fails,
    /// its first chapter starts, then a failed edit rolls everything back. The book stays
    /// restarted: unfinished, its place the first chapter, which is unfinished and dated; the
    /// second chapter stays finished. Once saves work it is stored, and a relaunch agrees.
    func testABookRestartedWhileSavesFailStaysRestartedThroughARollback() throws {
        let book = Folder(name: "Book", kind: .book)
        env.context.insert(book)
        let urls = ["https://example.com/ch1", "https://example.com/ch2"]
        let chapters = try urls.map { try library.addLink(url: URL(string: $0)!, title: $0, artwork: nil, in: book) }
        for url in urls { try library.save(env.article(url)) }
        try library.setFinished(chapters, true)
        XCTAssertNotNil(book.finishedAt, "finished: every chapter is")
        let (oneKey, twoKey) = (try XCTUnwrap(chapters[0].key), try XCTUnwrap(chapters[1].key))
        env.now = env.now.addingTimeInterval(600)
        let restarted = env.now
        failSaves()

        let start = try XCTUnwrap(library.continueStart(of: book), "Continue on the finished book")
        XCTAssertEqual(start.page.key, oneKey, "starts again at its first chapter")
        XCTAssertNil(book.finishedAt)
        library.recordPlaybackStarted(start.page)
        env.now = restarted.addingTimeInterval(60)
        XCTAssertThrowsError(try library.makeFolder(name: "Later", in: nil))
        func check(_ library: LibraryStore, _ when: String) throws {
            let one = try XCTUnwrap(library.page(key: oneKey), when)
            let book = try XCTUnwrap(one.folder, when)
            XCTAssertNil(book.finishedAt, "\(when): the book is listened to again")
            XCTAssertEqual(book.currentPageKey, oneKey, "\(when): its place is the first chapter")
            XCTAssertEqual(book.lastPlayedAt, restarted, when)
            XCTAssertNil(one.finishedAt, when)
            XCTAssertEqual(one.lastPlayedAt, restarted, when)
            XCTAssertNotNil(library.page(key: twoKey)?.finishedAt, "\(when): the second chapter stays finished")
        }
        try check(library, "after the rollback")

        allowSaves()
        library.commit("next")
        try env.relaunch()
        try check(env.library, "after a relaunch")
        XCTAssertFalse(env.folders().contains { $0.name == "Later" }, "the failed edit stays undone")
    }

    // MARK: The callers

    private func actions(_ shell: ShellState) -> LibraryActions {
        let test = speech ?? TestSpeech()
        speech = test
        return LibraryActions(library: library, speech: test.speech, shell: shell)
    }

    /// The Move tree (a row's *Move to…*, Edit's *Move…*, ⋯ → *Move…*): a move that wasn't saved
    /// isn't reported as done (Edit keeps its selection, a folder's own screen doesn't follow it),
    /// the tree stays up and a toast says so; once saves work, the same pick moves them and closes
    /// the tree.
    func testTheMoveTreeReportsAMoveOnlyOnceItIsSaved() throws {
        let s = try shelves()
        let shell = ShellState()
        let actions = actions(shell)
        var moved = 0

        actions.move([.folder(s.shortStories), .page(s.a)]) { moved += 1 }
        let request = try moveRequest(shell)
        failSaves()
        request.pick(s.essays, shell: shell)
        XCTAssertEqual(moved, 0, "a move that wasn't saved isn't reported as done")
        XCTAssertEqual(shell.toast?.message, "Couldn’t move")
        XCTAssertEqual(shell.sheet, .moveTo(request), "the tree stays up")
        XCTAssertIdentical(s.shortStories.parent, s.fiction)
        XCTAssertIdentical(s.a.folder, s.fiction)

        allowSaves()
        shell.dismissToast(try XCTUnwrap(shell.toast?.id))
        request.pick(s.essays, shell: shell)
        XCTAssertEqual(moved, 1)
        XCTAssertNil(shell.toast, "no failure this time")
        XCTAssertNil(shell.sheet, "the tree closes once the move is saved")
        XCTAssertIdentical(s.shortStories.parent, s.essays)
        XCTAssertIdentical(s.a.folder, s.essays)
    }

    /// The Move tree's *New Folder*: a folder that can't be saved files nothing and leaves the
    /// tree up under its toast; once saves work, the folder is made, what is filed goes in, and
    /// the tree closes.
    func testTheMoveTreeStaysUpWhenItsNewFolderCantBeSaved() throws {
        let s = try shelves()
        let shell = ShellState()
        let actions = actions(shell)
        var moved = 0
        let folders = env.folders().count

        actions.move([.page(s.a)]) { moved += 1 }
        let request = try moveRequest(shell)
        failSaves()
        request.pickNewFolder(named: "Drafts", in: s.essays, library: library, shell: shell)
        XCTAssertEqual(shell.toast?.message, "Couldn’t make the folder")
        XCTAssertEqual(shell.sheet, .moveTo(request), "the tree stays up")
        XCTAssertEqual(env.folders().count, folders, "no folder made")
        XCTAssertEqual(moved, 0)
        XCTAssertIdentical(s.a.folder, s.fiction)

        allowSaves()
        request.pickNewFolder(named: "Drafts", in: s.essays, library: library, shell: shell)
        XCTAssertNil(shell.sheet, "closed once filed")
        XCTAssertEqual(s.a.folder?.name, "Drafts")
        XCTAssertIdentical(s.a.folder?.parent, s.essays)
        XCTAssertEqual(moved, 1)
    }

    /// Marks and Remove from the rows and Edit's bar: false and a toast when the save fails.
    func testRowEditsReportFailure() throws {
        let s = try shelves()
        let shell = ShellState()
        let actions = actions(shell)
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

    /// Remove of several pages is one save: when it fails on the second page (a save the first
    /// page's removal alone would have passed), none is removed, in memory or after a relaunch,
    /// nothing waits for a later save, and their audio stays saved; once saves work, all go and
    /// their audio turns ephemeral.
    func testABatchRemoveThatFailsPartWayRemovesNone() throws {
        let s = try shelves()
        let link = try library.addLink(url: URL(string: "https://example.com/link")!, title: "Link", artwork: nil, in: s.essays)
        let (aKey, xKey, linkKey) = (try XCTUnwrap(s.a.key), try XCTUnwrap(s.x.key), try XCTUnwrap(link.key))
        for key in [aKey, xKey] { try env.storeAudio(key, paragraphs: ["One.", "Two."]) }
        env.cache.markSaved(cacheKey: aKey)
        env.cache.markSaved(cacheKey: xKey)
        let before = snapshot()
        let shell = ShellState()
        let actions = actions(shell)
        // Refuses only a save that carries x's change: removing page by page, a's save would pass.
        library.saveContext = { context in
            if context.changedModelsArray.contains(where: { ($0 as? Page)?.key == xKey }) { throw SaveFailed() }
            try context.save()
        }

        XCTAssertFalse(actions.remove([s.a, link, s.x]))
        XCTAssertEqual(shell.toast?.message, "Couldn’t remove")
        XCTAssertIdentical(s.a.folder, s.fiction, "a stays in Fiction")
        XCTAssertTrue(s.a.isInLibrary)
        XCTAssertFalse(link.isDeleted)
        XCTAssertFalse(env.context.hasChanges, "nothing waits for a later save")
        XCTAssertEqual(snapshot(), before)
        XCTAssertEqual(env.cache.loadMeta(for: aKey)?.kind, .saved, "a's audio is still saved")
        XCTAssertEqual(try env.context.fetchCount(FetchDescriptor<LibraryAudioWork>()), 0, "no audio work recorded")

        allowSaves()
        try library.rename(s.archive, to: "Old")
        let fictionID = s.fiction.id
        try env.relaunch()
        XCTAssertEqual(snapshot().pages, before.pages, "a later save didn't store any of it")
        XCTAssertEqual(library.page(key: aKey)?.folder?.id, fictionID)
        XCTAssertNotNil(library.page(key: linkKey))

        let shell2 = ShellState()
        let pages = try [aKey, linkKey, xKey].map { try XCTUnwrap(library.page(key: $0)) }
        XCTAssertTrue(self.actions(shell2).remove(pages))
        XCTAssertNil(shell2.toast)
        XCTAssertFalse(pages[0].isInLibrary)
        XCTAssertFalse(pages[2].isInLibrary)
        XCTAssertNil(library.page(key: linkKey), "a link never played is deleted")
        XCTAssertEqual(env.cache.loadMeta(for: aKey)?.kind, .ephemeral, "their audio turns ephemeral once saved")
        XCTAssertEqual(env.cache.loadMeta(for: xKey)?.kind, .ephemeral)
        XCTAssertEqual(try env.context.fetchCount(FetchDescriptor<LibraryAudioWork>()), 0, "the audio work is done and retired")
    }

    // MARK: Edit's Remove and the delete question

    private func editing(_ items: [LibraryItemID]) -> LibraryScreenState {
        let screen = LibraryScreenState()
        screen.beginEditing(folderID: UUID())
        screen.selection = Set(items)
        return screen
    }

    /// What the delete question's choice does (`libraryDialogs`): the folders waiting for it are
    /// taken off the question, then deleted.
    @discardableResult
    private func answerDelete(_ screen: LibraryScreenState, _ actions: LibraryActions) -> Bool {
        let folders = screen.pendingDelete
        screen.pendingDelete = []
        return actions.deleteFolders(folders, in: screen)
    }

    /// Edit → a page and a folder → Remove: the page goes and leaves the selection; the folder
    /// waits for the delete question, still selected. Cancelling keeps it selected; a delete that
    /// can't be saved keeps it, its folder and Edit, and Remove asks again; once saved, Edit ends.
    func testEditKeepsTheFoldersSelectedUntilTheirDeleteIsSaved() throws {
        let s = try shelves()
        let shell = ShellState()
        let actions = actions(shell)
        let archive = LibraryItemID.folder(s.archive.id)
        let screen = editing([archive, .page(try XCTUnwrap(s.loose.key))])

        actions.removeSelection(of: screen)
        XCTAssertFalse(s.loose.isInLibrary, "the page is removed")
        XCTAssertEqual(screen.selection, [archive], "only the folder stays selected")
        XCTAssertEqual(screen.pendingDelete.map(\.id), [s.archive.id], "the delete question")

        screen.cancelDelete()
        XCTAssertTrue(screen.pendingDelete.isEmpty)
        XCTAssertEqual(screen.selection, [archive], "cancelling keeps the selection")
        XCTAssertTrue(screen.isEditing)

        actions.removeSelection(of: screen)
        XCTAssertEqual(screen.pendingDelete.map(\.id), [s.archive.id], "Remove asks again")
        failSaves()
        XCTAssertFalse(answerDelete(screen, actions))
        XCTAssertEqual(shell.toast?.message, "Couldn’t delete")
        XCTAssertNotNil(library.folder(id: s.archive.id), "the folder stays")
        XCTAssertEqual(screen.selection, [archive], "a delete that wasn't saved keeps the selection")
        XCTAssertTrue(screen.isEditing, "and Edit")

        allowSaves()
        actions.removeSelection(of: screen)
        XCTAssertTrue(answerDelete(screen, actions))
        XCTAssertNil(library.folder(id: s.archive.id))
        XCTAssertFalse(screen.isEditing, "Edit ends once the delete is saved")
        XCTAssertTrue(screen.selection.isEmpty)
    }

    /// Edit → pages and a folder → Remove, when the pages can't be removed: nothing changes, the
    /// selection stays whole, and no delete question is asked.
    func testEditKeepsItsWholeSelectionWhenItsPagesCantBeRemoved() throws {
        let s = try shelves()
        let shell = ShellState()
        let actions = actions(shell)
        let items: [LibraryItemID] = [.folder(s.archive.id), .page(try XCTUnwrap(s.a.key)), .page(try XCTUnwrap(s.b.key))]
        let screen = editing(items)
        failSaves()

        actions.removeSelection(of: screen)
        XCTAssertEqual(shell.toast?.message, "Couldn’t remove")
        XCTAssertEqual(screen.selection, Set(items))
        XCTAssertTrue(screen.pendingDelete.isEmpty, "nothing asked")
        XCTAssertTrue(s.a.isInLibrary && s.b.isInLibrary)
        XCTAssertTrue(screen.isEditing)
    }

    /// ☆ sets only the favorite flag, including on a book chapter: a failed save shows "Couldn’t
    /// …" in place of the success toast, and neither the flag nor the row's location changes.
    func testFavoritesSayAFailedSaveInsteadOfSuccess() throws {
        let s = try shelves()
        let shell = ShellState()
        let flow = FavoriteFlow(library: library, shell: shell)
        let book = Folder(name: "Novel", kind: .book)
        env.context.insert(book)
        let chapterURL = URL(string: "https://example.com/novel/1")!
        let chapter = try library.addLink(url: chapterURL, title: "Ch 1", artwork: nil, in: book)

        failSaves()
        flow.toggle(url: chapterURL, title: nil, artwork: nil) { nil }
        XCTAssertEqual(shell.toast?.message, "Couldn’t add to Favorites")
        XCTAssertIdentical(chapter.folder, book, "the chapter stays in its book")
        XCTAssertFalse(chapter.isFavorite)

        let newURL = URL(string: "https://example.com/new")!
        flow.toggle(url: newURL, title: "New", artwork: nil) { nil }
        XCTAssertEqual(shell.toast?.message, "Couldn’t add to Favorites")
        XCTAssertNil(library.page(url: newURL))

        allowSaves()
        flow.toggle(url: newURL, title: "New", artwork: nil) { nil }
        XCTAssertEqual(shell.toast?.message, "Added to Favorites")
        let added = try XCTUnwrap(library.page(url: newURL))
        XCTAssertNil(shell.toast?.action, "moving is a separate Save to Folder action")
        actions(shell).move([.page(added)])
        let changeFolder = try moveRequest(shell)
        failSaves()
        changeFolder.pick(s.essays, shell: shell)
        XCTAssertEqual(shell.toast?.message, "Couldn’t move")
        XCTAssertEqual(shell.sheet, .moveTo(changeFolder), "the tree stays up")
        XCTAssertNil(added.folder, "Move to Folder remains an explicit, separate action")

        flow.toggle(url: newURL, title: nil, artwork: nil) { nil }
        XCTAssertEqual(shell.toast?.message, "Couldn’t remove from Favorites")
        XCTAssertTrue(LibraryStore.isFavorite(added))
    }
}
