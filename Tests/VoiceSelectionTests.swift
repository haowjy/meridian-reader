import XCTest
@testable import MeridianReader

/// An article's stored voice names its engine; the stored form round-trips.
final class VoiceSelectionTests: XCTestCase {
    func testStoredFormRoundTrips() {
        let kokoro = VoiceSelection(engine: .kokoro, voice: "af_heart")
        XCTAssertEqual(kokoro.stored, "local.kokoro/af_heart")
        XCTAssertEqual(VoiceSelection(stored: kokoro.stored), kokoro)
        let phonon = VoiceSelection(stored: "local.phonon/Zoey")
        XCTAssertEqual(phonon?.engine, .phonon)
        XCTAssertEqual(phonon?.voice, "Zoey")
        XCTAssertEqual(VoiceSelection(stored: "local.phonon/")?.voice, "")
        // A cache voice key has no engine: not a selection (the launch migration converts it).
        XCTAssertNil(VoiceSelection(stored: "kokoro.af_heart"))
    }
}
