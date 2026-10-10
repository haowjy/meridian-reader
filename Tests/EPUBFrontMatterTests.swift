import XCTest
@testable import MeridianReader

/// Front and back matter are skipped as whole chapters, and only chapters wholly inside them:
/// landmarks, the EPUB2 guide, `epub:type`, `linear="no"`, short unlisted pages, and
/// Gutenberg's header and licence.
final class EPUBFrontMatterTests: XCTestCase {
    private typealias Entry = SyntheticEPUB.Entry

    private func file(_ id: String, _ heading: String, words: Int, seed: Int = 0) -> String {
        SyntheticEPUB.xhtml(body: SyntheticEPUB.chapter(id: id, heading: heading, words: words, seed: seed))
    }

    func testLandmarksBodymatterSkipsWhatComesBeforeIt() throws {
        var epub = SyntheticEPUB()
        epub.addDocument("titlepage.xhtml", body: file("title", "Title Page", words: 60))
        epub.addDocument("copyright.xhtml", body: file("copyright", "Copyright", words: 120, seed: 1))
        epub.addDocument("ch1.xhtml", body: file("c1", "Chapter 1", words: 2_000, seed: 2))
        epub.addDocument("ch2.xhtml", body: file("c2", "Chapter 2", words: 2_000, seed: 3))
        epub.landmarks = [("titlepage", "titlepage.xhtml"), ("bodymatter", "ch1.xhtml")]
        epub.contents = [Entry("Title Page", "titlepage.xhtml"), Entry("Copyright", "copyright.xhtml"),
                         Entry("Chapter 1", "ch1.xhtml"), Entry("Chapter 2", "ch2.xhtml")]
        let book = try epub.read(in: self)
        XCTAssertEqual(book.titles, ["Copyright", "Chapter 1", "Chapter 2"], "the short title page merges into the copyright page")
        XCTAssertEqual(book.chapters.map(\.provisionalWordCount), [180, 2_000, 2_000])
        XCTAssertEqual(book.chapters.map(\.skipsInPlayback), [true, false, false])
    }

    func testGuideTextSkipsWhatComesBeforeIt() throws {
        var epub = SyntheticEPUB()
        epub.version = "2.0"
        epub.tableOfContents = .ncx
        epub.addDocument("preface.xhtml", body: file("preface", "Preface", words: 300))
        epub.addDocument("ch1.xhtml", body: file("c1", "Chapter 1", words: 2_000, seed: 1))
        epub.addDocument("ch2.xhtml", body: file("c2", "Chapter 2", words: 2_000, seed: 2))
        epub.guide = [("cover", "preface.xhtml"), ("text", "ch1.xhtml")]
        epub.contents = [Entry("Preface", "preface.xhtml"), Entry("Chapter 1", "ch1.xhtml"), Entry("Chapter 2", "ch2.xhtml")]
        let book = try epub.read(in: self)
        XCTAssertEqual(book.chapters.map(\.skipsInPlayback), [true, false, false])
    }

    func testLandmarksBackmatterSkipsWhatComesAfterIt() throws {
        var epub = SyntheticEPUB()
        epub.addDocument("ch1.xhtml", body: file("c1", "Chapter 1", words: 2_000))
        epub.addDocument("notes.xhtml", body: file("notes", "Notes", words: 500, seed: 1))
        epub.addDocument("about.xhtml", body: file("about", "About the Author", words: 300, seed: 2))
        epub.landmarks = [("bodymatter", "ch1.xhtml"), ("backmatter", "notes.xhtml")]
        epub.contents = [Entry("Chapter 1", "ch1.xhtml"), Entry("Notes", "notes.xhtml"), Entry("About the Author", "about.xhtml")]
        let book = try epub.read(in: self)
        XCTAssertEqual(book.chapters.map(\.skipsInPlayback), [false, true, true])
    }

    func testEpubTypeFrontAndBackMatterAreSkipped() throws {
        var epub = SyntheticEPUB()
        epub.addDocument("dedication.xhtml", body: SyntheticEPUB.xhtml(
            body: SyntheticEPUB.chapter(id: "dedication", heading: "Dedication", words: 200),
            bodyAttributes: "epub:type=\"frontmatter\""))
        epub.addDocument("ch1.xhtml", body: SyntheticEPUB.xhtml(body: SyntheticEPUB.chapter(id: "c1", heading: "Chapter 1", words: 2_000, seed: 1)
            + "\n<section epub:type=\"backmatter colophon\" id=\"colophon\"><h2>Colophon</h2>\(SyntheticEPUB.paragraphs(200))</section>"))
        epub.contents = [Entry("Dedication", "dedication.xhtml"), Entry("Chapter 1", "ch1.xhtml#c1"),
                         Entry("Colophon", "ch1.xhtml#colophon")]
        let book = try epub.read(in: self)
        XCTAssertEqual(book.titles, ["Dedication", "Chapter 1", "Colophon"])
        XCTAssertEqual(book.chapters.map(\.skipsInPlayback), [true, false, true])
        XCTAssertEqual(book.chapters.map(\.provisionalWordCount), [200, 2_000, 201])
    }

    func testNonLinearSpineItemIsSkipped() throws {
        var epub = SyntheticEPUB()
        epub.addDocument("ch1.xhtml", body: file("c1", "Chapter 1", words: 2_000))
        epub.addDocument("plates.xhtml", body: file("plates", "List of Plates", words: 300, seed: 1), linear: false)
        epub.addDocument("ch2.xhtml", body: file("c2", "Chapter 2", words: 2_000, seed: 2))
        epub.contents = [Entry("Chapter 1", "ch1.xhtml"), Entry("List of Plates", "plates.xhtml"), Entry("Chapter 2", "ch2.xhtml")]
        let book = try epub.read(in: self)
        XCTAssertEqual(book.chapters.map(\.skipsInPlayback), [false, true, false])
    }

    func testNonLinearPageNoEntryNamesIsItsOwnSkippedChapter() throws {
        var epub = SyntheticEPUB()
        epub.addDocument("ch1.xhtml", body: file("c1", "Chapter 1", words: 2_000))
        epub.addDocument("plates.xhtml", body: file("plates", "List of Plates", words: 300, seed: 1), linear: false)
        epub.addDocument("ch2.xhtml", body: file("c2", "Chapter 2", words: 2_000, seed: 2))
        epub.contents = [Entry("Chapter 1", "ch1.xhtml"), Entry("Chapter 2", "ch2.xhtml")]
        let book = try epub.read(in: self)
        XCTAssertEqual(book.titles, ["Chapter 1", "List of Plates", "Chapter 2"], "never read inside chapter 1")
        XCTAssertEqual(book.chapters.map(\.provisionalWordCount), [2_000, 300, 2_000])
        XCTAssertEqual(book.chapters.map(\.skipsInPlayback), [false, true, false])
    }

    func testNavInTheSpineIsSkipped() throws {
        var epub = SyntheticEPUB()
        epub.addDocument("title.xhtml", body: file("title", "Title Page", words: 200))
        epub.addDocument("ch1.xhtml", body: file("c1", "Chapter 1", words: 2_000, seed: 1))
        epub.addDocument("ch2.xhtml", body: file("c2", "Chapter 2", words: 2_000, seed: 2))
        epub.contents = [Entry("Title Page", "title.xhtml"), Entry("Chapter 1", "ch1.xhtml"), Entry("Chapter 2", "ch2.xhtml")]
        var entries = epub.entries()
        let opfIndex = try XCTUnwrap(entries.firstIndex { $0.path == epub.opfPath })
        let opf = epub.opf().replacingOccurrences(of: "<itemref idref=\"d1\"/>", with: "<itemref idref=\"nav\"/>\n<itemref idref=\"d1\"/>")
        entries[opfIndex].data = Data(opf.utf8)
        let book = try EPUBBookReader.read(fileURL: epub.write(in: self, entries: entries))
        XCTAssertEqual(book.spineCount, 4)
        XCTAssertEqual(book.titles, ["Title Page", "Contents", "Chapter 1", "Chapter 2"])
        XCTAssertEqual(book.chapters.map(\.provisionalWordCount), [200, 7, 2_000, 2_000])
        XCTAssertEqual(book.chapters.map(\.skipsInPlayback), [false, true, false, false])
        XCTAssertFalse(book.chapters[0].xhtml.contains("Contents"), "the contents page isn't read with the title page")
    }

    func testShortPageNoEntryNamesIsSkipped() throws {
        var epub = SyntheticEPUB()
        epub.addDocument("cover.xhtml", body: SyntheticEPUB.xhtml(body: "<div><img src=\"cover.jpg\" alt=\"\"/><p>The Synthetic Book</p></div>"))
        epub.addDocument("ch1.xhtml", body: file("c1", "Chapter 1", words: 2_000))
        epub.addDocument("ch2.xhtml", body: file("c2", "Chapter 2", words: 2_000, seed: 1))
        epub.contents = [Entry("Chapter 1", "ch1.xhtml"), Entry("Chapter 2", "ch2.xhtml")]
        let book = try epub.read(in: self)
        XCTAssertEqual(book.titles, [nil, "Chapter 1", "Chapter 2"])
        XCTAssertEqual(book.chapters.map(\.provisionalWordCount), [3, 2_000, 2_000], "a skipped page never merges into the body")
        XCTAssertEqual(book.chapters.map(\.skipsInPlayback), [true, false, false])
    }

    func testLongerPageNoEntryNamesIsKept() throws {
        var epub = SyntheticEPUB()
        epub.addDocument("foreword.xhtml", body: file("foreword", "Foreword", words: 300))
        epub.addDocument("ch1.xhtml", body: file("c1", "Chapter 1", words: 2_000, seed: 1))
        epub.contents = [Entry("Chapter 1", "ch1.xhtml")]
        let book = try epub.read(in: self)
        XCTAssertEqual(book.titles, ["Foreword", "Chapter 1"], "titled by its heading")
        XCTAssertEqual(book.chapters.map(\.skipsInPlayback), [false, false])
    }

    func testTinyFrontMatterNeverMergesIntoTheBody() throws {
        var epub = SyntheticEPUB()
        epub.addDocument("dedication.xhtml", body: SyntheticEPUB.xhtml(body: "<p>\(SyntheticEPUB.words(10))</p>",
                                                                       bodyAttributes: "epub:type=\"frontmatter\""))
        epub.addDocument("ch1.xhtml", body: file("c1", "Chapter 1", words: 2_000, seed: 1))
        epub.contents = [Entry("Dedication", "dedication.xhtml"), Entry("Chapter 1", "ch1.xhtml")]
        let book = try epub.read(in: self)
        XCTAssertEqual(book.titles, ["Dedication", "Chapter 1"])
        XCTAssertEqual(book.chapters.map(\.provisionalWordCount), [10, 2_000])
        XCTAssertEqual(book.chapters.map(\.skipsInPlayback), [true, false])
    }

    /// Standard Ebooks' shape: a top-level entry starts on a front-matter half-title and holds
    /// the body start. Skipping by where it starts would skip the novel.
    func testChapterHoldingTheBodyStartIsNotSkipped() throws {
        var epub = SyntheticEPUB()
        epub.addDocument("halftitle.xhtml", body: SyntheticEPUB.xhtml(body: "<h2>The Book</h2><p>\(SyntheticEPUB.words(20))</p>",
                                                                      bodyAttributes: "epub:type=\"frontmatter\""))
        epub.addDocument("ch1.xhtml", body: file("c1", "Chapter 1", words: 2_000, seed: 1))
        epub.addDocument("ch2.xhtml", body: file("c2", "Chapter 2", words: 2_000, seed: 2))
        epub.landmarks = [("bodymatter", "ch1.xhtml")]
        epub.contents = [Entry("The Book", "halftitle.xhtml", [Entry("Chapter 1", "ch1.xhtml"), Entry("Chapter 2", "ch2.xhtml")])]
        let book = try epub.read(in: self)
        XCTAssertEqual(book.titles, ["The Book"])
        XCTAssertEqual(book.chapters.map(\.provisionalWordCount), [4_022])
        XCTAssertEqual(book.chapters.map(\.skipsInPlayback), [false])
    }

    /// Gutenberg's header and licence become chapters of their own, skipped; the short title area
    /// between the header and chapter 1 merges into chapter 1, and the licence's opening (before
    /// the heading the contents names) into the licence.
    func testGutenbergHeaderAndLicenceAreTheirOwnSkippedChapters() throws {
        var epub = SyntheticEPUB()
        epub.addDocument("wrap.xhtml", body: SyntheticEPUB.xhtml(body: """
        <section class="pg-boilerplate pgheader" id="pg-header"><h2>Project Example Header</h2>
        <p>\(SyntheticEPUB.words(200, seed: 1))</p></section>
        <h1>The Synthetic Book</h1><p>\(SyntheticEPUB.words(58, seed: 2))</p>
        \(SyntheticEPUB.chapter(id: "c1", heading: "Chapter 1", words: 1_500, seed: 3))
        """))
        epub.addDocument("ch2.xhtml", body: file("c2", "Chapter 2", words: 1_500, seed: 4))
        epub.addDocument("end.xhtml", body: SyntheticEPUB.xhtml(body: """
        \(SyntheticEPUB.chapter(id: "c3", heading: "Chapter 3", words: 1_500, seed: 5))
        <section class="pg-boilerplate pgheader" id="pg-footer"><p>\(SyntheticEPUB.words(200, seed: 6))</p>
        <h2 id="pg-footer-heading">Licence</h2><p>\(SyntheticEPUB.words(3_000, seed: 7))</p></section>
        """))
        epub.contents = [Entry("Chapter 1", "wrap.xhtml#c1"), Entry("Chapter 2", "ch2.xhtml"),
                         Entry("Chapter 3", "end.xhtml#c3"), Entry("The Licence", "end.xhtml#pg-footer-heading")]
        let book = try epub.read(in: self)
        XCTAssertEqual(book.titles, ["Project Example Header", "Chapter 1", "Chapter 2", "Chapter 3", "The Licence"])
        XCTAssertEqual(book.chapters.map(\.skipsInPlayback), [true, false, false, false, true])
        XCTAssertEqual(book.chapters.map(\.provisionalWordCount), [203, 1_561, 1_500, 1_500, 3_201],
                       "the licence's opening, which no entry names, joins the licence")
        XCTAssertFalse(book.chapters[3].xhtml.contains("Licence"), "chapter 3 stops where the licence starts")
        assertBodyChaptersWithinBounds(book)
    }
}
