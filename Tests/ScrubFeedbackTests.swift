import XCTest
@testable import Reader

/// Scrubber feedback: haptic ticks only where boundaries are far enough apart to feel, a firm
/// tick at the ends, and a bubble that rides above the finger.
final class ScrubFeedbackTests: XCTestCase {
    /// Two paragraphs of 100 UTF-16 units, the first with sentences at 0, 10 and 50.
    private let map = ReaderScrubMap(paragraphs: [
        "Tiny one. Then the second sentence goes on a bit. Third sentence: the long one here and now it ends.",
        String(repeating: "c", count: 99) + ".",
    ])

    func testFixture() {
        XCTAssertEqual(map.texts[0].utf16.count, 100)
        XCTAssertEqual(map.sentenceStarts[0], [0, 10, 50])
    }

    private func spot(_ fraction: Double) -> (fraction: Double, target: ReaderScrubMap.Target) {
        (fraction, map.target(at: fraction))
    }

    func testWidthsAreFractionsOfTheWholeArticle() {
        XCTAssertEqual(map.paragraphWidth(0), 0.5, accuracy: 1e-9)
        XCTAssertEqual(map.sentenceWidth(map.target(at: 0)), 0.05, accuracy: 1e-9, "10 of 200 units")
        XCTAssertEqual(map.sentenceWidth(map.target(at: 0.3)), 0.25, accuracy: 1e-9, "the last sentence runs to the paragraph end")
    }

    func testDenseSentencesDoNotTickWhereSparseOnesDo() {
        // Back from the second sentence into the first, 10 units = 0.05 of the article.
        let second = spot(0.06), first = spot(0.01)
        XCTAssertEqual(second.target.sentence, 1)
        XCTAssertEqual(first.target.sentence, 0)
        // 100 pt across the whole article → 5 pt wide: too dense to tick.
        XCTAssertNil(ScrubTick.between(second, first, map: map, pointsPerFraction: 100))
        // Fine speed (×0.1) spreads the same article over 1000 pt → 50 pt wide: ticks.
        XCTAssertEqual(ScrubTick.between(second, first, map: map, pointsPerFraction: 1000), .boundary)
        // Forward into the 40-unit second sentence: 20 pt wide even at 100 pt, so it ticks.
        XCTAssertEqual(ScrubTick.between(first, second, map: map, pointsPerFraction: 100), .boundary)
    }

    func testParagraphBoundaryTicksWhenTheParagraphIsWideEnough() {
        XCTAssertEqual(ScrubTick.between(spot(0.45), spot(0.55), map: map, pointsPerFraction: 100), .boundary)
        XCTAssertNil(ScrubTick.between(spot(0.45), spot(0.55), map: map, pointsPerFraction: 10))
    }

    func testEndsTickFirmlyOnceAndStayingPutIsSilent() {
        XCTAssertEqual(ScrubTick.between(spot(0.98), spot(1), map: map, pointsPerFraction: 10), .end)
        XCTAssertEqual(ScrubTick.between(spot(0.02), spot(0), map: map, pointsPerFraction: 10), .end)
        XCTAssertNil(ScrubTick.between(spot(1), spot(1), map: map, pointsPerFraction: 1000))
        XCTAssertNil(ScrubTick.between(spot(0.6), spot(0.61), map: map, pointsPerFraction: 1000), "same sentence")
    }

    func testBubbleSitsAboveTheTrackThenRidesAboveTheFinger() {
        let track = CGRect(x: 0, y: 4, width: 200, height: 36)
        let resting = ReaderScrubBubble.bottom(track: track, fingerY: 18)
        XCTAssertLessThanOrEqual(resting, track.minY - ReaderScrubBubble.trackGap, "never over the track")
        let raised = ReaderScrubBubble.bottom(track: track, fingerY: -120)
        XCTAssertEqual(raised, track.minY - 120 - ReaderScrubBubble.fingerGap, "clear of the finger")
        XCTAssertLessThan(raised, resting)
    }

    func testSpeedChipsAreShort() {
        XCTAssertNil(ScrubSpeed.normal.chip)
        XCTAssertEqual(ScrubSpeed.half.chip, "½×")
        XCTAssertEqual(ScrubSpeed.quarter.chip, "¼×")
        XCTAssertEqual(ScrubSpeed.fine.chip, "Fine")
    }
}
