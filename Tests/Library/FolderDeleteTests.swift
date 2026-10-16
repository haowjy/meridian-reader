import SwiftData
import XCTest
@testable import MeridianReader

/// *Delete Folder and Contents* on a full folder while a chapter inside it plays, with the app's
/// pieces wired as `AppComposition` wires them (the real `SpeechController`): the folder, its
/// pages, its subfolders and the book inside with its chapters go in one save, with their audio;
/// nothing outside it changes and nothing is left pointing into what went; playback stops and
/// doesn't carry on; the Library's path leaves the deleted screens; and every deleted model reads
/// as no longer live, which the Library's rows and screens check before reading one (`isLive`).
@MainActor
final class FolderDeleteTests: XCTestCase {
    private var fixture: TestSpeech!
    private var env: LibraryTestEnvironment!
    private var speech: SpeechController { fixture.speech }
    private var library: LibraryStore { env.library }

    override func setUp() async throws {
        fixture = TestSpeech()
        env = try LibraryTestEnvironment()
        // As `AppComposition` wires them.
        library.stopPlaybackIfPlaying = { [unowned self] key in
            if speech.activeSessionID == key { speech.stop() }
        }
        speech.nextChapters = env.library
    }

    override func tearDown() async throws {
        fixture.tearDown()
        env.cleanUp()
    }

    private func saved(_ path: String, in folder: Folder?) throws -> Page {
        try library.save(env.article("https://example.com/\(path)", title: path), placement: .folder(folder))
    }

    /// A row's ▶, as `LibraryActions.play` does it: the page plays, carrying on through its folder.
    private func play(_ page: Page) {
        speech.press(.page(page.listenKey)) {
            speech.start(.page(page))
        }
    }

    func testDeletingAFullFolderWhileAChapterInsidePlays() throws {
        // Shelf: two pages, Nested (a page, and the empty Deeper), and a book with two chapters.
        let shelf = try library.makeFolder(name: "Shelf", in: nil)
        let nested = try library.makeFolder(name: "Nested", in: shelf)
        let deeper = try library.makeFolder(name: "Deeper", in: nested)
        let book = Folder(name: "Book", kind: .book)
        env.context.insert(book)
        book.parent = shelf
        let inside = [try saved("p1", in: shelf), try saved("p2", in: shelf), try saved("n1", in: nested),
                      try saved("c1", in: book), try saved("c2", in: book)]
        // Outside it: a page in no folder, and another folder with a page.
        let other = try library.makeFolder(name: "Other", in: nil)
        let outside = [try saved("loose", in: nil), try saved("elsewhere", in: other)]
        let insideKeys = inside.compactMap(\.key)
        let outsideKeys = outside.compactMap(\.key)
        XCTAssertEqual(insideKeys.count, 5)
        for page in inside + outside {
            try env.storeAudio(XCTUnwrap(page.key), paragraphs: page.cachedListenParagraphs ?? [])
        }
        XCTAssertEqual(library.contents(of: shelf).folders, 3, "Nested, Deeper and the book")
        XCTAssertEqual(library.contents(of: shelf).pages, 5)

        let chapter = inside[3]
        play(chapter)
        XCTAssertEqual(speech.activeSessionID, chapter.listenKey, "the book's first chapter plays")
        XCTAssertNotNil(speech.nowPlaying)
        let shell = ShellState()
        shell.libraryPath = [.folder(shelf.id), .folder(book.id)]

        try library.deleteFolders([shelf])
        shell.pruneLibraryPath { library.folder(id: $0) != nil }

        // Playback stopped, the bar has nothing to show, and the chapter's end carries nothing on
        // into the deleted book.
        XCTAssertNil(speech.activeSessionID, "the playing chapter stopped")
        XCTAssertNil(speech.nowPlaying)
        XCTAssertEqual(speech.playbackPhase, .idle)
        fixture.apple.emit(.finished)
        XCTAssertNil(speech.activeSessionID, "nothing carries on into the deleted book")

        // The store holds what was outside, as it was, and nothing pointing into what went.
        let folders = env.folders()
        let pages = env.pages()
        XCTAssertEqual(Set(folders.filter { $0.kind != .favorites }.map(\.name)), ["Other"])
        XCTAssertEqual(Set(pages.compactMap(\.key)), Set(outsideKeys))
        let folderIDs = Set(folders.map(\.id))
        for page in pages {
            if let id = page.folderID { XCTAssertTrue(folderIDs.contains(id), "\(page.title) left in a deleted folder") }
            if let folder = page.folder { XCTAssertTrue(folderIDs.contains(folder.id), "\(page.title) left in a deleted folder") }
        }
        for folder in folders {
            if let parent = folder.parent { XCTAssertTrue(folderIDs.contains(parent.id), "\(folder.name) under a deleted folder") }
            XCTAssertTrue((folder.children ?? []).allSatisfy(\.isLive))
            XCTAssertTrue((folder.pages ?? []).allSatisfy(\.isLive))
        }
        XCTAssertEqual(other.pages?.compactMap(\.key), [outsideKeys[1]])
        XCTAssertEqual(library.topLevelFolders().map(\.name).filter { !$0.isEmpty }, ["Other"])

        // Their audio went with them; the rest kept theirs.
        for key in insideKeys { XCTAssertFalse(env.cache.hasCache(for: key), "audio of a deleted page") }
        for key in outsideKeys { XCTAssertTrue(env.cache.hasCache(for: key), "audio of a page outside") }

        // The Library leaves the deleted screens.
        XCTAssertEqual(shell.libraryPath, [])

        // What screens still hold reads as gone; what was outside doesn't.
        for folder in [shelf, nested, deeper, book] { XCTAssertFalse(folder.isLive, "\(folder.name) reads as gone") }
        for page in inside { XCTAssertFalse(page.isLive, "\(page.title) reads as gone") }
        XCTAssertTrue(other.isLive)
        for page in outside { XCTAssertTrue(page.isLive) }
    }

    /// A delete that can't be saved is rolled back: every folder and page reads as live again,
    /// with its audio, so the screens holding them keep drawing them.
    func testADeleteThatCantBeSavedLeavesTheFolderLive() throws {
        let shelf = try library.makeFolder(name: "Shelf", in: nil)
        let nested = try library.makeFolder(name: "Nested", in: shelf)
        let pages = [try saved("p1", in: shelf), try saved("n1", in: nested)]
        for page in pages { try env.storeAudio(XCTUnwrap(page.key), paragraphs: page.cachedListenParagraphs ?? []) }

        library.saveContext = { _ in throw LibraryStoreError.saveFailed }
        XCTAssertThrowsError(try library.deleteFolders([shelf]))

        XCTAssertTrue(shelf.isLive)
        XCTAssertTrue(nested.isLive)
        for page in pages {
            XCTAssertTrue(page.isLive, "\(page.title) stays")
            XCTAssertTrue(env.cache.hasCache(for: try XCTUnwrap(page.key)), "with its audio")
        }
        XCTAssertEqual(library.subfolders(of: shelf).map(\.name), ["Nested"])
    }
}
