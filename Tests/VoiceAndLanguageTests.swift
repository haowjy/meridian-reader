import AVFoundation
import XCTest
@testable import MeridianReader

/// Settings → Listen: curated Kokoro voices, voice download-on-select, and article language
/// resolution (Automatic vs manual, unsupported language → Apple for that article).
@MainActor
final class VoiceAndLanguageTests: XCTestCase {
    private var kokoro: EngineDescriptor { FluidAudioProvider.kokoroDescriptor }
    private var apple: EngineDescriptor { AppleSpeechProvider.descriptor }

    // MARK: - Curated voices

    func testKokoroCuratedVoicesAndDefault() {
        XCTAssertEqual(kokoro.voices.map(\.id), ["af_heart", "af_bella", "bf_emma", "am_puck", "bm_fable"])
        XCTAssertEqual(kokoro.voices.map(\.detail),
                       ["Warm, American", "Bright, American", "British", "American male", "British male"])
        XCTAssertEqual(kokoro.defaultVoiceID, "af_heart")
        XCTAssertEqual(kokoro.voices, KokoroVoiceCatalog.curated, "one source of truth")
        // Stored voice kept if still curated; dropped voices / nothing stored → default.
        XCTAssertEqual(kokoro.resolvedVoice("bf_emma"), "bf_emma")
        XCTAssertEqual(kokoro.resolvedVoice("af_nicole"), "af_heart")
        XCTAssertEqual(kokoro.resolvedVoice(nil), "af_heart")
        // Cache key format unchanged (existing article audio keeps matching).
        XCTAssertEqual(kokoro.cacheVoiceID(engineVoice: "am_puck"), "kokoro.am_puck")
    }

    func testEveryCuratedVoiceHasABundledPreview() throws {
        for voice in kokoro.voices {
            let name = try XCTUnwrap(voice.previewResource, voice.id)
            let url = try XCTUnwrap(VoicePreviewPlayer.url(forResource: name), "missing preview for \(voice.id)")
            let bytes = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int)
            XCTAssertLessThan(bytes, 100_000, "\(voice.id) preview should be a few tens of KB")
            XCTAssertGreaterThan(bytes, 5_000, "\(voice.id) preview looks empty")
        }
    }

    // MARK: - Voice download on select

    private func makeCoordinator(_ provider: FakeEngineProvider) -> (LocalTTSCoordinator, UserDefaults, String) {
        let suite = "VoiceAndLanguageTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(FakeEngineProvider.fakeID.rawValue, forKey: LocalTTSCoordinator.engineIDKey)
        let registry = EngineRegistry(providers: [AppleSpeechProvider(), provider], gate: { _ in true })
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VoiceLang-\(UUID().uuidString)")
        let guardDir = FileManager.default.temporaryDirectory.appendingPathComponent("VoiceLangGuard-\(UUID().uuidString)")
        let coordinator = LocalTTSCoordinator(engines: registry, defaults: defaults,
                                              audioCache: ArticleAudioCache(root: root),
                                              crashGuard: EngineCrashGuard(directory: guardDir))
        return (coordinator, defaults, suite)
    }

    private func fakeWithVoices() -> FakeEngineProvider {
        let provider = FakeEngineProvider()
        provider.voices = [EngineVoice(id: "v1", label: "One"), EngineVoice(id: "v2", label: "Two")]
        provider.defaultVoice = "v1"
        return provider
    }

    func testChooseVoiceDownloadsThenSwitches() async {
        let provider = fakeWithVoices()
        let (c, defaults, suite) = makeCoordinator(provider)
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(c.voice(for: FakeEngineProvider.fakeID), "v1")
        let changed = await c.chooseVoice("v2", for: FakeEngineProvider.fakeID)
        XCTAssertTrue(changed)
        XCTAssertEqual(provider.preparedVoices, ["v2"])
        XCTAssertEqual(c.voice(for: FakeEngineProvider.fakeID), "v2")
        XCTAssertEqual(c.activeCacheVoice, "fake.v2", "cache key follows the new voice")
        XCTAssertNil(c.voiceDownloadID)
        XCTAssertNil(c.voiceDownloadError)
        let again = await c.chooseVoice("v2", for: FakeEngineProvider.fakeID)
        XCTAssertFalse(again, "same voice is a no-op")
        XCTAssertEqual(provider.preparedVoices, ["v2"])
    }

    func testFailedVoiceDownloadKeepsOldVoice() async {
        struct Offline: Error {}
        let provider = fakeWithVoices()
        provider.voiceDownloadError = Offline()
        let (c, defaults, suite) = makeCoordinator(provider)
        defer { defaults.removePersistentDomain(forName: suite) }
        let changed = await c.chooseVoice("v2", for: FakeEngineProvider.fakeID)
        XCTAssertFalse(changed)
        XCTAssertEqual(c.voice(for: FakeEngineProvider.fakeID), "v1")
        XCTAssertEqual(c.activeCacheVoice, "fake.v1")
        XCTAssertNotNil(c.voiceDownloadError)
        XCTAssertNil(c.voiceDownloadID)
    }

    // MARK: - Language detection

    func testDetectsArticleLanguage() {
        let en = ["The committee met on Tuesday to discuss the new library, which will open next spring.",
                  "Residents asked about parking, opening hours and whether the children's room would be larger."]
        let fr = ["Le comité s'est réuni mardi pour discuter de la nouvelle bibliothèque, qui ouvrira au printemps prochain.",
                  "Les habitants ont posé des questions sur le stationnement et les horaires d'ouverture."]
        let de = ["Der Ausschuss traf sich am Dienstag, um über die neue Bibliothek zu sprechen, die im nächsten Frühjahr eröffnet."]
        XCTAssertEqual(ListenLanguage.detect(paragraphs: en), "en")
        XCTAssertEqual(ListenLanguage.detect(paragraphs: fr), "fr")
        XCTAssertEqual(ListenLanguage.detect(paragraphs: de), "de")
        XCTAssertNil(ListenLanguage.detect(paragraphs: ["Hi"]), "too short to trust")
        XCTAssertEqual(ListenLanguage.detectCached(paragraphs: fr), "fr")
        XCTAssertEqual(ListenLanguage.detectCached(paragraphs: fr), "fr", "memoized")
        // Only the first few thousand characters are sampled.
        let long = Array(repeating: fr[0], count: 200)
        XCTAssertLessThanOrEqual(ListenLanguage.sample(long).count, ListenLanguage.sampleCharacterLimit)
    }

    // MARK: - Language resolution

    func testKokoroSupportsEnglishOnly() {
        XCTAssertEqual(kokoro.supportedLanguages, ["en"])
        XCTAssertTrue(kokoro.supportsLanguage("en-US"))
        XCTAssertTrue(kokoro.supportsLanguage("en_GB"))
        XCTAssertFalse(kokoro.supportsLanguage("fr"))
        XCTAssertTrue(apple.supportsLanguage("fr-FR"), "Apple: any language")
        XCTAssertEqual(kokoro.languageLimitNote?.hasPrefix("Kokoro is "), true)
        XCTAssertEqual(kokoro.languageLimitNote?.hasSuffix("-only"), true)
    }

    func testAutomaticUsesDetectedLanguage() {
        let r = ListenLanguageResolution.resolve(automatic: true, manualCode: "fr-FR", detectedCode: "en",
                                                 selectedEngine: kokoro)
        XCTAssertEqual(r.languageCode, "en")
        XCTAssertEqual(r.source, .detected)
        XCTAssertEqual(r.engineID, .kokoro)
        XCTAssertNil(r.note)
    }

    func testAutomaticWithoutDetectionFallsBackToSettingLanguage() {
        let r = ListenLanguageResolution.resolve(automatic: true, manualCode: "en-GB", detectedCode: nil,
                                                 selectedEngine: kokoro)
        XCTAssertEqual(r.languageCode, "en-GB")
        XCTAssertEqual(r.source, .fallback)
        XCTAssertEqual(r.engineID, .kokoro)
    }

    func testManualLanguageOverridesDetection() {
        let r = ListenLanguageResolution.resolve(automatic: false, manualCode: "en-US", detectedCode: "fr",
                                                 selectedEngine: kokoro)
        XCTAssertEqual(r.languageCode, "en-US")
        XCTAssertEqual(r.source, .manual)
        XCTAssertEqual(r.engineID, .kokoro)
    }

    func testUnsupportedLanguageSpeaksWithAppleForThatArticle() {
        let auto = ListenLanguageResolution.resolve(automatic: true, manualCode: "en-US", detectedCode: "fr",
                                                    selectedEngine: kokoro)
        XCTAssertEqual(auto.languageCode, "fr")
        XCTAssertEqual(auto.engineID, .apple)
        XCTAssertEqual(auto.unsupportedEngineID, .kokoro)
        let note = try? XCTUnwrap(auto.note)
        XCTAssertEqual(note?.hasPrefix("Apple voice for "), true)
        XCTAssertEqual(note?.contains("Kokoro is "), true)

        let manual = ListenLanguageResolution.resolve(automatic: false, manualCode: "de-DE", detectedCode: "en",
                                                      selectedEngine: kokoro)
        XCTAssertEqual(manual.engineID, .apple)
        XCTAssertEqual(manual.languageCode, "de-DE")

        // Apple selected: never a "fallback" note.
        let onApple = ListenLanguageResolution.resolve(automatic: true, manualCode: "en-US", detectedCode: "fr",
                                                       selectedEngine: apple)
        XCTAssertEqual(onApple.engineID, .apple)
        XCTAssertNil(onApple.note)
        XCTAssertNil(onApple.unsupportedEngineID)
    }

    func testLanguageGateStopsBakeForUnsupportedArticles() async {
        let provider = FakeEngineProvider()
        provider.languages = ["en"]
        let (c, defaults, suite) = makeCoordinator(provider)
        defer { defaults.removePersistentDomain(forName: suite) }
        await c.selectEngine(FakeEngineProvider.fakeID)
        XCTAssertTrue(c.usesLocalEngine)
        let gateCalls = GateRecorder()
        c.localLanguageGate = { paragraphs in
            gateCalls.count += 1
            return ListenLanguageResolution.resolve(
                automatic: true, manualCode: "en-US",
                detectedCode: ListenLanguage.detectCached(paragraphs: paragraphs),
                selectedEngine: provider.descriptor).engineID.isLocal
        }
        let french = ["Le comité s'est réuni mardi pour discuter de la nouvelle bibliothèque, qui ouvrira au printemps prochain."]
        let key = UUID()
        c.warmListenAudio(cacheKey: key, paragraphs: french, resumeParagraph: 0, isEphemeral: true)
        XCTAssertEqual(gateCalls.count, 1)
        XCTAssertFalse(c.synthQueue.hasJob(cacheKey: key), "French article must not bake with an English-only engine")

        let english = ["The committee met on Tuesday to discuss the new library, which will open next spring."]
        let key2 = UUID()
        c.warmListenAudio(cacheKey: key2, paragraphs: english, resumeParagraph: 0, isEphemeral: true)
        XCTAssertTrue(c.synthQueue.hasJob(cacheKey: key2), "English article bakes")
        c.synthQueue.remove(cacheKey: key2)
    }

    /// The render queue's Apple fallback for an article is the voice the player falls back to:
    /// the user's pick when it speaks the article's language, else the best voice for that
    /// language.
    func testTheRenderQueueFallsBackToTheUsersAppleVoice() throws {
        let english = AVSpeechSynthesisVoice.speechVoices().filter { ListenLanguage.baseCode($0.language) == "en" }
        let best = VoiceCatalog.bestVoice(forLanguage: "en")?.identifier
        guard let pick = english.first(where: { $0.identifier != best }) else { throw XCTSkip("needs two English voices") }
        let standard = UserDefaults.standard
        let savedVoice = standard.string(forKey: "reader.selectedVoiceIdentifier")
        let savedAutomatic = standard.object(forKey: SpeechController.languageAutomaticKey)
        let t = TestSpeech()
        defer {
            t.tearDown()
            standard.set(savedVoice, forKey: "reader.selectedVoiceIdentifier")
            standard.set(savedAutomatic, forKey: SpeechController.languageAutomaticKey)
        }
        t.speech.languageAutomatic = true
        let article = ["The committee met on Tuesday to discuss the new library, which will open next spring."]
        XCTAssertEqual(t.speech.localTTS.appleFallbackVoice(for: article), best, "no pick: the best English voice")

        t.speech.selectedVoiceIdentifier = pick.identifier
        XCTAssertEqual(t.speech.localTTS.appleFallbackVoice(for: article), pick.identifier, "the user's English voice")
        let french = ["Le comité s'est réuni mardi pour discuter de la nouvelle bibliothèque, qui ouvrira au printemps prochain."]
        XCTAssertEqual(t.speech.localTTS.appleFallbackVoice(for: french), VoiceCatalog.bestVoice(forLanguage: "fr")?.identifier,
                       "an English pick doesn't speak French")
    }
}

private final class GateRecorder { var count = 0 }
