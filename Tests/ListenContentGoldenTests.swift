import XCTest
@testable import Reader

/// Web extraction is Readability, then the listen normalizer (`ListenContentNormalizer`). For
/// every offline test page, and two synthetic documents that give the normalizer work (loose
/// text, `<br><br>` lines, lead-in text before nested blocks, a standards-mode table), the
/// extraction equals what the app produced when Readability and the normalizer ran as one script
/// (`ListenGoldenFixture`, recorded from that build): the listen blocks, the reading HTML and the
/// rest of the result. The listen-block rules keep their version, so no saved page rebuilds.
@MainActor
final class ListenContentGoldenTests: XCTestCase {
    /// Documents the golden fixture holds besides the test pages.
    static let extraDocuments: [(name: String, html: String)] = [
        ("loose-text", looseTextDocument),
        ("standards-table", standardsTableDocument),
    ]

    func testEveryTestPageAndExtraDocumentExtractsAsRecorded() async throws {
        let documents = TestPageSchemeHandler.pageNames.map { ($0, TestPageSchemeHandler.page($0)) } + Self.extraDocuments
        XCTAssertEqual(Set(documents.map(\.0)), Set(ListenGoldenFixture.pages.keys), "the fixture covers every document")
        for (name, html) in documents {
            let golden = try XCTUnwrap(ListenGoldenFixture.pages[name], name)
            let outcome: ListenGoldenFixture.Outcome
            do {
                let parsed = try await ReadabilityRunner.parse(html: html, baseURL: URL(string: "reader-test://pages/\(name)")!)
                let blocks = ParagraphDocument.forListening(plainText: parsed.textContent, cleanedHTML: parsed.contentHTML,
                                                            matchingTitle: parsed.title).paragraphs
                outcome = .extracted(title: parsed.title, byline: parsed.byline, siteName: parsed.siteName,
                                     excerpt: parsed.excerpt, textContent: parsed.textContent,
                                     contentHTML: parsed.contentHTML, listenBlocks: blocks)
            } catch {
                outcome = .failed(String(describing: error))
            }
            if case .extracted(_, _, _, _, _, _, let blocks) = outcome,
               case .extracted(_, _, _, _, _, _, let goldenBlocks) = golden {
                XCTAssertEqual(blocks, goldenBlocks, "\(name): listen blocks")
            }
            XCTAssertEqual(outcome, golden, name)
        }
    }

    func testListenBlockRulesKeepTheirVersion() {
        XCTAssertEqual(ListenHTMLBlocks.version, 3)
    }

    // MARK: - Documents

    private static let sentence = "This synthetic article exists only to give the normalizer some loose text to wrap. "

    /// Quirks mode (no doctype), like the test pages: a table start tag doesn't close the
    /// paragraph it's in (Readability then flattens the table).
    private static let looseTextDocument = """
    <html><head><title>Loose text</title></head><body><article>
    <h1>Loose text</h1>
    <p>\(String(repeating: sentence, count: 4))</p>
    <div>Loose lead-in text in a div, before a block. \(sentence)<p>\(String(repeating: sentence, count: 3))</p>
    Trailing loose text after the block, still in the div. \(sentence)</div>
    <div>First line of a short verse<br><br>Second line, after a blank line<br>Third line, after a plain break</div>
    <ul><li>Lead-in text of a list item <ul><li>Nested item one</li><li>Nested item two</li></ul></li></ul>
    <blockquote>Lead-in text of a quote <p>The quoted paragraph.</p></blockquote>
    <div><span>Text in a span, in a div.</span> <a href="#x">A link in the same run.</a></div>
    <p>A paragraph that runs into a table <table><tr><td>Quirks cell</td></tr></table> and on.</p>
    <p>\(String(repeating: sentence, count: 4))</p>
    </article></body></html>
    """

    /// Standards mode: a table start tag closes an open paragraph here, not in quirks mode.
    private static let standardsTableDocument = """
    <!DOCTYPE html><html><head><title>Standards table</title></head><body><article>
    <h1>Standards table</h1>
    <p>\(String(repeating: sentence, count: 4))</p>
    <p>A paragraph that runs into a table <table><tr><td>First cell</td><td>Second cell</td></tr></table> and on.
    <div>Loose text after the table. \(sentence)</div>
    <p>\(String(repeating: sentence, count: 4))</p>
    </article></body></html>
    """
}
