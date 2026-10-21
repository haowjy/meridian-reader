import XCTest
@testable import MeridianReader

/// C138a: an article's stored voice names its engine; the stored form round-trips.
final class VoiceSelectionTests: XCTestCase {
    func testStoredFormRoundTrips() {
        let kokoro = VoiceSelection(engine: .kokoro, voice: "af_heart")
        XCTAssertEqual(kokoro.stored, "local.kokoro/af_heart")
        XCTAssertEqual(VoiceSelection(stored: kokoro.stored), kokoro)
        let apple = VoiceSelection(stored: "apple/com.apple.voice.premium.en-US.Ava")
        XCTAssertEqual(apple?.engine, .apple)
        XCTAssertEqual(apple?.voice, "com.apple.voice.premium.en-US.Ava")
        XCTAssertEqual(VoiceSelection(stored: "apple/")?.voice, "")
        // A C138 cache voice key has no engine: not a selection (the C138a migration converts it).
        XCTAssertNil(VoiceSelection(stored: "kokoro.af_heart"))
    }
}
