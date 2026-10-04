import XCTest
@testable import Reader

/// Listening-time estimates and the "nothing to listen to" threshold behind 🎧's toast.
final class ListeningTimeTests: XCTestCase {
    func testMinutes() {
        XCTAssertEqual(ListeningTime.minutes(utf16Length: 0), 0)
        XCTAssertEqual(ListeningTime.minutes(utf16Length: 10), 1, "any text is at least a minute")
        XCTAssertEqual(ListeningTime.minutes(utf16Length: 1080 * 9), 9, "1,620 words at 180 a minute")
        XCTAssertEqual(ListeningTime.minutes(utf16Length: 1080 * 9, rate: 1.5), 6)
    }

    func testTooLittleTextIsNothingToListenTo() {
        XCTAssertFalse(ListeningTime.hasEnoughToListen(ParagraphDocument(parts: ["Only a line here."])))
        let paragraph = String(repeating: "A sentence with several words in it. ", count: 6)
        XCTAssertTrue(ListeningTime.hasEnoughToListen(ParagraphDocument(parts: [paragraph])))
    }
}
