import XCTest
@testable import MeridianReader

final class PhononSpokenTextTests: XCTestCase {
    // MARK: - Question / exclamation reach Phonon

    func testNormalizeKeepsQuestionAndExclaim() {
        let q = TTSTextNormalize.normalize("Why not?")
        XCTAssertTrue(q.hasSuffix("?"), q)
        let mixed = TTSTextNormalize.normalize("Is it raining? Yes! Maybe?")
        XCTAssertEqual(mixed, "Is it raining? Yes! Maybe?")
    }

    func testPhononPrepareKeepsQuestionMark() {
        let out = PhononSpokenText.prepare("Why not?")
        XCTAssertEqual(out, "Why not?")
    }

    func testPhononPrepareCollapsesQuestionEllipsisSoEnderSurvives() {
        // Phonon rewrite turns … into `.`, which would pop a preceding `?`.
        XCTAssertEqual(PhononSpokenText.prepare("Really?…"), "Really?")
        XCTAssertEqual(PhononSpokenText.prepare("What is this?."), "What is this?")
        XCTAssertEqual(PhononSpokenText.prepare("Look!..."), "Look!")
    }

    func testNormalizeThenPhononPrepareKeepsQuestion() {
        let normalized = TTSTextNormalize.normalize("A b c.  D e f!  G h i?")
        let spoken = PhononSpokenText.prepare(normalized)
        XCTAssertTrue(spoken.contains("?"), spoken)
        XCTAssertTrue(spoken.contains("!"), spoken)
        XCTAssertTrue(spoken.hasSuffix("?"), spoken)
    }

    // MARK: - ALL CAPS softening

    func testSoftensShoutyAllCapsSentence() {
        let out = PhononSpokenText.prepare("THIS IS IMPORTANT NEWS TODAY.")
        XCTAssertEqual(out, "This is important news today.")
    }

    func testKeepsShortAcronyms() {
        let out = PhononSpokenText.prepare("The FBI and NASA reviewed the HTML API today.")
        XCTAssertEqual(out, "The FBI and NASA reviewed the HTML API today.")
    }

    func testSoftensLongAllCapsWordInMixedSentence() {
        let out = PhononSpokenText.prepare("The FBI said HELLO THERE today.")
        XCTAssertEqual(out, "The FBI said hello there today.")
    }

    func testLeavesOrdinaryMixedCaseAlone() {
        let s = "Why, one councillor asked, had no one mentioned this before?"
        XCTAssertEqual(PhononSpokenText.prepare(s), s)
    }
}
