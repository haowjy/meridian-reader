import XCTest
@testable import MeridianReader

/// The import sheet's flow (`BookImportFlow`) over the real import: where the book lands, *Add to*
/// changed while it runs (stored there in the import's one save), D13's question, *Cancel*,
/// refusals, saves that fail, a downloaded book waiting for *Import*, one import sheet at a time,
/// and the book's file in `Imports/` gone however it ends.
@MainActor
final class BookImportFlowTests: XCTestCase {
    private var env: LibraryTestEnvironment!
    private var library: LibraryStore { env.library }
    private var files: BookImportFiles!
    private var landed: [Folder] = []
    private var closes = 0

    override func setUp() async throws {
        env = try LibraryTestEnvironment()
        files = BookImportFiles(directory: FileManager.default.temporaryDirectory
            .appending(path: "imports-\(UUID().uuidString)", directoryHint: .isDirectory))
        landed = []
        closes = 0
    }

    override func tearDown() async throws {
        files.clearLeftovers()
        env.cleanUp()
    }

    // MARK: - Helpers

    /// `epub` copied into `files`, as a pick would.
    private func picked(_ epub: SyntheticEPUB? = nil) throws -> URL {
        try files.copyIn(try (epub ?? BookImportTests.sampleBook()).write(in: self))
    }

    private func start(_ file: URL, into destination: Folder? = nil, waits: Bool = false,
                       library: LibraryStore? = nil) -> BookImportFlow {
        BookImportFlow(file: file, destinationID: destination?.id, waitsForImport: waits, library: library ?? self.library,
                       files: files, land: { _, book in self.landed.append(book) }, close: { _ in self.closes += 1 })
    }

    /// True once `flow` is preparing chapters, after doing `then` in that same main-actor turn:
    /// the import is between reading and its save, deterministically.
    private func whilePreparing(_ flow: BookImportFlow, then: () -> Void) -> Bool {
        guard case .working(.preparing) = flow.phase else { return false }
        then()
        return true
    }

    private func until(_ what: String, timeout: TimeInterval = 30, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return XCTFail("timed out waiting for \(what)") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func books() -> [Folder] { env.folders().filter { $0.kind == .book } }

    private func fileIsGone(_ file: URL) -> Bool {
        !FileManager.default.fileExists(atPath: file.path) && !FileManager.default.fileExists(atPath: file.deletingLastPathComponent().path)
    }

    // MARK: - Importing

    func testAPickedBookImportsIntoItsFolderAndLandsThere() async throws {
        let fiction = try library.makeFolder(name: "Fiction", in: nil)
        let file = try picked()
        let flow = start(file, into: fiction)
        XCTAssertTrue(flow.isWorking, "a picked book starts at once")
        try await until("the landing") { !landed.isEmpty }

        let book = try XCTUnwrap(landed.first)
        XCTAssertEqual(book.name, "The Lantern Keeper")
        XCTAssertTrue(book.parent === fiction, "in the folder it was imported from")
        XCTAssertEqual(flow.phase, .ended)
        XCTAssertEqual(flow.preview?.title, "The Lantern Keeper")
        XCTAssertEqual(flow.preview?.byline, "Ada Example, Ben Sample")
        XCTAssertEqual(flow.preview?.chapterCount, 4)
        XCTAssertEqual(flow.preview?.chapterTitles, ["Chapter 1: The Harbor", "Chapter 2: The Lighthouse", "Chapter 3: The Tide"])
        XCTAssertEqual(flow.preview?.skippedTitles, ["Title Page"])
        XCTAssertNotNil(flow.preview?.cover, "the cover's thumbnail")
        XCTAssertTrue(fileIsGone(file), "the copy in Imports/ is deleted")
        XCTAssertEqual(closes, 0, "landing closes the sheet itself")
    }

    func testAddToChangedWhileItRunsFilesTheNewBookThere() async throws {
        let fiction = try library.makeFolder(name: "Fiction", in: nil)
        let essays = try library.makeFolder(name: "Essays", in: nil)
        let flow = start(try picked(), into: fiction)
        flow.isChoosingDestination = true
        flow.choose(essays)
        XCTAssertFalse(flow.isChoosingDestination, "the Move tree goes back to the sheet")
        XCTAssertTrue(flow.destination === essays)
        try await until("the landing") { !landed.isEmpty }
        XCTAssertTrue(try XCTUnwrap(landed.first).parent === essays, "filed in the folder chosen while it ran")
        XCTAssertEqual(books().count, 1, "imported once")

        let top = start(try picked(otherBook()), into: essays)
        top.choose(nil)
        try await until("the second landing") { landed.count == 2 }
        XCTAssertNil(landed[1].parent, "Library (no folder): the top level")
    }

    /// The changed *Add to* is in the import's one save: no second save to fail or be cut short
    /// by the app dying, so the book is there after a relaunch.
    func testAddToChangedWhileItRunsIsStoredThereInOneSave() async throws {
        let disk = try LibraryTestEnvironment(fileBacked: true)
        defer { disk.cleanUp() }
        let fiction = try disk.library.makeFolder(name: "Fiction", in: nil)
        let essays = try disk.library.makeFolder(name: "Essays", in: nil)
        var saves: [String] = []
        disk.library.saveContext = { context in
            saves.append("save")
            guard saves.count == 1 else { throw CocoaError(.fileWriteUnknown) }  // any second save fails
            try context.save()
        }
        let flow = start(try picked(), into: fiction, library: disk.library)
        try await until("the change, mid-import") { whilePreparing(flow) { flow.choose(essays) } }
        try await until("the landing") { !landed.isEmpty }
        XCTAssertEqual(saves.count, 1, "the book and its place are one save")
        XCTAssertTrue(try XCTUnwrap(landed.first).parent === essays)

        disk.library.saveContext = { try $0.save() }
        try disk.relaunch()
        let stored = disk.folders().filter { $0.kind == .book }
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.parent?.name, "Essays", "reopened, the book is where Add to said")
    }

    /// The folder chosen while it ran is deleted before the save: the import fails, saying so,
    /// and keeps nothing; the sheet said so too.
    func testAChosenFolderDeletedMidImportFailsSayingSo() async throws {
        let fiction = try library.makeFolder(name: "Fiction", in: nil)
        let essays = try library.makeFolder(name: "Essays", in: nil)
        let file = try picked()
        let flow = start(file, into: fiction)
        try await until("the change, then the delete") {
            whilePreparing(flow) {
                flow.choose(essays)
                try? library.deleteFolder(essays)
                XCTAssertTrue(flow.isDestinationGone, "the sheet's Add to says the folder is gone")
            }
        }
        try await until("the refusal") { if case .failed = flow.phase { true } else { false } }
        XCTAssertEqual(flow.phase, .failed("The folder chosen for this book no longer exists."))
        XCTAssertTrue(books().isEmpty, "not filed in the original folder, or anywhere")
        XCTAssertTrue(env.pages().isEmpty)
        XCTAssertTrue(landed.isEmpty)
        XCTAssertTrue(fileIsGone(file))
        XCTAssertNotNil(library.folder(id: fiction.id))
    }

    /// The folder the import started in is deleted after another was chosen: the book goes to the
    /// chosen one.
    func testTheOriginalFolderDeletedAfterChoosingAnotherDoesntMatter() async throws {
        let fiction = try library.makeFolder(name: "Fiction", in: nil)
        let essays = try library.makeFolder(name: "Essays", in: nil)
        let flow = start(try picked(), into: fiction)
        try await until("the change, then the delete") {
            whilePreparing(flow) {
                flow.choose(essays)
                try? library.deleteFolder(fiction)
            }
        }
        try await until("the landing") { !landed.isEmpty }
        XCTAssertTrue(try XCTUnwrap(landed.first).parent === essays)
        XCTAssertEqual(books().count, 1)
    }

    func testABookAlreadyInTheLibraryAsksAndReplaceRebuildsItWhereItIs() async throws {
        let fiction = try library.makeFolder(name: "Fiction", in: nil)
        guard case .added(let existing) = try await BookImporter(library: library)
            .importBook(at: try BookImportTests.sampleBook().write(in: self), into: fiction.id, ifAlreadyInLibrary: .cancel)
        else { return XCTFail("first import") }
        existing.name = "Renamed"

        let file = try picked()
        let flow = start(file)
        try await until("D13's question") { flow.phase == .alreadyInLibrary(existing.id) }
        XCTAssertEqual(flow.title, "The Lantern Keeper", "named from the file, for the question")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "the file stays for Replace")
        XCTAssertTrue(landed.isEmpty)

        flow.replace()
        XCTAssertTrue(flow.isReplacing)
        XCTAssertTrue(flow.destination === fiction, "*Add to* shows where the book is")
        flow.choose(nil)
        XCTAssertTrue(flow.destination === fiction, "and can't change: Replace keeps the book where it is")
        try await until("the landing") { !landed.isEmpty }
        XCTAssertTrue(landed.first === existing, "the same folder")
        XCTAssertTrue(existing.parent === fiction)
        XCTAssertEqual(existing.name, "Renamed", "its name stays")
        XCTAssertEqual(books().count, 1)
        XCTAssertTrue(fileIsGone(file))
    }

    func testCancelOnTheQuestionKeepsTheBookAsItIs() async throws {
        guard case .added(let existing) = try await BookImporter(library: library)
            .importBook(at: try BookImportTests.sampleBook().write(in: self), into: nil, ifAlreadyInLibrary: .cancel)
        else { return XCTFail("first import") }
        let chapters = library.playOrder(of: existing).map(\.key)
        let file = try picked()
        let flow = start(file)
        try await until("D13's question") { flow.phase == .alreadyInLibrary(existing.id) }
        flow.cancel()
        XCTAssertEqual(flow.phase, .ended)
        XCTAssertEqual(closes, 1, "the sheet closes")
        XCTAssertTrue(fileIsGone(file))
        XCTAssertEqual(books().count, 1)
        XCTAssertEqual(library.playOrder(of: existing).map(\.key), chapters, "the book is untouched")
        XCTAssertTrue(landed.isEmpty)
    }

    func testCancelWhileItRunsKeepsNothing() async throws {
        let file = try picked()
        let flow = start(file)
        try await until("a chapter being prepared") {
            if case .working(.preparing) = flow.phase { true } else { false }
        }
        flow.cancel()
        XCTAssertEqual(closes, 1, "the sheet closes at once")
        try await until("the file to go") { fileIsGone(file) }
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(books().isEmpty, "nothing stored")
        XCTAssertTrue(env.pages().isEmpty, "no chapter stored")
        XCTAssertTrue(landed.isEmpty, "and no landing")
        XCTAssertEqual(flow.phase, .ended)
    }

    func testARefusalSaysWhyKeepsNothingAndClosesOnOK() async throws {
        var drm = BookImportTests.sampleBook()
        drm.extraFiles.append(("META-INF/encryption.xml", Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container" xmlns:enc="http://www.w3.org/2001/04/xmlenc#">
        <enc:EncryptedData><enc:EncryptionMethod Algorithm="http://www.w3.org/2001/04/xmlenc#aes128-cbc"/>
        <enc:CipherData><enc:CipherReference URI="OEBPS/two.xhtml"/></enc:CipherData></enc:EncryptedData>
        </encryption>
        """.utf8)))
        let file = try picked(drm)
        let flow = start(file)
        try await until("the refusal") { if case .failed = flow.phase { true } else { false } }
        XCTAssertEqual(flow.phase, .failed("This book is copy-protected (DRM), so Meridian can't read it."))
        XCTAssertFalse(flow.isWorking, "the sheet can be closed")
        XCTAssertTrue(fileIsGone(file))
        XCTAssertTrue(books().isEmpty)
        flow.acknowledgeFailure()
        XCTAssertEqual(flow.phase, .ended)
        XCTAssertEqual(closes, 1)
    }

    /// The import's one save fails: the sheet says so in its one line, nothing is kept (no book,
    /// no chapter, nothing waiting in the context), and the file goes.
    func testAnImportWhoseSaveFailsSaysSoAndKeepsNothing() async throws {
        let fiction = try library.makeFolder(name: "Fiction", in: nil)
        library.saveContext = { _ in throw CocoaError(.fileWriteUnknown) }
        let file = try picked()
        let flow = start(file, into: fiction)
        try await until("the failure") { if case .failed = flow.phase { true } else { false } }
        XCTAssertEqual(flow.phase, .failed("Meridian couldn't save the book. Try again."))
        XCTAssertFalse(env.context.hasChanges, "nothing waits for a later save")
        XCTAssertTrue(books().isEmpty)
        XCTAssertTrue(env.pages().isEmpty)
        XCTAssertTrue(fiction.children?.isEmpty ?? true)
        XCTAssertTrue(landed.isEmpty)
        XCTAssertTrue(fileIsGone(file))
        flow.acknowledgeFailure()
        XCTAssertEqual(closes, 1)
    }

    /// D13's *Replace* whose save fails: the sheet says so, and the book is as it was.
    func testAReplaceWhoseSaveFailsSaysSoAndLeavesTheBookAsItWas() async throws {
        guard case .added(let existing) = try await BookImporter(library: library)
            .importBook(at: try BookImportTests.sampleBook().write(in: self), into: nil, ifAlreadyInLibrary: .cancel)
        else { return XCTFail("first import") }
        let chapters = library.playOrder(of: existing).map(\.key)
        let texts = library.playOrder(of: existing).map(\.cachedListenParagraphs)
        let file = try picked(revisedBook())
        let flow = start(file)
        try await until("D13's question") { flow.phase == .alreadyInLibrary(existing.id) }

        library.saveContext = { _ in throw CocoaError(.fileWriteUnknown) }
        flow.replace()
        try await until("the failure") { if case .failed = flow.phase { true } else { false } }
        XCTAssertEqual(flow.phase, .failed("Meridian couldn't save the book. Try again."))
        XCTAssertFalse(env.context.hasChanges, "nothing waits for a later save")
        XCTAssertEqual(books().count, 1)
        XCTAssertEqual(library.playOrder(of: existing).map(\.key), chapters, "every chapter is still there")
        XCTAssertEqual(library.playOrder(of: existing).map(\.cachedListenParagraphs), texts, "with its text")
        XCTAssertTrue(landed.isEmpty)
        XCTAssertTrue(fileIsGone(file))
    }

    /// *New Folder* in *Add to*'s tree that can't be saved: no folder, *Add to* unchanged, the
    /// tree stays up and a toast says so. Once saves work, the folder is made and chosen.
    func testANewFolderInAddToThatCantBeSavedChoosesNothing() throws {
        let fiction = try library.makeFolder(name: "Fiction", in: nil)
        let shell = ShellState()
        let flow = start(try picked(), into: fiction, waits: true)
        flow.isChoosingDestination = true
        library.saveContext = { _ in throw CocoaError(.fileWriteUnknown) }

        flow.chooseNewFolder(named: "Essays", in: fiction, shell: shell)
        XCTAssertFalse(env.folders().contains { $0.name == "Essays" }, "no folder")
        XCTAssertEqual(flow.destinationID, fiction.id, "Add to is unchanged")
        XCTAssertTrue(flow.isChoosingDestination, "the tree stays up")
        XCTAssertEqual(shell.toast?.message, "Couldn’t make the folder")

        library.saveContext = { try $0.save() }
        flow.chooseNewFolder(named: "  ", in: fiction, shell: shell)
        let made = try XCTUnwrap(env.folders().first { $0.name == "New Folder" }, "a blank name makes New Folder")
        XCTAssertTrue(made.parent === fiction, "inside the folder it was asked in")
        XCTAssertEqual(flow.destinationID, made.id, "and the book goes there")
        XCTAssertFalse(flow.isChoosingDestination, "the tree goes back to the sheet")
        flow.cancel()
    }

    /// The sample book with its second chapter's text changed (the same identifier).
    private func revisedBook() -> SyntheticEPUB {
        var epub = BookImportTests.sampleBook()
        let two = epub.documents.firstIndex { $0.name == "two.xhtml" }!
        epub.documents[two].body = epub.documents[two].body.replacingOccurrences(of: "<p>", with: "<p>Revised. ")
        return epub
    }

    func testATooLargeBookSaysSo() {
        XCTAssertEqual(BookImportError(EPUBError.tooLarge), .tooLarge)
        XCTAssertEqual(BookImportError.tooLarge.localizedDescription, "This book is too large to import.")
    }

    // MARK: - A downloaded book

    func testADownloadedBookWaitsForImport() async throws {
        let file = try picked()
        let flow = start(file, waits: true)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(flow.phase, .ready)
        XCTAssertNil(flow.preview, "not read before Import")
        XCTAssertEqual(flow.title, file.deletingPathExtension().lastPathComponent, "named after its file until read")
        flow.startImport()
        try await until("the landing") { !landed.isEmpty }
        XCTAssertNil(landed.first?.parent, "a link's book goes to the top level unless changed")
    }

    func testTheSheetGoingAwayBeforeImportDeletesTheFile() throws {
        let file = try picked()
        let flow = start(file, waits: true)
        flow.sheetGone()
        XCTAssertEqual(flow.phase, .ended)
        XCTAssertTrue(fileIsGone(file))
        flow.sheetGone()
        XCTAssertEqual(closes, 1, "once")
    }

    // MARK: - One import sheet at a time

    func testABookArrivingWhileAnImportIsOpenIsRefused() throws {
        let shell = ShellState()
        let actions = BookImportActions(library: library, shell: shell, files: files)
        actions.importDownloaded(try picked())
        let first = try XCTUnwrap(shell.importFlow)

        let second = try picked(otherBook())
        actions.importDownloaded(second)
        XCTAssertTrue(shell.importFlow === first, "the open import stays")
        XCTAssertTrue(fileIsGone(second), "the second book's file goes")
        XCTAssertEqual(shell.toast?.message, "Another import is open; “\(second.lastPathComponent)” wasn't imported")
        first.cancel()
        XCTAssertNil(shell.importFlow)
    }

    /// An older flow's sheet going away, its Cancel, or its landing never closes a newer flow's
    /// sheet, however that one came up.
    func testAnOldFlowCantCloseOrLandOnANewerOnesSheet() async throws {
        let shell = ShellState()
        let actions = BookImportActions(library: library, shell: shell, files: files)
        actions.importDownloaded(try picked())
        let old = try XCTUnwrap(shell.importFlow)
        actions.importPicked(try BookImportTests.sampleBook().write(in: self), into: nil)
        XCTAssertTrue(shell.importFlow === old)

        let newer = BookImportFlow(file: try picked(otherBook()), destinationID: nil, waitsForImport: true,
                                   library: library, files: files, land: { _, _ in }, close: { shell.closeImport($0) })
        shell.present(.importBook(newer))
        old.sheetGone()
        XCTAssertEqual(old.phase, .ended)
        XCTAssertTrue(shell.importFlow === newer, "the old sheet's disappearance leaves the newer one up")

        // A picked book starts at once; it lands while a newer sheet is up.
        shell.sheet = nil
        actions.importPicked(try BookImportTests.sampleBook().write(in: self), into: nil)
        let landing = try XCTUnwrap(shell.importFlow)
        shell.present(.importBook(newer))
        try await until("the old import to end") { landing.phase == .ended }
        XCTAssertEqual(books().count, 1, "it was imported")
        XCTAssertTrue(shell.importFlow === newer, "its landing leaves the newer sheet up")
        XCTAssertFalse(shell.isInLibrary, "and doesn't go to its book under the newer sheet")
        newer.cancel()
        XCTAssertNil(shell.importFlow, "the newer flow closes its own sheet")
    }

    /// A second book (another identifier and title).
    private func otherBook() -> SyntheticEPUB {
        var epub = BookImportTests.sampleBook()
        epub.identifier = "urn:uuid:0f0e0d0c-2222-4333-8444-955566667777"
        epub.title = "The Other Book"
        return epub
    }
}
