import Foundation
import XCTest
@testable import MeridianReader

/// Builds EPUB files from strings for tests. Every word in them is generated here, so no book
/// text enters the repo.
struct SyntheticEPUB {
    enum TableOfContents {
        /// An EPUB3 nav document.
        case nav
        /// An EPUB2 NCX, named by `spine@toc`.
        case ncx
        /// Both; the nav should win.
        case both
        case none
    }

    struct Document {
        var name: String
        var body: String
        var bodyAttributes = ""
        var inSpine = true
        var linear = true
        var spineProperties: String?
    }

    /// A contents entry; `href` is relative to the OPF's folder (where the nav and NCX live too).
    struct Entry {
        var title: String
        var href: String?
        var children: [Entry] = []

        init(_ title: String, _ href: String?, _ children: [Entry] = []) {
            self.title = title
            self.href = href
            self.children = children
        }
    }

    var version = "3.0"
    var folder = "OEBPS"
    var title: String? = "The Synthetic Book"
    var creators: [(name: String, role: String?)] = [("Ada Example", nil)]
    var language: String? = "en"
    var identifier: String? = "urn:uuid:5a1b2c3d-1111-4222-8333-944455556666"
    /// Raw XML added to `<metadata>`.
    var extraMetadata = ""
    /// Raw XML added to `<manifest>`.
    var extraManifest = ""
    var documents: [Document] = []
    var tableOfContents: TableOfContents = .nav
    var contents: [Entry] = []
    /// EPUB3 landmarks: (epub:type, href).
    var landmarks: [(type: String, href: String)] = []
    /// EPUB2 guide references: (type, href).
    var guide: [(type: String, href: String)] = []
    /// Files added as they are, by archive path.
    var extraFiles: [(path: String, data: Data)] = []
    var writesContainer = true

    var opfPath: String { folder.isEmpty ? "content.opf" : folder + "/content.opf" }

    mutating func addDocument(_ name: String, body: String, bodyAttributes: String = "", inSpine: Bool = true,
                              linear: Bool = true, spineProperties: String? = nil) {
        documents.append(Document(name: name, body: body, bodyAttributes: bodyAttributes, inSpine: inSpine,
                                  linear: linear, spineProperties: spineProperties))
    }

    // MARK: - Writing

    /// The archive's entries, `mimetype` first and stored, as OCF asks.
    func entries() -> [TestZipWriter.Entry] {
        var entries = [TestZipWriter.Entry(path: "mimetype", data: Data("application/epub+zip".utf8), compressed: false)]
        if writesContainer {
            entries.append(.init(path: "META-INF/container.xml", data: Data(containerXML.utf8)))
        }
        entries.append(.init(path: opfPath, data: Data(opf().utf8)))
        for document in documents {
            entries.append(.init(path: path(document.name), data: Data(document.body.utf8)))
        }
        if tableOfContents == .nav || tableOfContents == .both {
            entries.append(.init(path: path("nav.xhtml"), data: Data(navDocument().utf8)))
        }
        if tableOfContents == .ncx || tableOfContents == .both {
            entries.append(.init(path: path("toc.ncx"), data: Data(ncxDocument().utf8)))
        }
        for file in extraFiles {
            entries.append(.init(path: file.path, data: file.data))
        }
        return entries
    }

    /// Writes the book to a temporary file, removed when the test ends.
    func write(in testCase: XCTestCase, entries: [TestZipWriter.Entry]? = nil) throws -> URL {
        try Self.write(TestZipWriter.archive(entries ?? self.entries()), in: testCase)
    }

    static func write(_ data: Data, in testCase: XCTestCase) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SyntheticEPUB-\(UUID().uuidString).epub")
        try data.write(to: url)
        testCase.addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func read(in testCase: XCTestCase, limits: EPUBLimits = .standard,
              rules: EPUBCutRules = .standard) throws -> EPUBBook {
        try EPUBBookReader.read(fileURL: try write(in: testCase), limits: limits, rules: rules)
    }

    func path(_ name: String) -> String {
        folder.isEmpty ? name : folder + "/" + name
    }

    private var containerXML: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="\(opfPath)" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """
    }

    func opf() -> String {
        var metadata = ""
        if let identifier { metadata += "<dc:identifier id=\"bookid\">\(identifier)</dc:identifier>\n" }
        if let title { metadata += "<dc:title>\(title)</dc:title>\n" }
        for creator in creators {
            let role = creator.role.map { " opf:role=\"\($0)\"" } ?? ""
            metadata += "<dc:creator\(role)>\(creator.name)</dc:creator>\n"
        }
        if let language { metadata += "<dc:language>\(language)</dc:language>\n" }
        metadata += extraMetadata

        var manifest = ""
        var spine = ""
        for (index, document) in documents.enumerated() {
            manifest += "<item id=\"d\(index)\" href=\"\(document.name)\" media-type=\"application/xhtml+xml\"/>\n"
            guard document.inSpine else { continue }
            let linear = document.linear ? "" : " linear=\"no\""
            let properties = document.spineProperties.map { " properties=\"\($0)\"" } ?? ""
            spine += "<itemref idref=\"d\(index)\"\(linear)\(properties)/>\n"
        }
        if tableOfContents == .nav || tableOfContents == .both {
            manifest += "<item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/>\n"
        }
        let writesNCX = tableOfContents == .ncx || tableOfContents == .both
        if writesNCX {
            manifest += "<item id=\"ncx\" href=\"toc.ncx\" media-type=\"application/x-dtbncx+xml\"/>\n"
        }
        manifest += extraManifest
        let guideXML = guide.isEmpty ? "" : "<guide>\n" + guide.map {
            "<reference type=\"\($0.type)\" title=\"\($0.type)\" href=\"\($0.href)\"/>"
        }.joined(separator: "\n") + "\n</guide>"
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" xmlns:opf="http://www.idpf.org/2007/opf" \
        version="\(version)" unique-identifier="bookid">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        \(metadata)</metadata>
        <manifest>
        \(manifest)</manifest>
        <spine\(writesNCX ? " toc=\"ncx\"" : "")>
        \(spine)</spine>
        \(guideXML)
        </package>
        """
    }

    func navDocument() -> String {
        func list(_ entries: [Entry]) -> String {
            "<ol>\n" + entries.map { entry in
                let label = entry.href.map { "<a href=\"\($0)\">\(entry.title)</a>" } ?? "<span>\(entry.title)</span>"
                return "<li>\(label)\(entry.children.isEmpty ? "" : list(entry.children))</li>\n"
            }.joined() + "</ol>"
        }
        var body = "<nav epub:type=\"toc\" id=\"toc\"><h1>Contents</h1>\(list(contents))</nav>\n"
        if !landmarks.isEmpty {
            body += "<nav epub:type=\"landmarks\" hidden=\"\"><ol>\n" + landmarks.map {
                "<li><a epub:type=\"\($0.type)\" href=\"\($0.href)\">\($0.type)</a></li>"
            }.joined(separator: "\n") + "\n</ol></nav>\n"
        }
        return Self.xhtml(body: body)
    }

    func ncxDocument() -> String {
        var order = 0
        func points(_ entries: [Entry]) -> String {
            entries.map { entry in
                order += 1
                let content = entry.href.map { "<content src=\"\($0)\"/>" } ?? ""
                return """
                <navPoint id="np\(order)" playOrder="\(order)"><navLabel><text>\(entry.title)</text></navLabel>\
                \(content)\(points(entry.children))</navPoint>

                """
            }.joined()
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN" "http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
        <head><meta name="dtb:uid" content="\(identifier ?? "")"/></head>
        <docTitle><text>\(title ?? "")</text></docTitle>
        <navMap>
        \(points(contents))</navMap>
        </ncx>
        """
    }

    // MARK: - Content

    static func xhtml(body: String, bodyAttributes: String = "", title: String = "Section") -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="en">
        <head><title>\(title)</title><link rel="stylesheet" type="text/css" href="style.css"/></head>
        <body\(bodyAttributes.isEmpty ? "" : " " + bodyAttributes)>
        \(body)
        </body>
        </html>
        """
    }

    /// Made-up words: deterministic filler with no source.
    private static let vocabulary = [
        "amber", "brook", "cinder", "dune", "ember", "fable", "glade", "harbor", "isle", "juniper",
        "kestrel", "lantern", "meadow", "nectar", "orchard", "pebble", "quill", "river", "sparrow",
        "thistle", "umber", "valley", "willow", "yarrow", "zephyr", "copper", "hollow", "marble",
    ]

    static func words(_ count: Int, seed: Int = 0) -> String {
        (0..<count).map { vocabulary[(($0 &* 7) &+ seed &* 13) % vocabulary.count] }.joined(separator: " ")
    }

    /// `<p>` blocks of filler totalling exactly `count` words.
    static func paragraphs(_ count: Int, seed: Int = 0, perParagraph: Int = 120) -> String {
        var remaining = count
        var blocks: [String] = []
        var paragraph = 0
        while remaining > 0 {
            let size = min(perParagraph, remaining)
            blocks.append("<p>\(words(size, seed: seed &+ paragraph))</p>")
            remaining -= size
            paragraph += 1
        }
        return blocks.joined(separator: "\n")
    }

    /// A chapter body: a section with an id, an `h2` heading, then filler; `words` in all.
    static func chapter(id: String, heading: String, words: Int, seed: Int = 0) -> String {
        let filler = paragraphs(max(0, words - EPUBWordCount.count(heading)), seed: seed)
        return "<section id=\"\(id)\"><h2>\(heading)</h2>\n\(filler)</section>"
    }
}

extension EPUBBook {
    var bodyChapters: [EPUBChapter] { chapters.filter { !$0.skipsInPlayback } }
    var titles: [String?] { chapters.map(\.title) }
}

/// Asserts that `expression` throws an `EPUBError` that `matches` accepts.
func assertEPUBError<T>(_ expression: @autoclosure () throws -> T, matches: (EPUBError) -> Bool,
                        file: StaticString = #filePath, line: UInt = #line) {
    do {
        _ = try expression()
        XCTFail("expected an EPUBError", file: file, line: line)
    } catch let error as EPUBError {
        XCTAssertTrue(matches(error), "unexpected \(error)", file: file, line: line)
    } catch {
        XCTFail("unexpected \(error)", file: file, line: line)
    }
}

/// The pass bar for cutting, on provisional (raw XHTML) counts: no body chapter under 100 or over
/// 30,000 words. Not for books where a short chapter can't merge (`EPUBChapterCutter`'s exception).
func assertBodyChaptersWithinBounds(_ book: EPUBBook, file: StaticString = #filePath, line: UInt = #line) {
    for chapter in book.bodyChapters {
        XCTAssertTrue((100...30_000).contains(chapter.provisionalWordCount),
                      "\(chapter.title ?? "untitled") has \(chapter.provisionalWordCount) words", file: file, line: line)
    }
}
