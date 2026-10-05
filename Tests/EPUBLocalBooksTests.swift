import XCTest
@testable import Reader

/// Reads real EPUBs kept outside the repo and reports how each was cut, then imports each and
/// reports its chapters as stored, settled on their listen blocks. Skipped unless
/// `TEST_RUNNER_READER_EPUB_DIR=<dir>` is set in xcodebuild's environment; writes
/// `<dir>/epub-report.txt` and `<dir>/import-report.txt`.
final class EPUBLocalBooksTests: XCTestCase {
    private func books() throws -> (folder: URL, files: [URL]) {
        guard let path = ProcessInfo.processInfo.environment["READER_EPUB_DIR"], !path.isEmpty else {
            throw XCTSkip("Set TEST_RUNNER_READER_EPUB_DIR=<dir> to read the EPUBs there.")
        }
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "epub" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertFalse(files.isEmpty, "no .epub files in \(path)")
        return (folder, files)
    }

    /// Each book into a library of its own: editions that share an identifier and a title (a
    /// Gutenberg book's EPUB2 and EPUB3 files) are one book to the library.
    @MainActor
    func testEveryBookInTheFolderImportsWithinBoundsOnItsListenBlocks() async throws {
        let (folder, files) = try books()
        var report = ""
        for file in files {
            let env = try LibraryTestEnvironment()
            defer { env.cleanUp() }
            let started = ContinuousClock.now
            let outcome: BookImportOutcome
            do {
                outcome = try await BookImporter(library: env.library).importBook(at: file, into: nil, ifAlreadyInLibrary: .cancel)
            } catch {
                report += "\(file.lastPathComponent): \(error)\n\n"
                XCTFail("\(file.lastPathComponent): \(error)")
                continue
            }
            guard case .added(let book) = outcome else {
                XCTFail("\(file.lastPathComponent): \(outcome)")
                continue
            }
            let pages = env.library.playOrder(of: book)
            let body = pages.filter { !$0.skipsInPlayback }.map(\.wordCount).sorted()
            report += "\(file.lastPathComponent): \(book.name) · \(book.byline ?? "")\n"
            report += "  pages \(pages.count) (\(body.count) body); body words min \(body.first ?? 0) / median \(body.isEmpty ? 0 : body[body.count / 2]) / max \(body.last ?? 0); cover \(book.coverData?.count ?? 0) bytes; imported in \(started.duration(to: .now))\n"
            for (index, page) in pages.enumerated() {
                report += "  \(page.skipsInPlayback ? "skip" : "    ") \(String(format: "%3d", index)) \(String(format: "%7d", page.wordCount)) \(String(format: "%5d", page.paragraphCount))  \(page.title.prefix(60))  [\(page.locator ?? "")]\n"
            }
            report += "\n"
            XCTAssertFalse(body.isEmpty, file.lastPathComponent)
            XCTAssertEqual(Set(pages.compactMap(\.key)).count, pages.count, "\(file.lastPathComponent): keys are unique")
            for page in pages {
                XCTAssertGreaterThan(page.paragraphCount, 0, "\(file.lastPathComponent): \(page.title) has text")
                if !page.skipsInPlayback, !(100...30_000).contains(page.wordCount) {
                    XCTFail("\(file.lastPathComponent): \(page.title) has \(page.wordCount) words")
                }
            }
        }
        try report.write(to: folder.appendingPathComponent("import-report.txt"), atomically: true, encoding: .utf8)
        print(report)
    }

    func testEveryBookInTheFolderCutsWithinBounds() throws {
        let (folder, files) = try books()
        var report = ""
        for file in files {
            let started = Date()
            let book: EPUBBook
            do {
                book = try EPUBBookReader.read(fileURL: file)
            } catch {
                report += "\(file.lastPathComponent): refused \(error)\n\n"
                XCTFail("\(file.lastPathComponent): \(error)")
                continue
            }
            let seconds = Date().timeIntervalSince(started)
            let body = book.bodyChapters.map(\.provisionalWordCount).sorted()
            report += "\(file.lastPathComponent): \(book.metadata.title ?? "untitled") · \(book.metadata.authors.joined(separator: ", "))\n"
            report += "  spine \(book.spineCount), contents \(book.contents.count) top-level, chapters \(book.chapters.count)"
            report += " (\(book.bodyChapters.count) body); body words min \(body.first ?? 0) / median \(body.isEmpty ? 0 : body[body.count / 2]) / max \(body.last ?? 0)"
            report += String(format: "; read in %.2f s\n", seconds)
            for chapter in book.chapters {
                let title = chapter.title ?? "untitled"
                report += "  \(chapter.skipsInPlayback ? "skip" : "    ") \(String(format: "%3d", chapter.ordinal)) \(String(format: "%7d", chapter.provisionalWordCount))  \(title.prefix(60))  [\(chapter.spineHrefs.count) file(s)]\n"
            }
            report += "\n"
            XCTAssertFalse(book.bodyChapters.isEmpty, file.lastPathComponent)
            for chapter in book.bodyChapters where !(100...30_000).contains(chapter.provisionalWordCount) {
                XCTFail("\(file.lastPathComponent): \(chapter.title ?? "untitled") has \(chapter.provisionalWordCount) words")
            }
        }
        try report.write(to: folder.appendingPathComponent("epub-report.txt"), atomically: true, encoding: .utf8)
        print(report)
    }
}
