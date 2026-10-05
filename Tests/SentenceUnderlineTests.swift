import XCTest
@testable import Reader

/// The underlined sentence on the reading page is the sentence the session is at: the page maps
/// the session's UTF-16 offsets onto the DOM, counting the paragraph's text exactly as the session
/// does (no whitespace collapsed; it isn't normalized, since positions and the audio cache count
/// in it).
@MainActor
final class SentenceUnderlineTests: XCTestCase {
    private var page: ReadingPageHarness!

    override func setUp() async throws {
        page = ReadingPageHarness()
    }

    override func tearDown() async throws {
        page.close()
        page = nil
    }

    func testPlainTextUnderlineMatchesTheSessionOffsets() async throws {
        let text = [
            "The tide turned at noon.    The boats came in slowly.   Nobody hurried.",
            "Nets dried on the wall.\tGulls waited.\t\tThe harbour went quiet.",
            "The keeper wrote it down.\nThen she lit the lamp.\n  The light swept the bay.",
            "A storm 🌊 came over the hill.  It rained 🌧️ all night. 𝔐orning was calm.",
        ].joined(separator: "\n\n")
        let doc = ParagraphDocument(plainText: text)
        XCTAssertEqual(doc.count, 4)
        XCTAssertTrue(doc.paragraphs[0].contains("    "), "the persisted text keeps its whitespace")
        XCTAssertTrue(doc.paragraphs[2].contains("\n  "))
        try await page.load(doc.paragraphsHTML, blocks: doc.count)
        try await assertUnderlines(doc.paragraphs) { $0 }
    }

    /// An HTML block's listen text keeps the source's whitespace runs (only its ends are trimmed),
    /// reads a `<br>` as a space and spans inline elements; the page counts it the same way.
    func testHTMLUnderlineCountsTheListenText() async throws {
        let html = "<p>\n  The tide   turned.  The boats\n   came in.</p>"
            + "<p><b>Nets</b> dried.\t Gulls <i>waited</i>.<br>Then rain.</p>"
        let paragraphs = ParagraphDocument(html: html).paragraphs
        XCTAssertEqual(paragraphs, ["The tide   turned.  The boats\n   came in.", "Nets dried.\t Gulls waited. Then rain."])
        try await page.load(html, blocks: 2)
        // A DOM range's text leaves out the <br>: compare with whitespace runs read as one space.
        try await assertUnderlines(paragraphs) {
            $0.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }
    }

    /// Underlines each sentence of each paragraph, at the offsets the session would give, and
    /// checks the page underlined exactly that text (`normalize` applied to both).
    private func assertUnderlines(_ paragraphs: [String], normalize: (String) -> String) async throws {
        let map = ReaderScrubMap(paragraphs: paragraphs)
        for (p, paragraph) in paragraphs.enumerated() {
            let starts = map.sentenceStarts[p]
            XCTAssertGreaterThan(starts.count, 1, "paragraph \(p) has several sentences")
            for start in starts {
                let range = try XCTUnwrap(map.sentenceRange(paragraph: p, offset: start))
                let expected = (paragraph as NSString).substring(with: NSRange(location: range.lowerBound,
                                                                               length: range.count))
                page.coordinator.setSentence(ReaderSentence(paragraph: p, start: range.lowerBound, end: range.upperBound))
                var underlined: String?
                try await page.waitUntil("paragraph \(p) sentence at \(start) underlined", timeout: 3) {
                    underlined = try await self.page.js("""
                    (function(){ var h = CSS.highlights.get('reader-sentence');
                      var r = h && Array.from(h)[0]; return r ? r.toString() : null; })()
                    """) as? String
                    return underlined.map(normalize) == normalize(expected)
                }
                XCTAssertEqual(underlined.map(normalize), normalize(expected), "paragraph \(p), offsets \(range)")
            }
        }
    }
}
