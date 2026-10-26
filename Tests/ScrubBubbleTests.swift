import XCTest
@testable import MeridianReader

/// Where the scrub bubble sits: never over the player card's own rows.
final class ScrubBubbleTests: XCTestCase {
    private let track = CGRect(x: 14, y: 46, width: 300, height: 36)

    func testFingerOnTheTrackPutsTheBubbleJustAboveIt() {
        XCTAssertEqual(ReaderScrubBubble.bottom(track: track, fingerY: 80), track.minY - ReaderScrubBubble.trackGap)
    }

    func testOnThePlayerCardTheBubbleStaysAboveTheCardsTopEdge() {
        let bottom = ReaderScrubBubble.bottom(track: track, fingerY: 80, aboveContainer: true)
        XCTAssertLessThanOrEqual(bottom, -ReaderScrubBubble.trackGap)
    }

    func testAFingerFarAboveTheTrackStillCarriesTheBubbleWithIt() {
        let high = ReaderScrubBubble.bottom(track: track, fingerY: -150, aboveContainer: true)
        let low = ReaderScrubBubble.bottom(track: track, fingerY: 80, aboveContainer: true)
        XCTAssertLessThan(high, low)
    }
}
