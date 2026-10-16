import XCTest
@testable import MeridianReader

/// Listening-time estimates, how they are written, and the "nothing to listen to" threshold
/// behind 🎧's toast.
final class ListeningTimeTests: XCTestCase {
    func testMinutes() {
        XCTAssertEqual(ListeningTime.minutes(utf16Length: 0, rate: 1), 0)
        XCTAssertEqual(ListeningTime.minutes(utf16Length: 10, rate: 1), 1, "any text is at least a minute")
        XCTAssertEqual(ListeningTime.minutes(utf16Length: 1080 * 9, rate: 1), 9, "1,620 words at 180 a minute")
        XCTAssertEqual(ListeningTime.minutes(utf16Length: 1080 * 9, rate: 1.5), 6)
    }

    /// A page's stored word count reads at the same rate as its listen text: 1,800 words is 10
    /// minutes either way.
    func testWordsAndTextShareOneRate() {
        XCTAssertEqual(ListeningTime.minutes(words: 1800, rate: 1), 10)
        XCTAssertEqual(ListeningTime.minutes(words: 1800, rate: 1),
                       ListeningTime.minutes(utf16Length: 1800 * Int(ListeningTime.unitsPerWord), rate: 1))
        XCTAssertEqual(ListeningTime.minutes(words: 0, rate: 1), 0)
        XCTAssertEqual(ListeningTime.minutes(words: 1800, rate: 2), 5)
    }

    func testLabelsWriteHoursAndMinutes() {
        XCTAssertEqual(ListeningTime.label(minutes: 9), "9 min")
        XCTAssertEqual(ListeningTime.label(minutes: 60), "1 h")
        XCTAssertEqual(ListeningTime.label(minutes: 370), "6 h 10 min")
        XCTAssertEqual(ListeningTime.leftLabel(minutes: 6), "6 min left")
        XCTAssertEqual(ListeningTime.leftLabel(minutes: 120), "2 h left")
        XCTAssertEqual(ListeningTime.leftLabel(minutes: 370), "6 h 10 min left", "not \"370 min left\"")
    }

    func testTooLittleTextIsNothingToListenTo() {
        XCTAssertFalse(ListeningTime.hasEnoughToListen(ParagraphDocument(parts: ["Only a line here."])))
        let paragraph = String(repeating: "A sentence with several words in it. ", count: 6)
        XCTAssertTrue(ListeningTime.hasEnoughToListen(ParagraphDocument(parts: [paragraph])))
    }

    /// The threshold counts words, not characters: many short words are enough, a few long ones
    /// aren't.
    func testTheThresholdCountsWords() {
        let shortWords = Array(repeating: "I am", count: 13).joined(separator: " ") + "."  // 26 words, 64 units
        XCTAssertTrue(ListeningTime.hasEnoughToListen(ParagraphDocument(parts: [shortWords])))
        let longWords = Array(repeating: "internationalization", count: 20).joined(separator: " ")  // 20 words
        XCTAssertFalse(ListeningTime.hasEnoughToListen(ParagraphDocument(parts: [longWords])))
        let across = ["One two three four five six seven eight nine ten eleven twelve.",
                      "Thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty.",
                      "Twenty-one twenty-two twenty-three twenty-four twenty-five."]
        XCTAssertTrue(ListeningTime.hasEnoughToListen(ParagraphDocument(parts: across)), "counted across paragraphs")
    }
}
