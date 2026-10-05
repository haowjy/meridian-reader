import XCTest
@testable import Reader

/// Refusals: DRM (an encrypted text document or a rights file; obfuscated fonts are fine), fixed
/// layout, zip bombs (size and entry caps, checked again while inflating), and paths that climb
/// out of the archive.
final class EPUBSecurityTests: XCTestCase {
    private func book() -> SyntheticEPUB {
        var epub = SyntheticEPUB()
        epub.addDocument("one.xhtml", body: SyntheticEPUB.xhtml(body: SyntheticEPUB.chapter(id: "c1", heading: "Chapter One", words: 400)))
        epub.addDocument("two.xhtml", body: SyntheticEPUB.xhtml(body: SyntheticEPUB.chapter(id: "c2", heading: "Chapter Two", words: 400, seed: 1)))
        epub.contents = [.init("Chapter One", "one.xhtml"), .init("Chapter Two", "two.xhtml")]
        return epub
    }

    private func encryptionXML(_ references: [(algorithm: String, uri: String)]) -> Data {
        let items = references.map { reference in
            """
            <enc:EncryptedData>
              <enc:EncryptionMethod Algorithm="\(reference.algorithm)"/>
              <enc:CipherData><enc:CipherReference URI="\(reference.uri)"/></enc:CipherData>
            </enc:EncryptedData>
            """
        }.joined(separator: "\n")
        return Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container" xmlns:enc="http://www.w3.org/2001/04/xmlenc#">
        \(items)
        </encryption>
        """.utf8)
    }

    private let isDRM: (EPUBError) -> Bool = { $0 == .drmProtected }
    private let isFixedLayout: (EPUBError) -> Bool = { $0 == .fixedLayout }
    private let isTooLarge: (EPUBError) -> Bool = { $0 == .tooLarge }

    // MARK: - DRM

    func testEncryptedSpineDocumentIsRefused() throws {
        var epub = book()
        epub.extraFiles = [("META-INF/encryption.xml", encryptionXML([
            ("http://www.w3.org/2001/04/xmlenc#aes128-cbc", "OEBPS/two.xhtml"),
        ]))]
        assertEPUBError(try epub.read(in: self), matches: isDRM)
    }

    func testEncryptedNavigationDocumentIsRefused() throws {
        var epub = book()
        epub.extraFiles = [("META-INF/encryption.xml", encryptionXML([
            ("http://www.w3.org/2001/04/xmlenc#aes256-cbc", "OEBPS/nav.xhtml"),
        ]))]
        assertEPUBError(try epub.read(in: self), matches: isDRM)
    }

    func testObfuscatedFontsAreAccepted() throws {
        var epub = book()
        epub.extraManifest = """
        <item id="f1" href="fonts/serif.otf" media-type="font/otf"/>
        <item id="f2" href="fonts/sans.ttf" media-type="font/ttf"/>
        """
        epub.extraFiles = [
            ("META-INF/encryption.xml", encryptionXML([
                ("http://www.idpf.org/2008/embedding", "OEBPS/fonts/serif.otf"),
                ("http://ns.adobe.com/pdf/enc#RC", "OEBPS/fonts/sans.ttf"),
            ])),
            (epub.path("fonts/serif.otf"), Data((0..<64).map { UInt8($0) })),
            (epub.path("fonts/sans.ttf"), Data((0..<64).map { UInt8(255 - $0) })),
        ]
        let book = try epub.read(in: self)
        XCTAssertEqual(book.titles, ["Chapter One", "Chapter Two"])
    }

    func testRightsFilesAreRefused() throws {
        for path in ["META-INF/rights.xml", "META-INF/license.lcpl", "META-INF/sinf.xml"] {
            var epub = book()
            epub.extraFiles = [(path, Data("<rights/>".utf8))]
            assertEPUBError(try epub.read(in: self), matches: isDRM)
        }
    }

    // MARK: - Fixed layout

    func testPrePaginatedBookIsRefused() throws {
        var epub = book()
        epub.extraMetadata = "<meta property=\"rendition:layout\">pre-paginated</meta>"
        assertEPUBError(try epub.read(in: self), matches: isFixedLayout)
    }

    func testEveryPagePrePaginatedIsRefused() throws {
        var epub = book()
        for index in epub.documents.indices { epub.documents[index].spineProperties = "rendition:layout-pre-paginated" }
        assertEPUBError(try epub.read(in: self), matches: isFixedLayout)
    }

    func testAppleFixedLayoutOptionIsRefused() throws {
        var epub = book()
        epub.extraFiles = [("META-INF/com.apple.ibooks.display-options.xml", Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <display_options><platform name="*"><option name="fixed-layout">true</option></platform></display_options>
        """.utf8))]
        assertEPUBError(try epub.read(in: self), matches: isFixedLayout)
    }

    func testOnePrePaginatedCoverPageIsAccepted() throws {
        var epub = book()
        epub.documents.insert(.init(name: "cover.xhtml", body: SyntheticEPUB.xhtml(body: "<p>Cover</p>"),
                                    spineProperties: "rendition:layout-pre-paginated"), at: 0)
        XCTAssertNoThrow(try epub.read(in: self))
    }

    // MARK: - Zip bombs

    func testDefaultCaps() {
        XCTAssertEqual(EPUBLimits.standard.maxUncompressedBytes, 200 * 1024 * 1024)
        XCTAssertEqual(EPUBLimits.standard.maxEntryCount, 5_000)
    }

    func testArchiveOverTheSizeCapIsRefused() throws {
        var epub = book()
        epub.extraFiles = [(epub.path("images/plate.bmp"), Data(count: 2 * 1024 * 1024))]
        let url = try epub.write(in: self)
        let limits = EPUBLimits(maxUncompressedBytes: 1024 * 1024, maxEntryCount: 5_000)
        assertEPUBError(try EPUBBookReader.read(fileURL: url, limits: limits), matches: isTooLarge)
        XCTAssertNoThrow(try EPUBBookReader.read(fileURL: url), "the same file is fine under the standard cap")
    }

    /// The headers claim 1 KB; the entry inflates to 4 MB of zeros. Reading stops as it inflates.
    func testEntryInflatingPastItsDeclaredSizeIsStopped() throws {
        let epub = book()
        let bomb = Data(count: 4 * 1024 * 1024)
        let entries = epub.entries().map { entry -> TestZipWriter.Entry in
            guard entry.path == epub.path("two.xhtml") else { return entry }
            return TestZipWriter.Entry(path: entry.path, data: bomb, compressed: true, declaredSize: 1_024)
        }
        let url = try epub.write(in: self, entries: entries)
        XCTAssertLessThan(try Data(contentsOf: url).count, 64 * 1024, "the fixture is small on disk")
        assertEPUBError(try EPUBBookReader.read(fileURL: url), matches: isTooLarge)
    }

    func testTooManyEntriesAreRefused() throws {
        var epub = book()
        epub.extraFiles = (1...12).map { (epub.path("misc/file\($0).txt"), Data("x".utf8)) }
        let url = try epub.write(in: self)
        let limits = EPUBLimits(maxUncompressedBytes: 200 * 1024 * 1024, maxEntryCount: 10)
        assertEPUBError(try EPUBBookReader.read(fileURL: url, limits: limits), matches: isTooLarge)
        XCTAssertNoThrow(try EPUBBookReader.read(fileURL: url))
    }

    // MARK: - Paths

    func testEntryNamesThatClimbOutAreRefused() throws {
        for unsafe in ["../evil.xhtml", "OEBPS/../../evil.xhtml", "/etc/evil.xhtml", "C:\\evil.xhtml", "OEBPS\\..\\..\\evil.xhtml"] {
            let epub = book()
            let entries = epub.entries() + [TestZipWriter.Entry(path: unsafe, data: Data("<p>x</p>".utf8))]
            assertEPUBError(try EPUBBookReader.read(fileURL: epub.write(in: self, entries: entries)),
                            matches: { $0 == .unsafePath(unsafe) })
        }
    }

    func testHrefsThatClimbOutOfTheArchiveAreNeverFollowed() throws {
        XCTAssertNil(EPUBPath.resolve("../../outside.xhtml", relativeTo: "OEBPS/content.opf"))
        XCTAssertNil(EPUBPath.resolve("https://example.com/remote.xhtml", relativeTo: "OEBPS/content.opf"))
        XCTAssertEqual(EPUBPath.resolve("../shared/a.xhtml#x", relativeTo: "OEBPS/text/b.xhtml")?.path, "OEBPS/shared/a.xhtml")
        XCTAssertEqual(EPUBPath.resolve("#x", relativeTo: "OEBPS/b.xhtml")?.path, "OEBPS/b.xhtml")
        XCTAssertEqual(EPUBPath.resolve("./a%20b.xhtml?q=1#f%C3%A9", relativeTo: "OEBPS/b.xhtml")?.fragment, "fé")

        var epub = book()
        epub.extraManifest = "<item id=\"out\" href=\"../../outside.xhtml\" media-type=\"application/xhtml+xml\"/>"
        var entries = epub.entries()
        let opfIndex = try XCTUnwrap(entries.firstIndex { $0.path == epub.opfPath })
        let opf = epub.opf().replacingOccurrences(of: "<itemref idref=\"d0\"/>", with: "<itemref idref=\"out\"/>\n<itemref idref=\"d0\"/>")
        entries[opfIndex].data = Data(opf.utf8)
        let book = try EPUBBookReader.read(fileURL: epub.write(in: self, entries: entries))
        XCTAssertEqual(book.spineCount, 2, "the escaping item is dropped, not read")
        XCTAssertEqual(book.titles, ["Chapter One", "Chapter Two"])
    }
}
