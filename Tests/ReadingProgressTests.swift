import XCTest
@testable import MeridianReader

/// How far through an article a playhead offset is (the mini player's fill), from the paragraph
/// ranges rather than by measuring the joined text.
final class ReadingProgressTests: XCTestCase {
    func testProgressIsTheOffsetOverTheJoinedTextLength() {
        let doc = ParagraphDocument(parts: ["Hello there.", "Second one."])
        let length = (doc.joinedText as NSString).length
        XCTAssertEqual(doc.progress(atUTF16Offset: 0), 0)
        XCTAssertEqual(doc.progress(atUTF16Offset: length / 2), Double(length / 2) / Double(length), accuracy: 1e-9)
        XCTAssertEqual(doc.progress(atUTF16Offset: length), 1)
        XCTAssertEqual(doc.progress(atUTF16Offset: length + 50), 1, "clamped")
        XCTAssertEqual(ParagraphDocument.empty.progress(atUTF16Offset: 10), 0)
    }
}
