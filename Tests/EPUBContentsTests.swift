import XCTest
@testable import Reader

/// The table of contents (EPUB3 nav, EPUB2 NCX) and cutting the book at its anchors: depth chosen
/// per branch, chapters across files, tiny entries merged, fallbacks for sparse or missing contents.
final class EPUBContentsTests: XCTestCase {
    private typealias Entry = SyntheticEPUB.Entry

    private func chapterFile(_ id: String, _ heading: String, words: Int, seed: Int = 0) -> String {
        SyntheticEPUB.xhtml(body: SyntheticEPUB.chapter(id: id, heading: heading, words: words, seed: seed))
    }

    // MARK: - Reading the contents

    private func partBook(version: String = "3.0", contents: SyntheticEPUB.TableOfContents = .nav) -> SyntheticEPUB {
        var epub = SyntheticEPUB()
        epub.version = version
        epub.tableOfContents = contents
        epub.addDocument("one.xhtml", body: chapterFile("c1", "Chapter 1", words: 400))
        epub.addDocument("two.xhtml", body: SyntheticEPUB.xhtml(body: SyntheticEPUB.chapter(id: "c2", heading: "Chapter 2", words: 400)
            + SyntheticEPUB.chapter(id: "c3", heading: "Chapter 3", words: 400, seed: 1)))
        epub.addDocument("three.xhtml", body: chapterFile("c4", "Afterword", words: 400))
        epub.contents = [
            Entry("Part One", nil, [Entry("Chapter 1", "one.xhtml"), Entry("Chapter 2", "two.xhtml#c2"),
                                    Entry("Chapter 3", "two.xhtml#c3")]),
            Entry("Afterword", "three.xhtml#c4"),
        ]
        return epub
    }

    private let partTree = [
        EPUBContentsEntry(title: "Part One", path: nil, fragment: nil, children: [
            EPUBContentsEntry(title: "Chapter 1", path: "OEBPS/one.xhtml", fragment: nil),
            EPUBContentsEntry(title: "Chapter 2", path: "OEBPS/two.xhtml", fragment: "c2"),
            EPUBContentsEntry(title: "Chapter 3", path: "OEBPS/two.xhtml", fragment: "c3"),
        ]),
        EPUBContentsEntry(title: "Afterword", path: "OEBPS/three.xhtml", fragment: "c4"),
    ]

    func testNavKeepsTheWholeTreeIncludingUnlinkedHeadings() throws {
        let book = try partBook().read(in: self)
        XCTAssertEqual(book.contents, partTree)
        // A short branch is one chapter, cut at the top level and titled by its heading.
        XCTAssertEqual(book.titles, ["Part One", "Afterword"])
        XCTAssertEqual(book.chapters.map(\.provisionalWordCount), [1_200, 400])
        XCTAssertEqual(book.chapters.first?.locator, EPUBLocator(href: "OEBPS/one.xhtml", anchor: .fileStart),
                       "a heading that links nowhere starts at its first child")
    }

    func testNCXKeepsTheWholeTree() throws {
        let book = try partBook(version: "2.0", contents: .ncx).read(in: self)
        XCTAssertEqual(book.contents, partTree)
        XCTAssertEqual(book.titles, ["Part One", "Afterword"])
    }

    func testNavWinsOverTheNCX() throws {
        let archive = try EPUBContainer(fileURL: partBook(contents: .both).write(in: self))
        let contents = try EPUBContents.read(EPUBPackage.read(from: archive, budget: MarkupBudget()), from: archive, budget: MarkupBudget())
        XCTAssertEqual(contents.source, .nav)
        XCTAssertEqual(contents.entries, partTree)
    }

    func testNCXIsUsedWhenTheNavListsNothing() throws {
        let epub = partBook(contents: .both)
        let entries = epub.entries().map { entry -> TestZipWriter.Entry in
            guard entry.path == epub.path("nav.xhtml") else { return entry }
            var empty = entry
            empty.data = Data(SyntheticEPUB.xhtml(body: "<nav epub:type=\"toc\"><h1>Contents</h1><ol></ol></nav>").utf8)
            return empty
        }
        let archive = try EPUBContainer(fileURL: epub.write(in: self, entries: entries))
        let contents = try EPUBContents.read(EPUBPackage.read(from: archive, budget: MarkupBudget()), from: archive, budget: MarkupBudget())
        XCTAssertEqual(contents.source, .ncx)
        XCTAssertEqual(contents.entries, partTree)
    }

    // MARK: - Cutting at anchors

    /// Gutenberg's shape: files cut by size, every entry `file#anchor`, a chapter running across
    /// two files.
    func testFlatContentsCutAtAnchorsWithAChapterAcrossTwoFiles() throws {
        var epub = SyntheticEPUB()
        epub.version = "2.0"
        epub.tableOfContents = .ncx
        epub.addDocument("part1.xhtml", body: SyntheticEPUB.xhtml(body: """
        <div class="chapter"><h2 id="c1">CHAPTER I.</h2>
        \(SyntheticEPUB.paragraphs(598))</div>
        <div class="chapter"><h2 id="c2">CHAPTER II.</h2>
        \(SyntheticEPUB.paragraphs(298, seed: 2))
        """))
        epub.addDocument("part2.xhtml", body: SyntheticEPUB.xhtml(body: """
        <p>zircon \(SyntheticEPUB.words(99, seed: 5))</p>
        \(SyntheticEPUB.paragraphs(400, seed: 6))</div>
        <div class="chapter"><h2 id="c3">CHAPTER III.</h2>
        \(SyntheticEPUB.paragraphs(698, seed: 7))</div>
        """))
        epub.contents = [Entry("Chapter I", "part1.xhtml#c1"), Entry("Chapter II", "part1.xhtml#c2"),
                         Entry("Chapter III", "part2.xhtml#c3")]
        let book = try epub.read(in: self)

        XCTAssertEqual(book.titles, ["Chapter I", "Chapter II", "Chapter III"])
        XCTAssertEqual(book.chapters.map(\.provisionalWordCount), [600, 800, 700])
        XCTAssertEqual(book.chapters.map(\.locator), [
            EPUBLocator(href: "OEBPS/part1.xhtml", anchor: .id("c1")),
            EPUBLocator(href: "OEBPS/part1.xhtml", anchor: .id("c2")),
            EPUBLocator(href: "OEBPS/part2.xhtml", anchor: .id("c3")),
        ])
        XCTAssertEqual(book.chapters.map(\.spineHrefs), [
            ["OEBPS/part1.xhtml"], ["OEBPS/part1.xhtml", "OEBPS/part2.xhtml"], ["OEBPS/part2.xhtml"],
        ])
        let (first, second, third) = (book.chapters[0].xhtml, book.chapters[1].xhtml, book.chapters[2].xhtml)
        XCTAssertFalse(first.contains("CHAPTER II."), "a chapter stops at the next anchor")
        XCTAssertTrue(second.contains("CHAPTER II.") && second.contains("zircon"), "both halves of chapter II")
        XCTAssertFalse(third.contains("zircon"))
        XCTAssertTrue(third.hasPrefix("<div class=\"chapter\"><h2 id=\"c3\">CHAPTER III.</h2>"), third)
        XCTAssertTrue(book.chapters.allSatisfy { !$0.skipsInPlayback })
    }

    func testChapterMarkupReopensItsAncestorsAndIsWellFormed() throws {
        var epub = SyntheticEPUB()
        epub.addDocument("one.xhtml", body: SyntheticEPUB.xhtml(body: """
        <div class="group" id="g"><h2 id="a">Chapter A</h2>
        \(SyntheticEPUB.paragraphs(300))
        <h2 id="b">Chapter B</h2>
        <p>zircon &amp; \(SyntheticEPUB.words(298, seed: 4))<br/></p>
        </div>
        <style>p { color: red }</style>
        """))
        epub.contents = [Entry("A", "one.xhtml#a"), Entry("B", "one.xhtml#b")]
        let book = try epub.read(in: self)
        XCTAssertEqual(book.chapters.map(\.provisionalWordCount), [302, 301])
        let (a, b) = (book.chapters[0].xhtml, book.chapters[1].xhtml)
        XCTAssertTrue(a.contains("<div class=\"group\" id=\"g\"><h2 id=\"a\">Chapter A</h2>"), a)
        XCTAssertFalse(a.contains("Chapter B"))
        XCTAssertTrue(b.hasPrefix("<div class=\"group\" id=\"g\"><h2 id=\"b\">Chapter B</h2>"),
                      "the enclosing element opens again: \(b.prefix(80))")
        XCTAssertTrue(b.contains("zircon &amp; ") && b.contains("<br/></p>"))
        for xhtml in [a, b] {
            XCTAssertFalse(xhtml.contains("<style"))
            XCTAssertTrue(XMLParser(data: Data("<root>\(xhtml)</root>".utf8)).parse(), "well-formed: \(xhtml.prefix(80))")
        }
    }

    func testUnresolvedFragmentStartsAtTheFileAndEncodedFragmentsResolve() throws {
        var epub = SyntheticEPUB()
        epub.addDocument("one.xhtml", body: chapterFile("c1", "Chapter One", words: 500))
        epub.addDocument("two.xhtml", body: chapterFile("café", "Chapter Two", words: 500))
        epub.contents = [Entry("Chapter One", "one.xhtml#gone"), Entry("Chapter Two", "two.xhtml#caf%C3%A9")]
        let book = try epub.read(in: self)
        XCTAssertEqual(book.titles, ["Chapter One", "Chapter Two"])
        XCTAssertEqual(book.chapters.map(\.provisionalWordCount), [500, 500])
        XCTAssertEqual(book.chapters.map(\.locator), [
            EPUBLocator(href: "OEBPS/one.xhtml", anchor: .id("gone")),
            EPUBLocator(href: "OEBPS/two.xhtml", anchor: .id("café")),
        ])
    }

    // MARK: - Depth per branch

    /// Standard Ebooks' shape: every chapter nested under one top-level entry.
    func testChaptersNestedUnderOneTopLevelEntryAreCutAtTheirOwnLevel() throws {
        let book = try nestedBook(chapterWords: 8_000).read(in: self)
        XCTAssertEqual(book.titles, ["Title Page", "Chapter 1", "Chapter 2", "Chapter 3", "Chapter 4", "Chapter 5", "Afterword"])
        XCTAssertEqual(book.chapters.map(\.provisionalWordCount), [200, 8_002, 8_000, 8_000, 8_000, 8_000, 500],
                       "the two-word half-title merges into chapter 1")
        XCTAssertEqual(book.chapters[1].locator, EPUBLocator(href: "OEBPS/ch1.xhtml", anchor: .fileStart))
        assertBodyChaptersWithinBounds(book)
    }

    func testShortNestedBranchStaysOneChapter() throws {
        let book = try nestedBook(chapterWords: 3_000).read(in: self)
        XCTAssertEqual(book.titles, ["Title Page", "The Book", "Afterword"])
        XCTAssertEqual(book.chapters.map(\.provisionalWordCount), [200, 15_002, 500])
    }

    private func nestedBook(chapterWords: Int) -> SyntheticEPUB {
        var epub = SyntheticEPUB()
        epub.addDocument("title.xhtml", body: chapterFile("title", "Title Page", words: 200))
        epub.addDocument("half.xhtml", body: SyntheticEPUB.xhtml(body: "<h1>The Book</h1>"))
        for number in 1...5 {
            epub.addDocument("ch\(number).xhtml", body: chapterFile("c\(number)", "Chapter \(number)", words: chapterWords, seed: number))
        }
        epub.addDocument("after.xhtml", body: chapterFile("after", "Afterword", words: 500))
        epub.contents = [
            Entry("Title Page", "title.xhtml"),
            Entry("The Book", "half.xhtml", (1...5).map { Entry("Chapter \($0)", "ch\($0).xhtml") }),
            Entry("Afterword", "after.xhtml"),
        ]
        return epub
    }

    func testDepthIsChosenPerBranch() throws {
        var epub = SyntheticEPUB()
        let words = [6_000, 6_000, 6_000, 6_000, 6_000, 6_000, 16_000, 16_000]
        for (index, count) in words.enumerated() {
            epub.addDocument("ch\(index + 1).xhtml", body: chapterFile("c\(index + 1)", "Chapter \(index + 1)", words: count, seed: index))
        }
        func chapters(_ range: ClosedRange<Int>) -> [Entry] { range.map { Entry("Chapter \($0)", "ch\($0).xhtml") } }
        epub.contents = [
            Entry("Volume I", nil, [Entry("Part 1", nil, chapters(1...3)), Entry("Part 2", nil, chapters(4...6))]),
            Entry("Volume II", nil, [Entry("Part 3", nil, chapters(7...8))]),
        ]
        let book = try epub.read(in: self)
        XCTAssertEqual(book.titles, ["Part 1", "Part 2", "Chapter 7", "Chapter 8"],
                       "Volume I (36k) opens to its parts; Volume II and its one part (32k) open to chapters")
        XCTAssertEqual(book.chapters.map(\.provisionalWordCount), [18_000, 18_000, 16_000, 16_000])
        assertBodyChaptersWithinBounds(book)
    }

    // MARK: - Sparse contents

    /// Internet Archive's shape: one entry for the whole book.
    func testOneEntryContentsSplitsAtHeadings() throws {
        var epub = SyntheticEPUB()
        epub.addDocument("notice.xhtml", body: chapterFile("notice", "Notice", words: 80))
        for (index, name) in ["One", "Two", "Three"].enumerated() {
            epub.addDocument("s\(index + 1).xhtml", body: SyntheticEPUB.xhtml(body: "<h1>Story \(name)</h1>\n"
                + SyntheticEPUB.paragraphs(11_998, seed: index)))
        }
        epub.contents = [Entry("Notice", "notice.xhtml")]
        let book = try epub.read(in: self)
        XCTAssertEqual(book.titles, ["Story One", "Story Two", "Story Three"])
        XCTAssertEqual(book.chapters.map(\.provisionalWordCount), [12_080, 12_000, 12_000], "the short notice merges forward")
        XCTAssertEqual(book.chapters.map(\.locator.href), ["OEBPS/s1.xhtml", "OEBPS/s2.xhtml", "OEBPS/s3.xhtml"])
        assertBodyChaptersWithinBounds(book)
    }

    func testOneEntryContentsWithoutHeadingsGathersPageFiles() throws {
        var epub = SyntheticEPUB()
        for page in 1...40 {
            epub.addDocument("page\(page).xhtml", body: SyntheticEPUB.xhtml(body: SyntheticEPUB.paragraphs(1_000, seed: page)))
        }
        epub.contents = [Entry("Notice", "page1.xhtml")]
        let book = try epub.read(in: self)
        XCTAssertEqual(book.chapters.map(\.provisionalWordCount), [20_000, 20_000], "pages are gathered into chapters, not one each")
        XCTAssertEqual(book.titles, ["Notice", nil])
        XCTAssertEqual(book.chapters.map(\.locator), [
            EPUBLocator(href: "OEBPS/page1.xhtml", anchor: .fileStart), EPUBLocator(href: "OEBPS/page21.xhtml", anchor: .fileStart),
        ])
    }

    func testOneLongFileWithoutHeadingsSplitsBetweenBlocks() throws {
        var epub = SyntheticEPUB()
        epub.addDocument("all.xhtml", body: SyntheticEPUB.xhtml(body: SyntheticEPUB.paragraphs(35_000)))
        epub.contents = [Entry("Everything", "all.xhtml")]
        let book = try epub.read(in: self)
        XCTAssertEqual(book.chapters.map(\.provisionalWordCount), [17_520, 17_480])
        XCTAssertEqual(book.chapters.map(\.locator.href), ["OEBPS/all.xhtml", "OEBPS/all.xhtml"])
        XCTAssertNotEqual(book.chapters[0].locator, book.chapters[1].locator)
        assertBodyChaptersWithinBounds(book)
    }

    // MARK: - The maximum

    /// One file, one entry, three paragraphs of 15,000, 20,000 and 5,000 words: no piece passes
    /// 30,000 even though the first cut point past an even split would make a 35,000-word one.
    func testPiecesNeverPassTheMaximum() throws {
        var epub = SyntheticEPUB()
        epub.addDocument("all.xhtml", body: SyntheticEPUB.xhtml(body: """
        <p>\(SyntheticEPUB.words(15_000))</p>
        <p>\(SyntheticEPUB.words(20_000, seed: 1))</p>
        <p>\(SyntheticEPUB.words(5_000, seed: 2))</p>
        """))
        epub.contents = [Entry("Everything", "all.xhtml")]
        let book = try epub.read(in: self)
        XCTAssertEqual(book.chapters.map(\.provisionalWordCount), [15_000, 25_000])
        assertBodyChaptersWithinBounds(book)
    }

    /// One paragraph over the maximum is split between sentences.
    func testParagraphOverTheMaximumSplitsBetweenSentences() throws {
        let sentence = SyntheticEPUB.words(19) + " finch."
        var epub = SyntheticEPUB()
        epub.addDocument("all.xhtml", body: SyntheticEPUB.xhtml(body: "<p class=\"run\">" + Array(repeating: sentence, count: 1_800).joined(separator: " ") + "</p>"))
        epub.contents = [Entry("Everything", "all.xhtml")]
        let book = try epub.read(in: self)
        XCTAssertEqual(book.chapters.count, 2)
        guard book.chapters.count == 2 else { return }
        XCTAssertEqual(book.chapters.map(\.provisionalWordCount).reduce(0, +), 36_000)
        assertBodyChaptersWithinBounds(book)
        XCTAssertTrue(book.chapters[0].xhtml.contains("finch.</p>"), "the first part ends at a sentence's end")
        XCTAssertTrue(book.chapters[1].xhtml.hasPrefix("<p class=\"run\">"), "the paragraph opens again: \(book.chapters[1].xhtml.prefix(40))")
        XCTAssertEqual(book.chapters.map(\.provisionalWordCount).map { $0 % 20 }, [0, 0], "whole sentences on each side")
    }

    /// One paragraph over the maximum with no sentence ends is split between words.
    func testParagraphWithoutSentencesSplitsBetweenWords() throws {
        var epub = SyntheticEPUB()
        epub.addDocument("all.xhtml", body: SyntheticEPUB.xhtml(body: "<p>\(SyntheticEPUB.words(30_001))</p>"))
        epub.contents = [Entry("Everything", "all.xhtml")]
        let book = try epub.read(in: self)
        XCTAssertEqual(book.chapters.count, 2)
        XCTAssertEqual(book.chapters.map(\.provisionalWordCount).reduce(0, +), 30_001)
        assertBodyChaptersWithinBounds(book)
    }

    /// A cut at the last file would leave 60 words alone; the range is balanced between
    /// paragraphs instead.
    func testShortTailIsRebalanced() throws {
        var epub = SyntheticEPUB()
        epub.addDocument("long.xhtml", body: SyntheticEPUB.xhtml(body: SyntheticEPUB.paragraphs(29_950)))
        epub.addDocument("tail.xhtml", body: SyntheticEPUB.xhtml(body: SyntheticEPUB.paragraphs(60, seed: 1)))
        epub.contents = [Entry("Everything", "long.xhtml")]
        let book = try epub.read(in: self)
        XCTAssertEqual(book.chapters.count, 2)
        XCTAssertEqual(book.chapters.map(\.provisionalWordCount).reduce(0, +), 30_010)
        assertBodyChaptersWithinBounds(book)
    }

    /// The exception to the bar: a short chapter whose neighbours can't take it without passing
    /// the maximum stays short.
    func testShortChapterBetweenFullNeighboursStays() throws {
        var epub = SyntheticEPUB()
        epub.addDocument("a.xhtml", body: chapterFile("a", "Chapter A", words: 29_950))
        epub.addDocument("b.xhtml", body: chapterFile("b", "Interlude", words: 60, seed: 1))
        epub.addDocument("c.xhtml", body: chapterFile("c", "Chapter C", words: 29_950, seed: 2))
        epub.contents = [Entry("Chapter A", "a.xhtml"), Entry("Interlude", "b.xhtml"), Entry("Chapter C", "c.xhtml")]
        let book = try epub.read(in: self)
        XCTAssertEqual(book.titles, ["Chapter A", "Interlude", "Chapter C"])
        XCTAssertEqual(book.chapters.map(\.provisionalWordCount), [29_950, 60, 29_950])
    }

    /// The other exception: a whole book under 100 words is one short chapter.
    func testBookUnderAHundredWordsIsOneChapter() throws {
        var epub = SyntheticEPUB()
        epub.addDocument("one.xhtml", body: chapterFile("c1", "Note", words: 50))
        epub.contents = [Entry("Note", "one.xhtml")]
        let book = try epub.read(in: self)
        XCTAssertEqual(book.chapters.map(\.provisionalWordCount), [50])
        XCTAssertEqual(book.chapters.map(\.skipsInPlayback), [false])
    }

    // MARK: - Merging tiny entries

    func testTinyEntriesMergeIntoTheNextAndALastOneIntoThePrevious() throws {
        var epub = SyntheticEPUB()
        epub.addDocument("one.xhtml", body: SyntheticEPUB.xhtml(body: """
        <section id="epigraph"><p>\(SyntheticEPUB.words(30, seed: 9))</p></section>
        \(SyntheticEPUB.chapter(id: "c1", heading: "Chapter 1", words: 2_000))
        """))
        epub.addDocument("two.xhtml", body: SyntheticEPUB.xhtml(body: """
        \(SyntheticEPUB.chapter(id: "c2", heading: "Chapter 2", words: 2_000, seed: 1))
        <h1 id="part2">Part Two</h1>
        \(SyntheticEPUB.chapter(id: "c3", heading: "Chapter 3", words: 2_000, seed: 2))
        <p id="end">\(SyntheticEPUB.words(6, seed: 3))</p>
        """))
        epub.contents = [
            Entry("Epigraph", "one.xhtml#epigraph"), Entry("Chapter 1", "one.xhtml#c1"),
            Entry("Chapter 2", "two.xhtml#c2"), Entry("Part Two", "two.xhtml#part2"),
            Entry("Chapter 3", "two.xhtml#c3"), Entry("The End", "two.xhtml#end"),
        ]
        let book = try epub.read(in: self)
        XCTAssertEqual(book.titles, ["Chapter 1", "Chapter 2", "Chapter 3"])
        XCTAssertEqual(book.chapters.map(\.provisionalWordCount), [2_030, 2_000, 2_008])
        XCTAssertEqual(book.chapters.map(\.locator.fragment), ["c1", "c2", "c3"],
                       "the chapter a tiny entry merges into keeps its identity")
        XCTAssertTrue(book.chapters[0].xhtml.contains("id=\"epigraph\""))
        assertBodyChaptersWithinBounds(book)
    }

    /// A short chapter can't merge into an empty skipped range (a plate) before the next chapter;
    /// once the plate has joined that chapter, the short one is looked at again and merges too.
    func testShortChapterMergesOnceAnEmptySkippedRangeBesideItHasMerged() throws {
        var epub = SyntheticEPUB()
        epub.addDocument("prelude.xhtml", body: chapterFile("prelude", "Prelude", words: 60))
        epub.addDocument("plate.xhtml", body: SyntheticEPUB.xhtml(body: "<div><img src=\"plate.png\" alt=\"\"/></div>"))
        epub.addDocument("one.xhtml", body: chapterFile("c1", "Chapter 1", words: 400, seed: 1))
        epub.contents = [Entry("Prelude", "prelude.xhtml"), Entry("Plate", "plate.xhtml"), Entry("Chapter 1", "one.xhtml")]
        let book = try epub.read(in: self)
        XCTAssertEqual(book.titles, ["Chapter 1"])
        XCTAssertEqual(book.chapters.map(\.provisionalWordCount), [460])
        XCTAssertEqual(book.chapters.first?.locator, EPUBLocator(href: "OEBPS/one.xhtml", anchor: .fileStart),
                       "the chapter they merge into keeps its identity")
        assertBodyChaptersWithinBounds(book)
    }

    func testEntriesOnTheSameBlockMerge() throws {
        var epub = SyntheticEPUB()
        epub.addDocument("one.xhtml", body: chapterFile("c1", "Chapter 1", words: 900))
        epub.contents = [Entry("Illustration", "one.xhtml#c1"), Entry("Chapter 1", "one.xhtml#c1")]
        let book = try epub.read(in: self)
        XCTAssertEqual(book.titles, ["Chapter 1"])
        XCTAssertEqual(book.chapters.map(\.provisionalWordCount), [900])
    }

    // MARK: - No contents

    func testNoContentsFallsBackToHeadings() throws {
        var epub = SyntheticEPUB()
        epub.tableOfContents = .none
        epub.addDocument("one.xhtml", body: SyntheticEPUB.xhtml(body: """
        <h1>First Part</h1>\(SyntheticEPUB.paragraphs(500))
        <h1>Second Part</h1>\(SyntheticEPUB.paragraphs(500, seed: 1))
        """))
        epub.addDocument("two.xhtml", body: SyntheticEPUB.xhtml(body: "<h1>Third Part</h1>\(SyntheticEPUB.paragraphs(500, seed: 2))"))
        let book = try epub.read(in: self)
        XCTAssertTrue(book.contents.isEmpty)
        XCTAssertEqual(book.titles, ["First Part", "Second Part", "Third Part"])
        XCTAssertEqual(book.chapters.map(\.provisionalWordCount), [502, 502, 502])
    }

    func testNoContentsOrHeadingsCutsAtFiles() throws {
        var epub = SyntheticEPUB()
        epub.tableOfContents = .none
        for index in 1...3 {
            epub.addDocument("f\(index).xhtml", body: SyntheticEPUB.xhtml(body: SyntheticEPUB.paragraphs(300, seed: index)))
        }
        let book = try epub.read(in: self)
        XCTAssertEqual(book.titles, [nil, nil, nil])
        XCTAssertEqual(book.chapters.map(\.provisionalWordCount), [300, 300, 300])
        XCTAssertEqual(book.chapters.map(\.locator.href), ["OEBPS/f1.xhtml", "OEBPS/f2.xhtml", "OEBPS/f3.xhtml"])
    }
}
