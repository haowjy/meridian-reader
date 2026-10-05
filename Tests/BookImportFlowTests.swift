import XCTest
@testable import Reader

/// The import sheet's flow (`BookImportFlow`) over the real import: where the book lands, *Add to*
/// changed while it runs, D13's question, *Cancel*, refusals, a downloaded book waiting for
/// *Import*, and the book's file in `Imports/` gone however it ends.
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

    private func start(_ file: URL, into destination: Folder? = nil, waits: Bool = false) -> BookImportFlow {
        BookImportFlow(file: file, destinationID: destination?.id, waitsForImport: waits, library: library, files: files,
                       land: { self.landed.append($0) }, close: { self.closes += 1 })
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

    func testAddToChangedWhileItRunsMovesTheNewBookThere() async throws {
        let fiction = try library.makeFolder(name: "Fiction", in: nil)
        let essays = try library.makeFolder(name: "Essays", in: nil)
        let flow = start(try picked(), into: fiction)
        flow.isChoosingDestination = true
        flow.choose(essays)
        XCTAssertFalse(flow.isChoosingDestination, "the Move tree goes back to the sheet")
        XCTAssertTrue(flow.destination === essays)
        try await until("the landing") { !landed.isEmpty }
        XCTAssertTrue(try XCTUnwrap(landed.first).parent === essays, "moved to the folder chosen while it ran")
        XCTAssertEqual(books().count, 1, "imported once")

        let top = start(try picked(otherBook()), into: essays)
        top.choose(nil)
        try await until("the second landing") { landed.count == 2 }
        XCTAssertNil(landed[1].parent, "Library (no folder): the top level")
    }

    func testABookAlreadyInTheLibraryAsksAndReplaceRebuildsItWhereItIs() async throws {
        let fiction = try library.makeFolder(name: "Fiction", in: nil)
        guard case .added(let existing) = try await BookImporter(library: library)
            .importBook(at: try BookImportTests.sampleBook().write(in: self), into: fiction, ifAlreadyInLibrary: .cancel)
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

    /// A second book (another identifier and title).
    private func otherBook() -> SyntheticEPUB {
        var epub = BookImportTests.sampleBook()
        epub.identifier = "urn:uuid:0f0e0d0c-2222-4333-8444-955566667777"
        epub.title = "The Other Book"
        return epub
    }
}
