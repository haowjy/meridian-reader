import XCTest
@testable import MeridianReader

/// Cutting stays close to linear for books inside every cap: many headings, many contents entries
/// on one target, many branches to open, many spine files. Each book is read through the package,
/// contents and spine against one standard `MarkupBudget`, so it's shown to be under the caps;
/// only the cut is timed. The 5 s bound is generous: these cut in about a second or less in a
/// Debug build, and took 8–32 s each, optimized, while parts of the cut grew with the square of
/// the book.
final class EPUBCutterScalingTests: XCTestCase {
    private typealias Entry = SyntheticEPUB.Entry

    /// What `EPUBBookReader` builds before cutting, read against one standard budget.
    private func prepared(_ url: URL, rules: EPUBCutRules) throws -> (stream: EPUBTextStream, contents: [EPUBContentsEntry]) {
        let archive = try EPUBContainer(fileURL: url)
        let budget = MarkupBudget(limits: .standard)
        let package = try EPUBPackage.read(from: archive, budget: budget)
        let contents = try EPUBContents.read(package, from: archive, budget: budget)
        let documents = try package.spine.map {
            try EPUBSpineDocument(path: $0.path, data: budget.readText($0.path, from: archive), linear: $0.linear,
                                  maxRunWords: rules.maxRunWords, budget: budget)
        }
        return (EPUBTextStream(documents: documents), contents.entries)
    }

    /// Cuts the book, checks the cuts cover it in order with no piece over the maximum, and
    /// returns them with the seconds the cut took.
    private func timedCut(_ url: URL, rules: EPUBCutRules = .standard,
                          file: StaticString = #filePath, line: UInt = #line) throws -> (cuts: [EPUBCut], seconds: TimeInterval) {
        let (stream, contents) = try prepared(url, rules: rules)
        // A monotonic clock: a wall-clock change during the cut can't make it look fast or slow.
        var cuts: [EPUBCut] = []
        let elapsed = ContinuousClock().measure {
            cuts = EPUBChapterCutter(stream: stream, rules: rules).cut(contents: contents)
        }
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        XCTAssertEqual(cuts.first?.start, stream.start, file: file, line: line)
        XCTAssertEqual(cuts.last?.end, stream.end, file: file, line: line)
        XCTAssertTrue(zip(cuts, cuts.dropFirst()).allSatisfy { $0.end == $1.start }, "cuts follow one another", file: file, line: line)
        XCTAssertEqual(cuts.map(\.provisionalWordCount).reduce(0, +), stream.totalWords, file: file, line: line)
        XCTAssertTrue(cuts.allSatisfy { $0.provisionalWordCount <= rules.maxWords }, file: file, line: line)
        XCTAssertEqual(Set(cuts.map(\.locator)).count, cuts.count, "locators are unique", file: file, line: line)
        return (cuts, seconds)
    }

    /// 150,000 one-word `h1` headings and nothing else: 150,000 ranges, nearly all merged away.
    func testHundredAndFiftyThousandOneWordHeadings() throws {
        var epub = SyntheticEPUB()
        epub.tableOfContents = .none
        let headings = (0..<150_000).map { "<h1>\(SyntheticEPUB.words(1, seed: $0))</h1>" }.joined()
        epub.addDocument("all.xhtml", body: SyntheticEPUB.xhtml(body: headings))
        let (cuts, seconds) = try timedCut(epub.write(in: self))
        XCTAssertEqual(cuts.count, 1_000, "short headings merge forward into pieces of 150 words")
        XCTAssertLessThan(seconds, 5, "cut in \(seconds) s")
    }

    /// 34,000 contents entries naming the same file, each with one child: the children gather on
    /// one mark, and the file (over the maximum) opens to all of them. The nav is written without
    /// whitespace so it stays under the node cap.
    func testManyContentsEntriesOnOneTargetWithChildren() throws {
        let count = 34_000
        var epub = SyntheticEPUB()
        let paragraphs = (0..<count).map { "<p id=\"c\($0)\">\(SyntheticEPUB.words(2, seed: $0))</p>" }.joined()
        epub.addDocument("all.xhtml", body: SyntheticEPUB.xhtml(body: paragraphs))
        epub.contents = [Entry("Part", "all.xhtml")]
        let items = (0..<count).map {
            "<li><a href=\"all.xhtml\">Part</a><ol><li><a href=\"all.xhtml#c\($0)\">Section</a></li></ol></li>"
        }.joined()
        let nav = SyntheticEPUB.xhtml(body: "<nav epub:type=\"toc\"><ol>\(items)</ol></nav>")
        let entries = epub.entries().map { entry -> TestZipWriter.Entry in
            guard entry.path == epub.path("nav.xhtml") else { return entry }
            var replaced = entry
            replaced.data = Data(nav.utf8)
            return replaced
        }
        let (cuts, seconds) = try timedCut(epub.write(in: self, entries: entries))
        XCTAssertEqual(cuts.count, 453, "each section is short: they merge into pieces of 150 words")
        XCTAssertLessThan(seconds, 5, "cut in \(seconds) s")
    }

    /// 5,000 entries over a small maximum, each with 10 children: 5,000 branches to open, one
    /// after another.
    func testManyBranchesToOpen() throws {
        let rules = EPUBCutRules(maxWords: 20, mergeBelowWords: 2, unlistedSkipBelowWords: 1)
        var epub = SyntheticEPUB()
        var paragraphs = ""
        var contents: [Entry] = []
        for part in 0..<5_000 {
            paragraphs += "<p id=\"p\(part)\">\(SyntheticEPUB.words(2, seed: part))</p>"
            var children: [Entry] = []
            for section in 0..<10 {
                paragraphs += "<p id=\"p\(part)-\(section)\">\(SyntheticEPUB.words(2, seed: section))</p>"
                children.append(Entry("Section", "all.xhtml#p\(part)-\(section)"))
            }
            contents.append(Entry("Part", "all.xhtml#p\(part)", children))
        }
        epub.addDocument("all.xhtml", body: SyntheticEPUB.xhtml(body: paragraphs))
        epub.contents = contents
        let (cuts, seconds) = try timedCut(epub.write(in: self), rules: rules)
        XCTAssertEqual(cuts.count, 55_000, "every part (22 words) opens to its sections")
        XCTAssertLessThan(seconds, 5, "cut in \(seconds) s")
    }

    /// A spine naming one empty file 200,000 times, then a file with text: every file's top is
    /// the next file with any markup.
    func testManyEmptySpineFiles() throws {
        var epub = SyntheticEPUB()
        epub.tableOfContents = .none
        epub.addDocument("empty.xhtml", body: "<html><body></body></html>")
        epub.addDocument("text.xhtml", body: SyntheticEPUB.xhtml(body: SyntheticEPUB.paragraphs(500)))
        // Itemrefs with nothing between them: two nodes each, so the package stays under the cap.
        let itemref = "<itemref idref=\"d0\"/>"
        let opf = epub.opf().replacingOccurrences(of: itemref + "\n", with: String(repeating: itemref, count: 200_000) + "\n")
        let entries = epub.entries().map { entry -> TestZipWriter.Entry in
            guard entry.path == epub.opfPath else { return entry }
            var replaced = entry
            replaced.data = Data(opf.utf8)
            return replaced
        }
        let (cuts, seconds) = try timedCut(epub.write(in: self, entries: entries))
        XCTAssertEqual(cuts.map(\.provisionalWordCount), [500])
        XCTAssertEqual(cuts.first?.locator, EPUBLocator(href: "OEBPS/text.xhtml", anchor: .fileStart))
        XCTAssertLessThan(seconds, 5, "cut in \(seconds) s")
    }
}
