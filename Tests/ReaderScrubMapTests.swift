import XCTest
@testable import Reader

/// Nav-mockup scrubber: position ↔ paragraph mapping and haptic tick boundaries.
final class ReaderScrubMapTests: XCTestCase {
    func testParagraphWeightsAndLookup() {
        // 100 + 300 + 100 chars → fractions 0, 0.2, 0.8.
        let map = ReaderScrubMap(paragraphs: [String(repeating: "a", count: 100),
                                              String(repeating: "b", count: 300),
                                              String(repeating: "c", count: 100)])
        XCTAssertEqual(map.fraction(paragraph: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(map.fraction(paragraph: 1), 0.2, accuracy: 1e-9)
        XCTAssertEqual(map.fraction(paragraph: 1, within: 0.5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(map.fraction(paragraph: 2), 0.8, accuracy: 1e-9)
        XCTAssertEqual(map.paragraph(at: 0), 0)
        XCTAssertEqual(map.paragraph(at: 0.19), 0)
        XCTAssertEqual(map.paragraph(at: 0.2), 1)
        XCTAssertEqual(map.paragraph(at: 0.79), 1)
        XCTAssertEqual(map.paragraph(at: 1), 2)
        XCTAssertEqual(map.paragraph(at: -3), 0)
        // No chunk plan → ticks at paragraph starts only.
        XCTAssertEqual(map.ticks.count, 2)
        XCTAssertEqual(map.tickIndex(at: 0.1), 0)
        XCTAssertEqual(map.tickIndex(at: 0.5), 1)
        XCTAssertEqual(map.tickIndex(at: 0.9), 2)
    }

    func testChunkBoundariesAddTicks() {
        let p0 = String(repeating: "a", count: 100)
        let p1 = String(repeating: "b", count: 100)
        // Split p1 into two equal chunks → an extra tick at 0.75.
        let map = ReaderScrubMap(paragraphs: [p0, p1]) { text in
            text.hasPrefix("b") ? [String(text.prefix(50)), String(text.suffix(50))] : [text]
        }
        XCTAssertEqual(map.ticks.count, 2)
        XCTAssertEqual(map.ticks[0], 0.5, accuracy: 1e-9)
        XCTAssertEqual(map.ticks[1], 0.75, accuracy: 1e-9)
        // Dragging across 0.75 changes the tick index (one haptic), but not the paragraph.
        XCTAssertNotEqual(map.tickIndex(at: 0.7), map.tickIndex(at: 0.8))
        XCTAssertEqual(map.paragraph(at: 0.7), map.paragraph(at: 0.8))
    }

    func testBufferedSpansMergeAdjacentReadyParagraphs() {
        // Four equal paragraphs → quarters.
        let map = ReaderScrubMap(paragraphs: Array(repeating: String(repeating: "x", count: 10), count: 4))
        let spans = map.spans(covering: [0, 1, 3])
        XCTAssertEqual(spans.count, 2)
        XCTAssertEqual(spans[0].lowerBound, 0, accuracy: 1e-9)
        XCTAssertEqual(spans[0].upperBound, 0.5, accuracy: 1e-9)
        XCTAssertEqual(spans[1].lowerBound, 0.75, accuracy: 1e-9)
        XCTAssertEqual(spans[1].upperBound, 1, accuracy: 1e-9)
        XCTAssertTrue(map.spans(covering: []).isEmpty)
        XCTAssertTrue(ReaderScrubMap(paragraphs: []).spans(covering: [0]).isEmpty)
    }
}
