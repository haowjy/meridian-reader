import XCTest
@testable import Reader

/// `Imports/`: a picked or downloaded book is copied in under its own name, in a folder of its
/// own, and deleted with that folder; launch clears what a killed import left.
final class BookImportFilesTests: XCTestCase {
    private var root: URL!
    private var files: BookImportFiles!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "import-files-\(UUID().uuidString)", directoryHint: .isDirectory)
        files = BookImportFiles(directory: root.appending(path: "Imports", directoryHint: .isDirectory))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testAPickedFileIsCopiedInUnderItsOwnName() throws {
        let original = root.appending(path: "Pride and Prejudice.epub")
        try Data("book".utf8).write(to: original)
        let copy = try files.copyIn(original)
        XCTAssertEqual(copy.lastPathComponent, "Pride and Prejudice.epub")
        XCTAssertEqual(copy.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL,
                       files.directory.standardizedFileURL, "in a folder of its own inside Imports/")
        XCTAssertEqual(try Data(contentsOf: copy), Data("book".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path), "the original stays")

        let again = try files.copyIn(original)
        XCTAssertNotEqual(again, copy, "two picks of one file don't collide")
    }

    func testACopyThatFailsLeavesNothing() throws {
        let missing = root.appending(path: "gone.epub")
        XCTAssertThrowsError(try files.copyIn(missing))
        let left = (try? FileManager.default.contentsOfDirectory(atPath: files.directory.path)) ?? []
        XCTAssertEqual(left, [], "no folder of its own left in Imports/")
    }

    func testNamesAreFileNamesEndingInEPUB() {
        XCTAssertEqual(BookImportFiles.fileName("pg1342-images-3.epub"), "pg1342-images-3.epub")
        XCTAssertEqual(BookImportFiles.fileName("Unknown"), "Unknown.epub")
        XCTAssertEqual(BookImportFiles.fileName("a/b:c.EPUB"), "a-b-c.EPUB")
        XCTAssertEqual(BookImportFiles.fileName("  "), "Book.epub")
        XCTAssertEqual(BookImportFiles.fileName("..hidden"), "hidden.epub")
    }

    func testDiscardDeletesTheFileAndItsFolderOnly() throws {
        let file = try files.newFile(named: "book.epub")
        try Data("book".utf8).write(to: file)
        let other = try files.newFile(named: "other.epub")
        try Data("other".utf8).write(to: other)
        let outside = root.appending(path: "outside.epub")
        try Data("outside".utf8).write(to: outside)

        files.discard(file)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.deletingLastPathComponent().path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.path), "another import's file stays")
        files.discard(outside)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path), "a file outside Imports/ is never touched")
    }

    func testLaunchClearsLeftovers() throws {
        let file = try files.newFile(named: "book.epub")
        try Data("book".utf8).write(to: file)
        files.clearLeftovers()
        XCTAssertFalse(FileManager.default.fileExists(atPath: files.directory.path))
        XCTAssertNotNil(try? files.newFile(named: "next.epub"), "and the next import makes it again")
    }

    /// The app's launch sequence clears them, before anything else runs.
    @MainActor
    func testTheAppsLaunchClearsLeftovers() async throws {
        let file = try files.newFile(named: "book.epub")
        try Data("book".utf8).write(to: file)
        let env = try LibraryTestEnvironment()
        let speech = TestSpeech()
        defer { speech.tearDown(); env.cleanUp() }
        await AppLaunch.launch(library: env.library, speech: speech.speech, shell: ShellState(), importFiles: files)
        XCTAssertFalse(FileManager.default.fileExists(atPath: files.directory.path), "Imports/ is gone")
    }
}
