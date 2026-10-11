import XCTest
@testable import MeridianReader

/// Playback-unit identity: which units of one paragraph would replay the same audio, and where
/// an Apple fallback restarts the engine after the background.
final class UnitSourceTests: XCTestCase {
    func testBakedParagraphOverlapsEveryUnit() {
        let others: [UnitSource] = [.baked, .chunk(0), .chunk(3), .stitched(fromChunk: 2),
                                    .appleFallback(fromChunk: 1, reason: .behind)]
        for other in others {
            XCTAssertTrue(UnitSource.baked.overlaps(other), "\(other)")
            XCTAssertTrue(other.overlaps(.baked), "\(other)")
        }
    }

    func testEngineUnitsOverlapAtTheSameChunk() {
        XCTAssertTrue(UnitSource.chunk(2).overlaps(.chunk(2)))
        XCTAssertFalse(UnitSource.chunk(2).overlaps(.chunk(3)))
        XCTAssertTrue(UnitSource.chunk(2).overlaps(.stitched(fromChunk: 2)))
        XCTAssertTrue(UnitSource.stitched(fromChunk: 1).overlaps(.stitched(fromChunk: 1)))
        XCTAssertFalse(UnitSource.stitched(fromChunk: 1).overlaps(.chunk(2)))
    }

    func testAppleFallbackOnlyOverlapsAppleFromTheSameChunk() {
        let apple = UnitSource.appleFallback(fromChunk: 2, reason: .background)
        XCTAssertFalse(apple.overlaps(.chunk(2)))
        XCTAssertFalse(UnitSource.stitched(fromChunk: 2).overlaps(apple))
        XCTAssertTrue(apple.overlaps(.appleFallback(fromChunk: 2, reason: .engineError)))
        XCTAssertFalse(apple.overlaps(.appleFallback(fromChunk: 0, reason: .background)))
    }

    func testStartChunk() {
        XCTAssertNil(UnitSource.baked.startChunk)
        XCTAssertEqual(UnitSource.chunk(4).startChunk, 4)
        XCTAssertEqual(UnitSource.stitched(fromChunk: 1).startChunk, 1)
        XCTAssertEqual(UnitSource.appleFallback(fromChunk: 3, reason: .background).startChunk, 3)
    }

    func testFallbackNotes() {
        XCTAssertEqual(FallbackReason.background.localizedNote(engine: "Kokoro"),
                       "Apple voice – Kokoro can't render in the background")
        XCTAssertEqual(FallbackReason.behind.localizedNote(engine: "Kokoro"),
                       "Apple voice for this paragraph – Kokoro fell behind")
        XCTAssertEqual(FallbackReason.engineError.localizedNote(engine: "Kokoro"),
                       "Apple voice – Kokoro couldn't render this paragraph")
    }
}
