import AVFoundation
import Foundation

/// The listen speed: one of `options`. The stored setting and its launch argument, the setter,
/// the players, the lock screen's speed command and the pickers all go through it, so a speed
/// outside the list (an older build's stored value) loads as the nearest one in it.
enum ListenRate {
    static let options: [Double] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    /// The option nearest `value`.
    static func nearest(to value: Double) -> Double {
        options.min { abs($0 - value) < abs($1 - value) } ?? 1
    }

    /// "1×", "1.25×".
    static func label(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        return abs(rounded - 1) < 0.01 ? "1×" : String(format: "%g×", rounded)
    }
}

/// What Settings chooses: the language and the Apple voice (the speeds are `ListenRate`). The stored
/// settings themselves live on `SpeechController` (`languageAutomatic`, `selectedLanguageCode`,
/// `selectedVoiceIdentifier`, `rateMultiplier`).
extension SpeechController {
    // MARK: - Language

    /// Engine the language picker would use: the active local engine (selected or pending),
    /// else the selected one.
    var languageEngineDescriptor: EngineDescriptor? {
        localTTS.engines.descriptor(localTTS.defaultSelection.engine)
    }

    /// Language + engine for an article with `detected` language under the current settings.
    func languageResolution(detected: String?) -> ListenLanguageResolution {
        ListenLanguageResolution.resolve(
            automatic: languageAutomatic,
            manualCode: selectedLanguageCode,
            detectedCode: detected,
            selectedEngine: languageEngineDescriptor
        )
    }

    /// Resolution for the prepared session (Settings / listen bar).
    var languageResolution: ListenLanguageResolution { languageResolution(detected: sessionDetectedLanguage) }

    /// Language the current session speaks in.
    var effectiveLanguageCode: String { languageResolution.languageCode }

    /// Apple voice for the current session (`appleVoice(forLanguage:)` of its language).
    var effectiveAppleVoice: AVSpeechSynthesisVoice? { appleVoice(forLanguage: effectiveLanguageCode) }

    /// The Apple voice that speaks `code`: the user's pick when it speaks that language, else the
    /// best installed voice for it. Apple speech and every Apple fallback of the on-device engine
    /// (live and in the render queue, `LocalTTSCoordinator.appleVoiceForArticle`) use it.
    func appleVoice(forLanguage code: String, preferred: String? = nil) -> AVSpeechSynthesisVoice? {
        let pick = preferred.flatMap { $0.isEmpty ? nil : AVSpeechSynthesisVoice(identifier: $0) } ?? selectedVoice
        if let voice = pick, ListenLanguage.baseCode(voice.language) == ListenLanguage.baseCode(code) {
            return voice
        }
        return VoiceCatalog.bestVoice(forLanguage: code,
                                      gender: VoiceCatalog.gender(ofKokoroVoice: localTTS.voice(for: .kokoro)))
    }

    /// The Apple voice of the Settings default, when the default is an Apple voice.
    var selectedVoice: AVSpeechSynthesisVoice? {
        let d = localTTS.defaultSelection
        guard d.isApple, !d.voice.isEmpty else { return nil }
        return AVSpeechSynthesisVoice(identifier: d.voice)
    }

    // MARK: - Choosing

    /// Settings → Language → Automatic (match article).
    func selectAutomaticLanguage() {
        guard !languageAutomatic else { return }
        languageAutomatic = true
        languageSettingChanged()
    }

    /// Settings → Language → a specific language (turns Automatic off).
    func selectLanguage(_ code: String) {
        guard languageAutomatic || selectedLanguageCode != code else { return }
        let codeChanged = selectedLanguageCode != code
        languageAutomatic = false
        selectedLanguageCode = code
        if codeChanged { selectedVoiceIdentifier = nil }
        languageSettingChanged()
    }

    /// Language change can move the article between the local engine and Apple: restart the
    /// utterance and let the bake queue / marks follow.
    private func languageSettingChanged() {
        localTTS.noteBakeMarksChanged()
        restartUtteranceIfNeeded()
    }
}
