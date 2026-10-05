import XCTest
@testable import Reader

/// The package document: `container.xml` → OPF, metadata, spine and cover, for EPUB2 and EPUB3.
final class EPUBPackageTests: XCTestCase {
    private func chapterBook(version: String = "3.0", contents: SyntheticEPUB.TableOfContents = .nav) -> SyntheticEPUB {
        var epub = SyntheticEPUB()
        epub.version = version
        epub.tableOfContents = contents
        epub.addDocument("one.xhtml", body: SyntheticEPUB.xhtml(body: SyntheticEPUB.chapter(id: "c1", heading: "Chapter One", words: 400)))
        epub.addDocument("two.xhtml", body: SyntheticEPUB.xhtml(body: SyntheticEPUB.chapter(id: "c2", heading: "Chapter Two", words: 500, seed: 3)))
        epub.contents = [.init("Chapter One", "one.xhtml"), .init("Chapter Two", "two.xhtml")]
        return epub
    }

    private func package(of epub: SyntheticEPUB) throws -> EPUBPackage {
        try EPUBPackage.read(from: EPUBContainer(fileURL: epub.write(in: self)), budget: MarkupBudget())
    }

    func testEPUB3MetadataTakesTheUniqueIdentifierMainTitleAndAuthors() throws {
        var epub = chapterBook()
        epub.title = nil
        epub.creators = [("Ada Example", nil)]
        epub.extraMetadata = """
        <dc:identifier id="other">urn:example:another-edition</dc:identifier>
        <dc:title id="sub">A Made-Up Subtitle</dc:title>
        <meta refines="#sub" property="title-type">subtitle</meta>
        <dc:title id="main">  The   Synthetic Book </dc:title>
        <meta refines="#main" property="title-type">main</meta>
        <dc:creator id="ill">Ivo Illustrator</dc:creator>
        <meta refines="#ill" property="role" scheme="marc:relators">ill</meta>
        <dc:creator id="co">Bo Example</dc:creator>
        <meta refines="#co" property="role" scheme="marc:relators">aut</meta>
        """
        let book = try epub.read(in: self)

        XCTAssertEqual(book.metadata.title, "The Synthetic Book", "the title refined as main, whitespace collapsed")
        XCTAssertEqual(book.metadata.identifier, "urn:uuid:5a1b2c3d-1111-4222-8333-944455556666",
                       "the identifier the package's unique-identifier names, not the first one")
        XCTAssertEqual(book.metadata.authors, ["Ada Example", "Bo Example"], "the illustrator isn't an author")
        XCTAssertEqual(book.metadata.language, "en")
        XCTAssertEqual(book.titles, ["Chapter One", "Chapter Two"])
        XCTAssertEqual(book.spineCount, 2)
    }

    func testEPUB2ReadsMetadataRolesAndItsNCX() throws {
        var epub = chapterBook(version: "2.0", contents: .ncx)
        epub.creators = [("Tia Translator", "trl"), ("Ada Example", "aut")]
        let package = try package(of: epub)
        XCTAssertEqual(package.version, "2.0")
        XCTAssertNil(package.navPath)
        XCTAssertEqual(package.ncxPath, "OEBPS/toc.ncx", "the NCX that spine@toc names")
        XCTAssertEqual(package.metadata.authors, ["Ada Example"])

        let book = try epub.read(in: self)
        XCTAssertEqual(book.titles, ["Chapter One", "Chapter Two"])
        XCTAssertEqual(book.chapters.map(\.provisionalWordCount), [400, 500])
    }

    func testSpineKeepsOrderAndLinearityAndLeavesOutNonTextItems() throws {
        var epub = chapterBook()
        epub.documents.insert(.init(name: "cover.xhtml", body: SyntheticEPUB.xhtml(body: "<p>Cover</p>"), linear: false), at: 0)
        epub.extraManifest = "<item id=\"pic\" href=\"images/plate.svg\" media-type=\"image/svg+xml\"/>"
        var spine = try package(of: epub).spine
        XCTAssertEqual(spine.map(\.path), ["OEBPS/cover.xhtml", "OEBPS/one.xhtml", "OEBPS/two.xhtml"])
        XCTAssertEqual(spine.map(\.linear), [false, true, true])

        // An SVG page in the spine is not text: it's left out.
        epub.extraManifest = "<item id=\"pic\" href=\"plate.svg\" media-type=\"image/svg+xml\"/>"
        var entries = epub.entries()
        let opfIndex = try XCTUnwrap(entries.firstIndex { $0.path == epub.opfPath })
        let opf = epub.opf().replacingOccurrences(of: "<itemref idref=\"d1\"/>", with: "<itemref idref=\"pic\"/>\n<itemref idref=\"d1\"/>")
        entries[opfIndex].data = Data(opf.utf8)
        spine = try EPUBPackage.read(from: EPUBContainer(fileURL: epub.write(in: self, entries: entries)), budget: MarkupBudget()).spine
        XCTAssertEqual(spine.map(\.path), ["OEBPS/cover.xhtml", "OEBPS/one.xhtml", "OEBPS/two.xhtml"])
    }

    func testCoverFromTheCoverImageProperty() throws {
        var epub = chapterBook()
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x01])
        epub.extraManifest = "<item id=\"img\" href=\"images/front.jpg\" media-type=\"image/jpeg\" properties=\"cover-image\"/>"
        epub.extraFiles = [(epub.path("images/front.jpg"), jpeg)]
        let cover = try XCTUnwrap(try epub.read(in: self).cover)
        XCTAssertEqual(cover.path, "OEBPS/images/front.jpg")
        XCTAssertEqual(cover.mediaType, "image/jpeg")
        XCTAssertEqual(cover.data, jpeg)
    }

    func testCoverFromMetaNameInEPUB2() throws {
        var epub = chapterBook(version: "2.0", contents: .ncx)
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        epub.extraMetadata = "<meta name=\"cover\" content=\"cover-img\"/>"
        epub.extraManifest = "<item id=\"cover-img\" href=\"cover.png\" media-type=\"image/png\"/>"
        epub.extraFiles = [(epub.path("cover.png"), png)]
        let cover = try XCTUnwrap(try epub.read(in: self).cover)
        XCTAssertEqual(cover.path, "OEBPS/cover.png")
        XCTAssertEqual(cover.data, png)
    }

    func testCoverFromTheGuidesCoverPage() throws {
        var epub = chapterBook(version: "2.0", contents: .ncx)
        let jpeg = Data([0xFF, 0xD8, 0x02])
        epub.addDocument("titlepage.xhtml", body: SyntheticEPUB.xhtml(body: "<div><img src=\"images/c%20over.jpg\" alt=\"\"/></div>"),
                         inSpine: false)
        epub.extraManifest = "<item id=\"img\" href=\"images/c%20over.jpg\" media-type=\"image/jpeg\"/>"
        epub.extraFiles = [(epub.path("images/c over.jpg"), jpeg)]
        epub.guide = [("cover", "titlepage.xhtml")]
        let cover = try XCTUnwrap(try epub.read(in: self).cover)
        XCTAssertEqual(cover.path, "OEBPS/images/c over.jpg", "the first image on the cover page, percent-decoded")
        XCTAssertEqual(cover.mediaType, "image/jpeg")
        XCTAssertEqual(cover.data, jpeg)
    }

    func testPackageAtTheTopLevelWithPercentEncodedHrefs() throws {
        var epub = SyntheticEPUB()
        epub.folder = ""
        epub.addDocument("chapter one.xhtml", body: SyntheticEPUB.xhtml(body: SyntheticEPUB.chapter(id: "c1", heading: "Chapter One", words: 300)))
        epub.contents = [.init("Chapter One", "chapter%20one.xhtml#c1")]
        var entries = epub.entries()
        let opfIndex = try XCTUnwrap(entries.firstIndex { $0.path == epub.opfPath })
        entries[opfIndex].data = Data(epub.opf().replacingOccurrences(of: "href=\"chapter one.xhtml\"",
                                                                      with: "href=\"chapter%20one.xhtml\"").utf8)
        let book = try EPUBBookReader.read(fileURL: epub.write(in: self, entries: entries))
        XCTAssertEqual(book.chapters.map(\.locator), [EPUBLocator(href: "chapter one.xhtml", anchor: .id("c1"))])
        XCTAssertEqual(book.chapters.first?.provisionalWordCount, 300)
    }

    func testEntitiesAndLooseMarkupInAChapterAreRead() throws {
        var epub = SyntheticEPUB()
        let body = """
        <section id="c1"><h2>Chapter&nbsp;One</h2>
        <p>amber &mdash; brook &amp; cinder&#x2019;s dune <b>ember</p>
        <p>fable <i>glade</i> harbor</p></section>
        <p>Stray &unknown; close</div> isle</p>
        <script>var x = "<p>never read</p>";</script>
        """
        epub.addDocument("one.xhtml", body: SyntheticEPUB.xhtml(body: body))
        epub.contents = [.init("Chapter One", "one.xhtml#c1")]
        let chapter = try XCTUnwrap(try epub.read(in: self).chapters.first)
        XCTAssertTrue(chapter.xhtml.contains("Chapter\u{00A0}One"), chapter.xhtml)
        XCTAssertTrue(chapter.xhtml.contains("amber \u{2014} brook &amp; cinder\u{2019}s dune <b>ember</b></p>"), chapter.xhtml)
        XCTAssertTrue(chapter.xhtml.contains("Stray &amp;unknown; close isle"), chapter.xhtml)
        XCTAssertFalse(chapter.xhtml.contains("never read"), "script content is never part of a chapter")
        XCTAssertFalse(chapter.xhtml.contains("<script"))
        XCTAssertEqual(chapter.provisionalWordCount, 14)
    }

    func testUTF16DocumentIsRead() throws {
        var epub = SyntheticEPUB()
        epub.addDocument("one.xhtml", body: "")
        epub.contents = [.init("Chapter One", "one.xhtml")]
        var entries = epub.entries()
        let index = try XCTUnwrap(entries.firstIndex { $0.path == epub.path("one.xhtml") })
        let xhtml = SyntheticEPUB.xhtml(body: SyntheticEPUB.chapter(id: "c1", heading: "Chapter One", words: 200))
            .replacingOccurrences(of: "encoding=\"UTF-8\"", with: "encoding=\"UTF-16\"")
        entries[index].data = try XCTUnwrap(xhtml.data(using: .utf16))
        let book = try EPUBBookReader.read(fileURL: epub.write(in: self, entries: entries))
        XCTAssertEqual(book.chapters.map(\.provisionalWordCount), [200])
    }

    // MARK: - Unreadable files

    func testFileThatIsNotAZipIsUnreadable() throws {
        let url = try SyntheticEPUB.write(Data("not a zip at all".utf8), in: self)
        assertEPUBError(try EPUBBookReader.read(fileURL: url), matches: { if case .unreadable = $0 { true } else { false } })
    }

    func testMissingContainerIsUnreadable() throws {
        var epub = chapterBook()
        epub.writesContainer = false
        assertEPUBError(try epub.read(in: self), matches: { if case .unreadable = $0 { true } else { false } })
    }

    func testContainerNamingAMissingPackageIsUnreadable() throws {
        let epub = chapterBook()
        let entries = epub.entries().filter { $0.path != epub.opfPath }
        assertEPUBError(try EPUBBookReader.read(fileURL: epub.write(in: self, entries: entries)),
                    matches: { if case .unreadable = $0 { true } else { false } })
    }

    func testBookWithNoTextIsUnreadable() throws {
        var epub = SyntheticEPUB()
        epub.addDocument("one.xhtml", body: SyntheticEPUB.xhtml(body: "<div><img src=\"a.jpg\" alt=\"\"/></div>"))
        epub.contents = [.init("Plate", "one.xhtml")]
        assertEPUBError(try epub.read(in: self), matches: { if case .unreadable = $0 { true } else { false } })
    }
}
