#if DEBUG
import Foundation
import ZIPFoundation

/// `-importTestEPUB` (Debug builds only): an EPUB built here in code from text written for this
/// app (the demo book's chapters), so a probe can import a book through the real pipeline
/// (`BookImporter`) and play it. A title page, which is front matter, then three chapters. The
/// first opens with a line that sits loose in a `<div>` and carries a footnote, so the
/// normalizer's work shows on screen.
enum TestEPUB {
    static let title = "Imported Demo Folder"
    /// Its file's name, as *Import Book…* and the test pages' link give it.
    static let fileName = "the-imported-demo-book.epub"
    static let author = DemoBook.author
    static let identifier = "urn:uuid:7e57e9b0-0000-4000-8000-000000000001"
    static let looseLine = "This line sits loose in a div, and is read all the same."
    static let footnote = "A footnote, which is never read inside the chapter."

    /// What an earlier import of it is found by: the identifier is usable, so the file doesn't
    /// count.
    static var bookKey: UUID { BookIdentity.bookKey(identifier: identifier, title: title, fileFingerprint: "") }

    static var chapterTitles: [String] { DemoBook.chapters.dropFirst().map(\.title) }

    static func write(to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        let archive = try Archive(url: url, accessMode: .create)
        // OCF: `mimetype` first, stored.
        try add("mimetype", "application/epub+zip", to: archive, compressed: false)
        try add("META-INF/container.xml", container, to: archive)
        try add("OEBPS/content.opf", package, to: archive)
        try add("OEBPS/nav.xhtml", xhtml(navigation), to: archive)
        for (name, body) in documents { try add("OEBPS/\(name)", xhtml(body), to: archive) }
    }

    /// The EPUB's bytes (the test pages serve them).
    static func data() throws -> Data {
        let file = FileManager.default.temporaryDirectory.appending(path: "served-\(UUID().uuidString).epub")
        defer { try? FileManager.default.removeItem(at: file) }
        try write(to: file)
        return try Data(contentsOf: file)
    }

    private static func add(_ path: String, _ text: String, to archive: Archive, compressed: Bool = true) throws {
        let data = Data(text.utf8)
        try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count),
                             compressionMethod: compressed ? .deflate : .none) { position, size in
            data.subdata(in: Int(position)..<Int(position) + size)
        }
    }

    private static var documents: [(name: String, body: String)] {
        var out: [(name: String, body: String)] = [("title.xhtml", "<section epub:type=\"titlepage\"><h1>\(title)</h1><p>\(author)</p></section>")]
        for (index, chapter) in DemoBook.chapters.dropFirst().enumerated() {
            var body = chapter.paragraphs.map { "<p>\($0)</p>" }.joined(separator: "\n")
            if index == 0 {
                body = "<div>\(looseLine)</div>\n" + body
                    + "\n<p>The end of the chapter<a epub:type=\"noteref\" href=\"#fn1\">1</a>.</p>"
                    + "\n<aside epub:type=\"footnote\" id=\"fn1\"><p>\(footnote)</p></aside>"
            }
            out.append(("chapter-\(index + 1).xhtml", "<section id=\"c\(index + 1)\"><h2>\(chapter.title)</h2>\n\(body)</section>"))
        }
        return out
    }

    private static let container = """
    <?xml version="1.0" encoding="UTF-8"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
    <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
    </container>
    """

    private static var package: String {
        let items = documents.enumerated().map { "<item id=\"d\($0)\" href=\"\($1.name)\" media-type=\"application/xhtml+xml\"/>" }
        let spine = documents.indices.map { "<itemref idref=\"d\($0)\"/>" }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        <dc:identifier id="bookid">\(identifier)</dc:identifier>
        <dc:title>\(title)</dc:title>
        <dc:creator>\(author)</dc:creator>
        <dc:language>en</dc:language>
        </metadata>
        <manifest>
        <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
        \(items.joined(separator: "\n"))
        </manifest>
        <spine>\(spine.joined())</spine>
        </package>
        """
    }

    private static var navigation: String {
        let entries = [("Title Page", "title.xhtml")]
            + chapterTitles.enumerated().map { ($1, "chapter-\($0 + 1).xhtml#c\($0 + 1)") }
        return """
        <nav epub:type="toc"><ol>
        \(entries.map { "<li><a href=\"\($1)\">\($0)</a></li>" }.joined(separator: "\n"))
        </ol></nav>
        <nav epub:type="landmarks"><ol><li><a epub:type="bodymatter" href="chapter-1.xhtml#c1">Start</a></li></ol></nav>
        """
    }

    private static func xhtml(_ body: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="en">
        <head><title>\(title)</title></head>
        <body>
        \(body)
        </body>
        </html>
        """
    }
}
#endif
