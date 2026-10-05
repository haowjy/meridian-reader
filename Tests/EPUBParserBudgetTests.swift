import XCTest
@testable import Reader

/// Markup the parser refuses or bounds: text files and nodes over their caps (per file and across
/// the book), nesting too deep, unmatched end tags (cheap at any depth), package XML that isn't
/// well-formed or declares entities (and package XML that only mentions one, which is read). Both
/// parsers charge the same budget; neither falls back.
final class EPUBParserBudgetTests: XCTestCase {
    private typealias Entry = SyntheticEPUB.Entry

    private func book() -> SyntheticEPUB {
        var epub = SyntheticEPUB()
        epub.addDocument("one.xhtml", body: SyntheticEPUB.xhtml(body: SyntheticEPUB.chapter(id: "c1", heading: "Chapter One", words: 400)))
        epub.addDocument("two.xhtml", body: SyntheticEPUB.xhtml(body: SyntheticEPUB.chapter(id: "c2", heading: "Chapter Two", words: 400, seed: 1)))
        epub.contents = [Entry("Chapter One", "one.xhtml"), Entry("Chapter Two", "two.xhtml")]
        return epub
    }

    private let isTooLarge: (EPUBError) -> Bool = { $0 == .tooLarge }
    private let isUnreadable: (EPUBError) -> Bool = { if case .unreadable = $0 { true } else { false } }

    /// The book's entries with the one at `path` replaced by `text`.
    private func entries(of epub: SyntheticEPUB, replacing path: String, with text: String) -> [TestZipWriter.Entry] {
        epub.entries().map { entry in
            guard entry.path == path else { return entry }
            var replaced = entry
            replaced.data = Data(text.utf8)
            return replaced
        }
    }

    private func limits(_ change: (inout EPUBLimits) -> Void) -> EPUBLimits {
        var limits = EPUBLimits.standard
        change(&limits)
        return limits
    }

    func testDefaultMarkupCaps() {
        let limits = EPUBLimits.standard
        XCTAssertEqual(limits.maxTextFileBytes, 16 * 1024 * 1024)
        XCTAssertEqual(limits.maxTextBytes, 64 * 1024 * 1024)
        XCTAssertEqual(limits.maxNestingDepth, 256)
        XCTAssertEqual(limits.maxNodesPerFile, 500_000)
        XCTAssertEqual(limits.maxNodes, 2_000_000)
    }

    // MARK: - Sizes and counts

    func testTextFileOverItsCapIsRefused() throws {
        var epub = book()
        epub.documents[1].body = SyntheticEPUB.xhtml(body: SyntheticEPUB.chapter(id: "c2", heading: "Chapter Two", words: 3_000))
        assertEPUBError(try epub.read(in: self, limits: limits { $0.maxTextFileBytes = 16 * 1024 }), matches: isTooLarge)
        XCTAssertNoThrow(try epub.read(in: self, limits: limits { $0.maxTextFileBytes = 64 * 1024 }))
    }

    func testTextAcrossTheBookOverItsCapIsRefused() throws {
        var epub = book()
        for index in epub.documents.indices {
            epub.documents[index].body = SyntheticEPUB.xhtml(body: SyntheticEPUB.chapter(id: "c\(index)", heading: "Chapter", words: 2_000, seed: index))
        }
        let fileCap = limits { $0.maxTextFileBytes = 32 * 1024 }
        XCTAssertNoThrow(try epub.read(in: self, limits: fileCap), "each file is under its cap")
        assertEPUBError(try epub.read(in: self, limits: limits { $0.maxTextFileBytes = 32 * 1024; $0.maxTextBytes = 24 * 1024 }),
                        matches: isTooLarge)
    }

    func testTooManyNodesInOneFileIsRefused() throws {
        var epub = book()
        epub.documents[1].body = SyntheticEPUB.xhtml(body: SyntheticEPUB.paragraphs(2_000, perParagraph: 10))
        assertEPUBError(try epub.read(in: self, limits: limits { $0.maxNodesPerFile = 300 }), matches: isTooLarge)
        XCTAssertNoThrow(try epub.read(in: self, limits: limits { $0.maxNodesPerFile = 1_000 }))
    }

    func testTooManyNodesAcrossTheBookIsRefused() throws {
        var epub = book()
        for index in epub.documents.indices {
            epub.documents[index].body = SyntheticEPUB.xhtml(body: SyntheticEPUB.paragraphs(1_000, seed: index, perParagraph: 10))
        }
        XCTAssertNoThrow(try epub.read(in: self, limits: limits { $0.maxNodesPerFile = 600; $0.maxNodes = 2_000 }))
        assertEPUBError(try epub.read(in: self, limits: limits { $0.maxNodesPerFile = 600; $0.maxNodes = 600 }),
                        matches: isTooLarge)
    }

    func testEndTagsThatMatchNothingCountAgainstTheBudget() throws {
        var epub = book()
        epub.documents[1].body = SyntheticEPUB.xhtml(body: SyntheticEPUB.paragraphs(300) + String(repeating: "</missing>", count: 2_000))
        assertEPUBError(try epub.read(in: self, limits: limits { $0.maxNodesPerFile = 1_000 }), matches: isTooLarge)
    }

    /// The package document is counted by the strict parser: over the cap is refused, never read
    /// again by a forgiving one.
    func testPackageOverTheNodeCapIsRefused() throws {
        let epub = book()
        let budget = MarkupBudget(limits: limits { $0.maxNodesPerFile = 25 })
        XCTAssertNoThrow(try XMLTree.parse(Data(epub.entries()[1].data), named: "container.xml", budget: budget),
                         "container.xml is under the cap")
        assertEPUBError(try epub.read(in: self, limits: limits { $0.maxNodesPerFile = 25 }), matches: isTooLarge)
    }

    // MARK: - Nesting

    func testChapterNestedTooDeeplyIsRefused() throws {
        var epub = book()
        let nested = String(repeating: "<div>", count: 300) + SyntheticEPUB.paragraphs(300) + String(repeating: "</div>", count: 300)
        epub.documents[1].body = SyntheticEPUB.xhtml(body: nested)
        assertEPUBError(try epub.read(in: self), matches: isTooLarge)
    }

    /// The nav (forgiving reader) nests two elements per level, the NCX (`XMLParser`) one.
    func testContentsNestedTooDeeplyIsRefused() throws {
        for (contents, levels) in [(SyntheticEPUB.TableOfContents.nav, 150), (.ncx, 300)] {
            var epub = book()
            epub.tableOfContents = contents
            var entry = Entry("Level \(levels)", "two.xhtml")
            for level in (1..<levels).reversed() {
                entry = Entry("Level \(level)", "one.xhtml", [entry])
            }
            epub.contents = [entry]
            assertEPUBError(try epub.read(in: self), matches: isTooLarge)
        }
    }

    /// An end tag nothing open matches is ignored without searching the open elements, so 100,000
    /// of them cost the same under 250 open elements as under one.
    func testUnmatchedEndTagsCostTheSameAtAnyDepth() throws {
        func seconds(depth: Int) throws -> TimeInterval {
            let markup = String(repeating: "<div>", count: depth) + "<p>amber</p>"
                + String(repeating: "</missing>", count: 100_000)
            let data = Data(markup.utf8)
            var best = TimeInterval.infinity
            for _ in 0..<2 {
                let start = Date()
                _ = try XHTMLReader.events(from: data, budget: MarkupBudget())
                best = min(best, Date().timeIntervalSince(start))
            }
            return best
        }
        let shallow = try seconds(depth: 1)
        let deep = try seconds(depth: 250)
        XCTAssertLessThan(deep, shallow * 4 + 0.1, "deep \(deep) s against shallow \(shallow) s")
    }

    // MARK: - Package XML

    func testXMLParserResolvesNoExternalEntity() {
        let parser = XMLTree.makeParser(Data())
        XCTAssertEqual(parser.externalEntityResolvingPolicy, .never)
        XCTAssertFalse(parser.shouldResolveExternalEntities)
    }

    func testEntityDeclarationsAreFoundInUTF16() throws {
        let xml = "<?xml version=\"1.0\" encoding=\"UTF-16\"?><!DOCTYPE p [<!ENTITY t \"x\">]><p>&t;</p>"
        for encoding in [String.Encoding.utf16LittleEndian, .utf16BigEndian] {
            let data = try XCTUnwrap(xml.data(using: encoding))
            XCTAssertTrue(XMLTree.declaresEntities(data))
            assertEPUBError(try XMLTree.parse(data, named: "p.xml", budget: MarkupBudget()),
                            matches: { if case .unreadable = $0 { true } else { false } })
        }
        XCTAssertFalse(XMLTree.declaresEntities(Data("<p>&amp; &lt;</p>".utf8)))
    }

    private let encodings: [String.Encoding] = [.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian]

    /// `<!ENTITY` written inside a comment, a CDATA section, a processing instruction or a quoted
    /// literal declares nothing: the document is read.
    func testEntityTextInCommentsCDATAAndLiteralsIsNotADeclaration() throws {
        let documents = [
            "<!-- <!ENTITY t \"x\"> --><p>amber</p>",
            "<p><![CDATA[<!ENTITY t \"x\">]]></p>",
            "<?note <!ENTITY t \"x\"> ?><p>amber</p>",
            "<!DOCTYPE p SYSTEM \"<!ENTITY t.dtd\"><p>amber</p>",
            "<!DOCTYPE p [<!-- <!ENTITY t \"x\"> --><!ELEMENT p (#PCDATA)>]><p>amber</p>",
        ]
        for document in documents {
            for encoding in encodings {
                let data = try XCTUnwrap(("<?xml version=\"1.0\"?>" + document).data(using: encoding))
                XCTAssertFalse(XMLTree.declaresEntities(data), "\(encoding): \(document)")
                XCTAssertNoThrow(try XMLTree.parse(data, named: "p.xml", budget: MarkupBudget()), "\(encoding): \(document)")
            }
        }
    }

    /// Declarations after a comment, a literal holding `>` or `[`, or a parameter entity are still
    /// found, in any encoding the parser reads.
    func testEntityDeclarationsAfterCommentsAndLiteralsAreFound() throws {
        let documents = [
            "<!DOCTYPE p [<!ENTITY t \"x\">]><p>&t;</p>",
            "<!DOCTYPE p [<!-- <!ENTITY a \"1\"> --><!ENTITY t \"x\">]><p>&t;</p>",
            "<!DOCTYPE p SYSTEM \"a>b[\" [<!ENTITY t \"x\">]><p>&t;</p>",
            "<!DOCTYPE p [<!ELEMENT p ANY><!ENTITY % pe \"x\">]><p>a</p>",
            "<!DOCTYPE p [<?note ?><!entity t \"x\">]><p>a</p>",
        ]
        for document in documents {
            for encoding in encodings + [.utf32LittleEndian, .utf32BigEndian] {
                let data = try XCTUnwrap(("<?xml version=\"1.0\"?>" + document).data(using: encoding))
                XCTAssertTrue(XMLTree.declaresEntities(data), "\(encoding): \(document)")
            }
            assertEPUBError(try XMLTree.parse(Data(document.utf8), named: "p.xml", budget: MarkupBudget()), matches: isUnreadable)
        }
    }

    /// The doctypes real package files carry name an external DTD and declare nothing: such a
    /// book reads, and the DTD isn't fetched.
    func testOrdinaryExternalDoctypesAreRead() throws {
        let opfDoctype = "<!DOCTYPE package PUBLIC \"+//ISBN 0-9673008-1-9//DTD OEB 1.2 Package//EN\" "
            + "\"http://openebook.org/dtds/oeb-1.2/oebpkg12.dtd\">"
        var epub = book()
        epub.version = "2.0"
        epub.tableOfContents = .ncx
        let opf = epub.opf().replacingOccurrences(of: "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
                                                  with: "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" + opfDoctype)
        XCTAssertFalse(XMLTree.declaresEntities(Data(opf.utf8)))
        XCTAssertFalse(XMLTree.declaresEntities(Data(epub.ncxDocument().utf8)), "the NCX's NISO doctype")
        let url = try epub.write(in: self, entries: entries(of: epub, replacing: epub.opfPath, with: opf))
        let read = try EPUBBookReader.read(fileURL: url)
        XCTAssertEqual(read.titles, ["Chapter One", "Chapter Two"])
    }

    func testContainerThatIsNotWellFormedIsRefused() throws {
        let epub = book()
        let container = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="\(epub.opfPath)" media-type="application/oebps-package+xml"/>
          </rootfilez>
        </container>
        """
        let url = try epub.write(in: self, entries: entries(of: epub, replacing: "META-INF/container.xml", with: container))
        assertEPUBError(try EPUBBookReader.read(fileURL: url), matches: isUnreadable)
    }

    func testPackageThatIsNotWellFormedIsRefused() throws {
        var epub = book()
        epub.title = "The Synthetic Book & Co"
        assertEPUBError(try epub.read(in: self), matches: isUnreadable)
    }

    func testNCXThatIsNotWellFormedIsRefused() throws {
        var epub = book()
        epub.version = "2.0"
        epub.tableOfContents = .ncx
        epub.contents = [Entry("Chapter One & More", "one.xhtml"), Entry("Chapter Two", "two.xhtml")]
        assertEPUBError(try epub.read(in: self), matches: isUnreadable)
    }

    /// Internal entities (expanded text, or a billion-laughs chain) and external ones (a file on
    /// the device) are refused before any is expanded or resolved.
    func testEntityDeclarationsInThePackageAreRefused() throws {
        let laughs = "<!ENTITY l0 \"ha\">" + (1...5).map { level in
            "<!ENTITY l\(level) \"" + String(repeating: "&l\(level - 1);", count: 10) + "\">"
        }.joined()
        let cases: [(doctype: String, reference: String)] = [
            ("<!DOCTYPE package [<!ENTITY t \"An Expanded Title\">]>", "&t;"),
            ("<!DOCTYPE package [\(laughs)]>", "&l5;"),
            ("<!DOCTYPE package [<!ENTITY ext SYSTEM \"file:///etc/hosts\">]>", "&ext;"),
        ]
        for (doctype, reference) in cases {
            var epub = book()
            epub.title = reference
            let opf = epub.opf().replacingOccurrences(of: "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
                                                      with: "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" + doctype)
            let url = try epub.write(in: self, entries: entries(of: epub, replacing: epub.opfPath, with: opf))
            assertEPUBError(try EPUBBookReader.read(fileURL: url), matches: isUnreadable)
        }
    }
}
