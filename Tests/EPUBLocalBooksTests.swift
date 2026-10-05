import XCTest
@testable import Reader

/// Reads real EPUBs kept outside the repo and reports how each was cut. Skipped unless
/// `TEST_RUNNER_READER_EPUB_DIR=<dir>` is set in xcodebuild's environment; writes
/// `<dir>/epub-report.txt`.
final class EPUBLocalBooksTests: XCTestCase {
    func testEveryBookInTheFolderCutsWithinBounds() throws {
        guard let path = ProcessInfo.processInfo.environment["READER_EPUB_DIR"], !path.isEmpty else {
            throw XCTSkip("Set TEST_RUNNER_READER_EPUB_DIR=<dir> to read the EPUBs there.")
        }
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "epub" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertFalse(files.isEmpty, "no .epub files in \(path)")
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
            let body = book.bodyChapters.map(\.wordCount).sorted()
            report += "\(file.lastPathComponent): \(book.metadata.title ?? "untitled") · \(book.metadata.authors.joined(separator: ", "))\n"
            report += "  spine \(book.spineCount), contents \(book.contents.count) top-level, chapters \(book.chapters.count)"
            report += " (\(book.bodyChapters.count) body); body words min \(body.first ?? 0) / median \(body.isEmpty ? 0 : body[body.count / 2]) / max \(body.last ?? 0)"
            report += String(format: "; read in %.2f s\n", seconds)
            for chapter in book.chapters {
                let title = chapter.title ?? "untitled"
                report += "  \(chapter.skipsInPlayback ? "skip" : "    ") \(String(format: "%3d", chapter.ordinal)) \(String(format: "%7d", chapter.wordCount))  \(title.prefix(60))  [\(chapter.spineHrefs.count) file(s)]\n"
            }
            report += "\n"
            XCTAssertFalse(book.bodyChapters.isEmpty, file.lastPathComponent)
            for chapter in book.bodyChapters where !(100...30_000).contains(chapter.wordCount) {
                XCTFail("\(file.lastPathComponent): \(chapter.title ?? "untitled") has \(chapter.wordCount) words")
            }
        }
        try report.write(to: folder.appendingPathComponent("epub-report.txt"), atomically: true, encoding: .utf8)
        print(report)
    }
}
