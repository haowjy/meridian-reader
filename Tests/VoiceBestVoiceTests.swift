import XCTest
import AVFoundation
@testable import MeridianReader

/// C139: `VoiceCatalog.bestVoiceProxy` applies the English preference order without touching
/// `AVSpeechSynthesisVoice`. All voices are injected as `VoiceProxy` values.
final class VoiceBestVoiceTests: XCTestCase {
    typealias Proxy = VoiceCatalog.VoiceProxy

    // MARK: - Helpers

    private func proxy(_ id: String, name: String, lang: String = "en-US",
                       quality: AVSpeechSynthesisVoiceQuality = .default,
                       gender: AVSpeechSynthesisVoiceGender = .unspecified) -> Proxy {
        Proxy(identifier: id, name: name, language: lang, quality: quality, gender: gender)
    }

    private func best(_ voices: [Proxy], lang: String = "en-US",
                      gender: AVSpeechSynthesisVoiceGender? = nil) -> String? {
        VoiceCatalog.bestVoiceProxy(forLanguage: lang, gender: gender, from: voices)?.name
    }

    // MARK: - C139 English preference

    func testNoraBeatsEverything() {
        let voices = [
            proxy("com.apple.voice.premium.en-US.Ava", name: "Ava", quality: .premium),
            proxy("com.apple.siri.natural.Nora.en-US", name: "Voice 4"),
            proxy("com.apple.ttsbundle.Samantha-compact", name: "Samantha"),
        ]
        XCTAssertEqual(best(voices), "Voice 4")
    }

    func testNoraMatchedByName() {
        let voices = [
            proxy("com.apple.voice.enhanced.en-US.Ava", name: "Ava", quality: .enhanced),
            proxy("com.apple.voice.special.en-US.Voice4", name: "Voice 4"),
        ]
        XCTAssertEqual(best(voices), "Voice 4", "Name 'Voice 4' is the Nora fallback match")
    }

    func testPremiumBeatsEnhancedWhenNoNora() {
        let voices = [
            proxy("com.apple.voice.enhanced.en-US.Ava", name: "Ava", quality: .enhanced),
            proxy("com.apple.voice.premium.en-US.Zoe", name: "Zoe", quality: .premium),
        ]
        XCTAssertEqual(best(voices), "Zoe")
    }

    func testEnhancedBeatsSamanthaStandard() {
        let voices = [
            proxy("com.apple.voice.enhanced.en-US.Ava", name: "Ava", quality: .enhanced),
            proxy("com.apple.ttsbundle.Samantha-compact", name: "Samantha"),
        ]
        XCTAssertEqual(best(voices), "Ava")
    }

    func testSamanthaBeforeDanielWhenOnlyStandard() {
        let voices = [
            proxy("com.apple.ttsbundle.Daniel-compact", name: "Daniel"),
            proxy("com.apple.ttsbundle.Samantha-compact", name: "Samantha"),
            proxy("com.apple.ttsbundle.Karen-compact", name: "Karen"),
        ]
        XCTAssertEqual(best(voices), "Samantha")
    }

    func testFallbackOrderDanielKarenMoiraTessa() {
        func bestOf(_ names: [String]) -> String? {
            best(names.map { proxy("id.\($0.lowercased())", name: $0) })
        }
        XCTAssertEqual(bestOf(["Daniel", "Karen", "Moira", "Tessa"]), "Daniel")
        XCTAssertEqual(bestOf(["Karen", "Moira", "Tessa"]), "Karen")
        XCTAssertEqual(bestOf(["Moira", "Tessa"]), "Moira")
        XCTAssertEqual(bestOf(["Tessa"]), "Tessa")
    }

    func testUnnamedStandardLosesToTessa() {
        let voices = [
            proxy("com.apple.ttsbundle.Fred-compact", name: "Fred"),
            proxy("com.apple.ttsbundle.Tessa-compact", name: "Tessa"),
        ]
        XCTAssertEqual(best(voices), "Tessa")
    }

    // MARK: - Non-English unaffected

    func testFrenchUsesQualityScoring() {
        let voices = [
            proxy("com.apple.voice.enhanced.fr-FR.Thomas", name: "Thomas", lang: "fr-FR", quality: .enhanced),
            proxy("com.apple.ttsbundle.fr-FR-Amelie-compact", name: "Amelie", lang: "fr-FR"),
        ]
        XCTAssertEqual(best(voices, lang: "fr-FR"), "Thomas", "Enhanced beats Standard for French too")
    }

    func testFrenchNoraIgnored() {
        let voices = [
            proxy("com.apple.siri.natural.Nora.fr-FR", name: "Voice 4", lang: "fr-FR"),
            proxy("com.apple.voice.premium.fr-FR.Aurelie", name: "Aurelie", lang: "fr-FR", quality: .premium),
        ]
        // Nora boost is English-only; premium wins on quality
        XCTAssertEqual(best(voices, lang: "fr-FR"), "Aurelie")
    }

    // MARK: - Novelty voices excluded

    func testNoveltyVoiceExcluded() {
        let voices = [
            proxy("com.apple.speech.synthesis.voice.zarvox", name: "Zarvox"),
            proxy("com.apple.ttsbundle.Samantha-compact", name: "Samantha"),
        ]
        XCTAssertEqual(best(voices), "Samantha", "Novelty voices are excluded from selection")
    }

    // MARK: - Empty input

    func testNilWhenNoEnglishVoices() {
        let voices = [
            proxy("com.apple.voice.enhanced.fr-FR.Thomas", name: "Thomas", lang: "fr-FR", quality: .enhanced),
        ]
        XCTAssertNil(best(voices, lang: "en-US"))
    }
}
