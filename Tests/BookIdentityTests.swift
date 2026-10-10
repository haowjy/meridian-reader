import XCTest
@testable import Reader

/// Book and chapter keys: the same file gives the same keys on every import (they're audio cache
/// keys), chapters cut from one file differ by anchor, markup that doesn't change the text keeps
/// them, delimiters inside names can't make two keys collide, and the values are pinned.
final class BookIdentityTests: XCTestCase {
    private let identifier = "urn:uuid:5a1b2c3d-1111-4222-8333-944455556666"

    private func book() -> SyntheticEPUB {
        var epub = SyntheticEPUB()
        epub.addDocument("one.xhtml", body: SyntheticEPUB.xhtml(body: SyntheticEPUB.chapter(id: "c1", heading: "Chapter 1", words: 600)
            + SyntheticEPUB.chapter(id: "c2", heading: "Chapter 2", words: 600, seed: 1)))
        epub.addDocument("two.xhtml", body: SyntheticEPUB.xhtml(body: SyntheticEPUB.chapter(id: "c3", heading: "Chapter 3", words: 600, seed: 2)))
        epub.contents = [.init("Chapter 1", "one.xhtml#c1"), .init("Chapter 2", "one.xhtml#c2"), .init("Chapter 3", "two.xhtml")]
        return epub
    }

    func testKeysAreStableAcrossReimport() throws {
        let epub = book()
        let first = try epub.read(in: self)
        let again = try epub.read(in: self)
        XCTAssertEqual(first.key, again.key)
        XCTAssertEqual(first.chapters.map(\.key), again.chapters.map(\.key))
        XCTAssertEqual(first.fileFingerprint, again.fileFingerprint)
        XCTAssertEqual(Set(first.chapters.map(\.key)).count, 3, "chapters cut from one file have distinct keys")
    }

    /// Values computed independently (Python's hashlib) from the encoding `BookIdentity`
    /// documents: SHA-256(namespace, 0x00, each field as an 8-byte big-endian length and UTF-8).
    func testKeysArePinned() {
        let bookKey = BookIdentity.bookKey(identifier: identifier, title: "The Synthetic Book", fileFingerprint: "unused")
        XCTAssertEqual(bookKey, UUID(uuidString: "31D26ED1-281A-1031-D40C-8BBEA3945C6D"))
        XCTAssertEqual(BookIdentity.chapterKey(bookKey: bookKey, locator: EPUBLocator(href: "OEBPS/one.xhtml", anchor: .id("c1"))),
                       UUID(uuidString: "81AD420D-EE6D-4A42-D7FC-2A04BBF8D5D6"))
        XCTAssertEqual(BookIdentity.chapterKey(bookKey: bookKey, locator: EPUBLocator(href: "OEBPS/one.xhtml", anchor: .fileStart)),
                       UUID(uuidString: "C90A3BF9-B286-EC43-1212-7C250353EBA0"))
        XCTAssertEqual(EPUBChapterCutter.fingerprint("The Fourth Part"), "ed50ac4e342a9e3ab904a19361f454e2")
        let text = EPUBLocator(href: "OEBPS/two.xhtml", anchor: .text(fingerprint: "ed50ac4e342a9e3ab904a19361f454e2", occurrence: 0))
        XCTAssertEqual(BookIdentity.chapterKey(bookKey: bookKey, locator: text),
                       UUID(uuidString: "5B8A68ED-965D-672F-91CF-D0E8475BFEAC"))
        XCTAssertEqual(BookIdentity.bookKey(identifier: nil, title: "Anything", fileFingerprint: "abc123"),
                       UUID(uuidString: "8A0B28E3-57E0-C941-FAF6-A71A4371B295"))
    }

    func testChapterKeysDifferByAnchorAndByBook() {
        let bookKey = BookIdentity.bookKey(identifier: identifier, title: "The Synthetic Book", fileFingerprint: "")
        let otherBook = BookIdentity.bookKey(identifier: "urn:example:other", title: "The Synthetic Book", fileFingerprint: "")
        let keys = [
            BookIdentity.chapterKey(bookKey: bookKey, locator: EPUBLocator(href: "OEBPS/one.xhtml", anchor: .fileStart)),
            BookIdentity.chapterKey(bookKey: bookKey, locator: EPUBLocator(href: "OEBPS/one.xhtml", anchor: .text(fingerprint: "c1", occurrence: 0))),
            BookIdentity.chapterKey(bookKey: bookKey, locator: EPUBLocator(href: "OEBPS/one.xhtml", anchor: .text(fingerprint: "c1", occurrence: 1))),
            BookIdentity.chapterKey(bookKey: bookKey, locator: EPUBLocator(href: "OEBPS/one.xhtml", anchor: .id("c1"))),
            BookIdentity.chapterKey(bookKey: bookKey, locator: EPUBLocator(href: "OEBPS/one.xhtml", anchor: .id("c2"))),
            BookIdentity.chapterKey(bookKey: bookKey, locator: EPUBLocator(href: "OEBPS/two.xhtml", anchor: .id("c1"))),
            BookIdentity.chapterKey(bookKey: otherBook, locator: EPUBLocator(href: "OEBPS/one.xhtml", anchor: .id("c1"))),
        ]
        XCTAssertEqual(Set(keys).count, keys.count)
        XCTAssertNotEqual(keys[1], ArticleIdentity.articleKey(canonicalURL: "OEBPS/one.xhtml"),
                          "a chapter key never collides with a web article key")
    }

    /// A book with no contents cut at headings with no ids, and a long file cut between paragraphs:
    /// attributes, whitespace between blocks and inline tags don't move any key.
    private func derivedCutsBook(decorated: Bool) -> SyntheticEPUB {
        func paragraph(_ count: Int, seed: Int) -> String {
            let words = SyntheticEPUB.words(count, seed: seed).split(separator: " ").map(String.init)
            guard decorated else { return "<p>\(words.joined(separator: " "))</p>" }
            let inline = "<i>\(words[0])</i> <span class=\"x\"><b>\(words[1])</b></span> " + words.dropFirst(2).joined(separator: " ")
            return "<p class=\"para\" style=\"margin: 0\">\n  \(inline)\n</p>\n\n"
        }
        func paragraphs(_ count: Int, seed: Int) -> String {
            (0..<count).map { paragraph(100, seed: seed + $0) }.joined()
        }
        var epub = SyntheticEPUB()
        epub.tableOfContents = .none
        let heading = decorated ? "<h1 class=\"title\">The <em>Second</em> Part</h1>" : "<h1>The Second Part</h1>"
        epub.addDocument("one.xhtml", body: SyntheticEPUB.xhtml(body: "<h1>The First Part</h1>" + paragraphs(5, seed: 0)
            + heading + paragraphs(5, seed: 10)))
        epub.addDocument("two.xhtml", body: SyntheticEPUB.xhtml(body: "<h1>The Third Part</h1>" + paragraphs(5, seed: 20)
            + "<h1>The Fourth Part</h1>" + paragraphs(350, seed: 30)))
        return epub
    }

    func testMarkupThatDoesNotChangeTheTextKeepsTheKeys() throws {
        let plain = try derivedCutsBook(decorated: false).read(in: self)
        let decorated = try derivedCutsBook(decorated: true).read(in: self)
        XCTAssertEqual(plain.titles, ["The First Part", "The Second Part", "The Third Part", "The Fourth Part", nil])
        XCTAssertEqual(decorated.chapters.map(\.provisionalWordCount), plain.chapters.map(\.provisionalWordCount))
        XCTAssertEqual(decorated.chapters.map(\.key), plain.chapters.map(\.key))
        XCTAssertEqual(plain.chapters[3].locator, EPUBLocator(href: "OEBPS/two.xhtml", anchor: .text(
            fingerprint: EPUBChapterCutter.fingerprint("The Fourth Part"), occurrence: 0)), "a heading with no id: a text anchor")
        XCTAssertEqual(Set(plain.chapters.map(\.key)).count, plain.chapters.count)
    }

    // MARK: - Anchors from where a cut falls

    /// A book with no contents (cut at `h1` headings): each file's sections as given, every
    /// section 300 words after its heading.
    private func headingsBook(_ files: [[String]]) -> SyntheticEPUB {
        var epub = SyntheticEPUB()
        epub.tableOfContents = .none
        var seed = 0
        for (index, sections) in files.enumerated() {
            let body = sections.map { section -> String in
                seed += 1
                return section.replacingOccurrences(of: "FILLER", with: SyntheticEPUB.paragraphs(300, seed: seed))
            }.joined()
            epub.addDocument("f\(index + 1).xhtml", body: "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
                + "<html xmlns=\"http://www.w3.org/1999/xhtml\"><head><title>Part</title></head><body>\(body)</body></html>")
        }
        return epub
    }

    /// Whitespace, a comment or a wrapper without an id before a heading, at the top of a file or
    /// inside it, doesn't move any key.
    func testWhitespaceAndWrappersBeforeAHeadingKeepTheKeys() throws {
        let variants: [(String) -> String] = [
            { "<h1>\($0)</h1>FILLER" },
            { "\n\n  <h1>\($0)</h1>\nFILLER\n" },
            { "<!-- page -->\n<h1>\($0)</h1>FILLER" },
            { "<div class=\"part\">\n<h1>\($0)</h1>FILLER</div>\n" },
        ]
        let books = try variants.map { section in
            try headingsBook([[section("Part 1"), section("Part 2")], [section("Part 3"), section("Part 4")]]).read(in: self)
        }
        let fingerprint = { (text: String) in EPUBChapterCutter.fingerprint(text) }
        XCTAssertEqual(books[0].chapters.map(\.locator), [
            EPUBLocator(href: "OEBPS/f1.xhtml", anchor: .fileStart),
            EPUBLocator(href: "OEBPS/f1.xhtml", anchor: .text(fingerprint: fingerprint("Part 2"), occurrence: 0)),
            EPUBLocator(href: "OEBPS/f2.xhtml", anchor: .fileStart),
            EPUBLocator(href: "OEBPS/f2.xhtml", anchor: .text(fingerprint: fingerprint("Part 4"), occurrence: 0)),
        ])
        for (index, book) in books.enumerated().dropFirst() {
            XCTAssertEqual(book.chapters.map(\.locator), books[0].chapters.map(\.locator), "variant \(index)")
            XCTAssertEqual(book.chapters.map(\.key), books[0].chapters.map(\.key), "variant \(index)")
        }
    }

    /// An id on a heading, or on an element opened just before it with no words between, is the
    /// chapter's anchor wherever the heading is, at the top of a file or not.
    func testAnIDOnOrAroundAHeadingIsTheAnchor() throws {
        let variants: [(String, String) -> String] = [
            { "<h1 id=\"\($1)\">\($0)</h1>FILLER" },
            { "\n<h1 id=\"\($1)\">\($0)</h1>\nFILLER" },
            { "<div class=\"part\">\n<h1 id=\"\($1)\">\($0)</h1>FILLER</div>" },
            { "<section id=\"\($1)\">\n<h1>\($0)</h1>FILLER</section>" },
        ]
        let books = try variants.map { section in
            try headingsBook([[section("Part 1", "p1"), section("Part 2", "p2")]]).read(in: self)
        }
        for (index, book) in books.enumerated() {
            XCTAssertEqual(book.chapters.map(\.locator), [
                EPUBLocator(href: "OEBPS/f1.xhtml", anchor: .id("p1")),
                EPUBLocator(href: "OEBPS/f1.xhtml", anchor: .id("p2")),
            ], "variant \(index)")
            XCTAssertEqual(book.chapters.map(\.key), books[0].chapters.map(\.key), "variant \(index)")
        }
    }

    /// Gutenberg's shape: the header (skipped matter no entry names), an empty element, then the
    /// first chapter's heading, whose id the contents names. The empty range between them joins
    /// the chapter, so the header keeps the id at the top of the file and the chapter its own.
    func testHeaderBeforeAnEmptyElementKeepsItsOwnAnchor() throws {
        var epub = SyntheticEPUB()
        epub.addDocument("book.xhtml", body: SyntheticEPUB.xhtml(body: """
        <header class="pg-boilerplate pgheader" id="pg-header"><p>\(SyntheticEPUB.words(120, seed: 7))</p></header><div/>
        <h1 id="start">The Book</h1>
        \(SyntheticEPUB.paragraphs(600))
        """))
        epub.contents = [SyntheticEPUB.Entry("The Book", "book.xhtml#start")]
        let book = try epub.read(in: self)
        XCTAssertEqual(book.chapters.map(\.skipsInPlayback), [true, false])
        XCTAssertEqual(book.chapters.map(\.provisionalWordCount), [120, 602])
        XCTAssertEqual(book.chapters.map(\.locator), [
            EPUBLocator(href: "OEBPS/book.xhtml", anchor: .id("pg-header")),
            EPUBLocator(href: "OEBPS/book.xhtml", anchor: .id("start")),
        ])
    }

    /// A text anchor is the first block at the chapter's own cut: a short range merging into the
    /// chapter (or not) doesn't change it.
    func testAChapterKeepsItsKeyWhetherOrNotAShortRangeMergesIntoIt() throws {
        func book(epigraphWords: Int) throws -> EPUBBook {
            let epigraph = "<h1>Epigraph</h1><p>\(SyntheticEPUB.words(epigraphWords, seed: 50))</p>"
            return try headingsBook([["<h1>Part 1</h1>FILLER", epigraph, "<h1>Part 2</h1>FILLER"]]).read(in: self)
        }
        let merged = try book(epigraphWords: 30)
        let apart = try book(epigraphWords: 200)
        XCTAssertEqual(merged.titles, ["Part 1", "Part 2"], "the 31-word epigraph merges into Part 2")
        XCTAssertEqual(apart.titles, ["Part 1", "Epigraph", "Part 2"])
        XCTAssertEqual(merged.chapters[1].locator, EPUBLocator(href: "OEBPS/f1.xhtml", anchor: .text(
            fingerprint: EPUBChapterCutter.fingerprint("Part 2"), occurrence: 0)))
        XCTAssertEqual(merged.chapters[1].key, apart.chapters[2].key)
    }

    /// Chapters with no anchor of the book's own whose first blocks match are numbered by order
    /// in their file, counting every earlier chapter that starts the same way. An id added to an
    /// earlier one keeps the later numbers. **Known limitation:** another chapter starting the same
    /// way, added before them, renumbers them, so their keys move to other chapters' text.
    func testChaptersThatStartAlikeAreToldApartByOrder() throws {
        /// Sections by seed: a heading, then 300 words of the seed's own filler.
        func book(_ sections: [(heading: String, seed: Int)]) throws -> EPUBBook {
            try headingsBook([sections.map { "\($0.heading)<p>\(SyntheticEPUB.words(300, seed: $0.seed))</p>" }]).read(in: self)
        }
        let interlude = EPUBChapterCutter.fingerprint("Interlude")
        let plain = try book([("<h1>Opening</h1>", 1), ("<h1>Interlude</h1>", 2), ("<h1>Interlude</h1>", 3), ("<h1>Interlude</h1>", 4)])
        XCTAssertEqual(plain.chapters.map(\.locator.anchor), [
            .fileStart,
            .text(fingerprint: interlude, occurrence: 0),
            .text(fingerprint: interlude, occurrence: 1),
            .text(fingerprint: interlude, occurrence: 2),
        ])

        let withID = try book([("<h1>Opening</h1>", 1), ("<h1 id=\"i2\">Interlude</h1>", 2), ("<h1>Interlude</h1>", 3), ("<h1>Interlude</h1>", 4)])
        XCTAssertEqual(withID.chapters[1].locator.anchor, .id("i2"))
        XCTAssertEqual(withID.chapters[2...].map(\.key), plain.chapters[2...].map(\.key), "an id on an earlier chapter renumbers nothing")

        let inserted = try book([("<h1>Opening</h1>", 1), ("<h1>Interlude</h1>", 9), ("<h1>Interlude</h1>", 2),
                                 ("<h1>Interlude</h1>", 3), ("<h1>Interlude</h1>", 4)])
        XCTAssertEqual(inserted.chapters[0].key, plain.chapters[0].key)
        XCTAssertEqual(Set(inserted.chapters.map(\.key)).count, 5)
        // The known limitation: the interlude with seed 2's text was occurrence 0 and is now 1, so
        // it carries the key the seed 3 interlude had.
        XCTAssertEqual(inserted.chapters[2].xhtml, plain.chapters[1].xhtml)
        XCTAssertNotEqual(inserted.chapters[2].key, plain.chapters[1].key)
        XCTAssertEqual(inserted.chapters[2].key, plain.chapters[2].key)
    }

    func testDelimitersInsideNamesDontCollide() {
        let bookKey = BookIdentity.bookKey(identifier: identifier, title: "The Synthetic Book", fileFingerprint: "")
        let pairs = [
            (EPUBLocator(href: "a.xhtml#b", anchor: .id("c")), EPUBLocator(href: "a.xhtml", anchor: .id("b#c"))),
            (EPUBLocator(href: "a.xhtml", anchor: .fileStart), EPUBLocator(href: "a.xhtml", anchor: .id(""))),
            (EPUBLocator(href: "a.xhtml", anchor: .id("start")), EPUBLocator(href: "a.xhtml", anchor: .fileStart)),
            (EPUBLocator(href: "a.xhtml", anchor: .text(fingerprint: "ab", occurrence: 12)),
             EPUBLocator(href: "a.xhtml", anchor: .text(fingerprint: "ab1", occurrence: 2))),
            (EPUBLocator(href: "a\u{0}b", anchor: .id("c")), EPUBLocator(href: "a", anchor: .id("b\u{0}c"))),
        ]
        for (first, second) in pairs {
            XCTAssertNotEqual(BookIdentity.chapterKey(bookKey: bookKey, locator: first),
                              BookIdentity.chapterKey(bookKey: bookKey, locator: second), "\(first) vs \(second)")
        }
        let fingerprint = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        XCTAssertNotEqual(BookIdentity.bookKey(identifier: "file", title: fingerprint, fileFingerprint: "unused"),
                          BookIdentity.bookKey(identifier: nil, title: nil, fileFingerprint: fingerprint),
                          "an identifier and title never collide with a file's fingerprint")
    }

    func testTitleSeparatesEditionsSharingAnIdentifier() {
        let epub3 = BookIdentity.bookKey(identifier: identifier, title: "The Synthetic Book", fileFingerprint: "a")
        let illustrated = BookIdentity.bookKey(identifier: identifier, title: "The Synthetic Book, Illustrated", fileFingerprint: "b")
        XCTAssertNotEqual(epub3, illustrated)
        XCTAssertEqual(BookIdentity.bookKey(identifier: identifier, title: "The Synthetic Book", fileFingerprint: "b"), epub3,
                       "with a real identifier, the file's bytes don't matter")
    }

    func testWhitespaceDoesNotChangeTheKey() {
        let plain = BookIdentity.bookKey(identifier: identifier, title: "The Synthetic Book", fileFingerprint: "")
        XCTAssertEqual(BookIdentity.bookKey(identifier: "  \(identifier)\n", title: "The  Synthetic\nBook ", fileFingerprint: ""), plain)
    }

    func testPlaceholderIdentifierFallsBackToTheFile() throws {
        for placeholder in [nil, "", "  ", "urn:uuid:00000000-0000-0000-0000-000000000000", "00000000-0000-0000-0000-000000000000"] {
            XCTAssertNil(BookIdentity.usableIdentifier(placeholder), placeholder ?? "nil")
        }
        XCTAssertEqual(BookIdentity.usableIdentifier(" urn:isbn:9990000000017 "), "urn:isbn:9990000000017")

        var first = book()
        first.identifier = "urn:uuid:00000000-0000-0000-0000-000000000000"
        var second = first
        second.documents[1].body = SyntheticEPUB.xhtml(body: SyntheticEPUB.chapter(id: "c3", heading: "Chapter 3", words: 700, seed: 9))
        let a = try first.read(in: self)
        let b = try second.read(in: self)
        XCTAssertNotEqual(a.key, b.key, "two different files sharing a placeholder identifier and title stay apart")
        XCTAssertEqual(a.key, BookIdentity.bookKey(identifier: nil, title: nil, fileFingerprint: a.fileFingerprint))
        XCTAssertEqual(try first.read(in: self).key, a.key, "the same file still gets the same key")
    }

    func testFileFingerprintIsTheFilesSHA256() throws {
        let url = try SyntheticEPUB.write(Data("abc".utf8), in: self)
        XCTAssertEqual(try BookIdentity.fileFingerprint(of: url),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
