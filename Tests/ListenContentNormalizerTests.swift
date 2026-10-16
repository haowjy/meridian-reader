import XCTest
@testable import MeridianReader

/// The listen normalizer on its own: text sitting loose in a `<div>` becomes a listen block, so it
/// is read and spoken; a book chapter loses what isn't text to read.
@MainActor
final class ListenContentNormalizerTests: XCTestCase {
    private static let loose = "Loose text straight in the chapter's div, which a scan of blocks alone would never speak."

    private static let looseChapter = """
    <div class="chapter"><h2>Chapter One</h2>\(loose)<div>More loose text, in an inner div.</div>
    <p>A paragraph.</p>Trailing loose text, after the paragraph.</div>
    """

    func testLooseDivTextInABookChapterIsWrappedAndSpoken() async throws {
        XCTAssertFalse(ListenHTMLBlocks.leafTexts(fromHTML: Self.looseChapter).contains(Self.loose),
                       "unnormalized, the loose text is in no listen block")

        let normalized = try await ListenContentNormalizer().normalizeBookChapter(Self.looseChapter)
        let document = ParagraphDocument.forListening(plainText: "", cleanedHTML: normalized)
        XCTAssertEqual(document.paragraphs, ["Chapter One", Self.loose, "More loose text, in an inner div.",
                                             "A paragraph.", "Trailing loose text, after the paragraph."])

        let fixture = TestSpeech()
        defer { fixture.tearDown() }
        fixture.speech.start(SpeechSession(id: UUID(), document: document), at: ListenSpot(paragraph: 1))
        let play = try XCTUnwrap(fixture.apple.plays.last, "the engine was asked to speak")
        XCTAssertEqual(play.document.paragraphs, document.paragraphs)
        XCTAssertEqual(play.utf16Offset, document.startUTF16Offset(forParagraph: 1), "from the loose text")
        XCTAssertEqual(fixture.speech.nowPlaying?.phase, .playing)
    }

    func testLooseDivTextOnAWebPageIsWrappedInTheViewGiven() async throws {
        let webView = OffscreenWebView.make()
        try await OffscreenWebView.load(webView, html: "<!DOCTYPE html><html><body></body></html>", baseURL: nil)
        let normalized = try await ListenContentNormalizer.normalize("<div>\(Self.loose)<p>A paragraph.</p></div>", in: webView)
        XCTAssertEqual(ListenHTMLBlocks.leafTexts(fromHTML: normalized), [Self.loose, "A paragraph."])
    }

    func testABookChapterLosesPicturesMediaFootnotesAndNoteReferences() async throws {
        let chapter = """
        <section epub:type="chapter"><p>A sentence with a note<a epub:type="noteref" href="#n1"><sup>1</sup></a>.</p>
        <img src="images/plate.jpg" alt="A plate"/><svg xmlns="http://www.w3.org/2000/svg"><text>Drawn text</text></svg>
        <video src="clip.mp4">Video fallback</video><audio src="clip.mp3">Audio fallback</audio>
        <aside epub:type="footnote" id="n1"><p>The footnote's text.</p></aside>
        <p role="doc-footnote">A footnote marked by its role.</p>
        <p>A <a href="chapter-2.xhtml#start">link to elsewhere</a> in the text<a role="doc-noteref" href="#n2">2</a>.</p></section>
        """
        let normalized = try await ListenContentNormalizer().normalizeBookChapter(chapter)
        XCTAssertEqual(ListenHTMLBlocks.leafTexts(fromHTML: normalized),
                       ["A sentence with a note.", "A link to elsewhere in the text."])
        for gone in ["<img", "<svg", "<video", "<audio", "<a ", "<a>", "footnote", "noteref"] {
            XCTAssertFalse(normalized.contains(gone), "\(gone) is gone: \(normalized)")
        }
    }

    func testABooksEndnotesStayWithoutTheirLinksBack() async throws {
        let endnotes = """
        <section id="endnotes" role="doc-endnotes" epub:type="endnotes footnotes"><h2>Endnotes</h2><ol>
        <li id="note-1" epub:type="endnote footnote"><p>The first note's text. \
        <a href="chapter-1.xhtml#noteref-1" role="doc-backlink" epub:type="backlink">↩︎</a></p></li>
        <li id="note-2" epub:type="endnote footnote"><p>The second note's text.</p></li></ol></section>
        """
        let normalized = try await ListenContentNormalizer().normalizeBookChapter(endnotes)
        XCTAssertEqual(ParagraphDocument.forListening(plainText: "", cleanedHTML: normalized).paragraphs,
                       ["Endnotes", "The first note's text.", "The second note's text."])
    }

    func testOneNormalizerServesEveryChapterOfABook() async throws {
        let normalizer = ListenContentNormalizer()
        let first = try await normalizer.normalizeBookChapter("<div>First chapter's loose text.</div>")
        let second = try await normalizer.normalizeBookChapter("<div>Second chapter's loose text.</div>")
        XCTAssertEqual(ListenHTMLBlocks.leafTexts(fromHTML: first), ["First chapter's loose text."])
        XCTAssertEqual(ListenHTMLBlocks.leafTexts(fromHTML: second), ["Second chapter's loose text."], "nothing carried over")
    }
}
