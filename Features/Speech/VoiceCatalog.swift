import Foundation
import AVFoundation

/// Filters Apple's installed TTS voices down to ones worth offering in-app.
/// Source: `AVSpeechSynthesisVoice.speechVoices()` — only voices already on the device.
enum VoiceCatalog {
    struct Entry: Identifiable, Hashable {
        var id: String { voice.identifier }
        var voice: AVSpeechSynthesisVoice
        var qualityLabel: String
        var languageDisplayName: String
    }

    struct LanguageOption: Identifiable, Hashable {
        var id: String { code }
        var code: String
        var displayName: String
    }

    static func allGoodEntries(
        from all: [AVSpeechSynthesisVoice] = AVSpeechSynthesisVoice.speechVoices()
    ) -> [Entry] {
        all
            .filter { isGoodQuality($0) }
            .filter { !isNoveltyName($0.name) }
            .map { Entry(voice: $0, qualityLabel: qualityLabel(for: $0), languageDisplayName: languageName(for: $0.language)) }
            .sorted(by: sortEntries)
    }

    static func availableLanguages(
        from all: [AVSpeechSynthesisVoice] = AVSpeechSynthesisVoice.speechVoices()
    ) -> [LanguageOption] {
        var seen = Set<String>()
        var options: [LanguageOption] = []
        for entry in allGoodEntries(from: all) {
            let code = entry.voice.language
            if seen.insert(code).inserted {
                options.append(LanguageOption(code: code, displayName: languageName(for: code)))
            }
        }
        return options.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    static func voices(
        forLanguage code: String,
        from all: [AVSpeechSynthesisVoice] = AVSpeechSynthesisVoice.speechVoices()
    ) -> [Entry] {
        let target = canonicalLang(code)
        return allGoodEntries(from: all).filter { entry in
            let lang = canonicalLang(entry.voice.language)
            return lang == target || lang.hasPrefix(target) || target.hasPrefix(lang)
        }
    }

    /// Apple voice for speaking `code` when the user hasn't picked one for that language (C129):
    /// the best installed voice, Premium before Enhanced before the default, then one whose gender
    /// matches `gender` (the Kokoro voice's, so the live-gap fallback sounds closer), then the
    /// exact region asked for (or the device's), never a novelty voice. Siri's voices aren't
    /// offered to apps, so these are the Spoken Content voices.
    static func bestVoice(
        forLanguage code: String,
        gender: AVSpeechSynthesisVoiceGender? = nil,
        from all: [AVSpeechSynthesisVoice] = AVSpeechSynthesisVoice.speechVoices()
    ) -> AVSpeechSynthesisVoice? {
        let wanted = canonicalLang(code)
        let base = ListenLanguage.baseCode(code)
        let region = wanted.contains("-") ? String(wanted.split(separator: "-").last ?? "")
            : Locale.current.region?.identifier.lowercased()
        let candidates = all.filter { ListenLanguage.baseCode($0.language) == base && !isNoveltyName($0.name) }
        func score(_ v: AVSpeechSynthesisVoice) -> Int {
            var s = qualityRank(v) * 100
            if let gender, gender != .unspecified, v.gender == gender { s += 10 }
            if let region, canonicalLang(v.language).hasSuffix("-" + region) { s += 5 }
            return s
        }
        return candidates.max { score($0) < score($1) }
            ?? AVSpeechSynthesisVoice(language: code.replacingOccurrences(of: "_", with: "-"))
    }

    /// Whether any Enhanced or Premium voice is installed for `code` (Settings' download hint).
    static func hasHighQualityVoice(forLanguage code: String,
                                    from all: [AVSpeechSynthesisVoice] = AVSpeechSynthesisVoice.speechVoices()) -> Bool {
        let base = ListenLanguage.baseCode(code)
        return all.contains { ListenLanguage.baseCode($0.language) == base && qualityRank($0) >= 2 }
    }

    /// A Kokoro voice id's gender: its second letter ("af_heart" female, "bm_george" male).
    static func gender(ofKokoroVoice id: String?) -> AVSpeechSynthesisVoiceGender? {
        guard let id, id.count >= 2 else { return nil }
        switch id[id.index(after: id.startIndex)] {
        case "f": return .female
        case "m": return .male
        default: return nil
        }
    }

    static func languageName(for code: String) -> String {
        Locale.current.localizedString(forIdentifier: code)
            ?? Locale.current.localizedString(forLanguageCode: String(code.prefix(2)))
            ?? code
    }

    static func canonicalLang(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: "-").lowercased()
    }

    private static func isGoodQuality(_ voice: AVSpeechSynthesisVoice) -> Bool {
        switch voice.quality {
        case .enhanced, .premium: return true
        default: return false
        }
    }

    private static func isNoveltyName(_ name: String) -> Bool {
        let lowered = name.lowercased()
        let blocked = ["zarvox", "trinoids", "whisper", "bad news", "good news", "bells", "bubbles", "cellos", "boing"]
        return blocked.contains { lowered.contains($0) }
    }

    private static func qualityLabel(for voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .premium: return "Premium"
        case .enhanced: return "Enhanced"
        default: return "Standard"
        }
    }

    private static func sortEntries(_ lhs: Entry, _ rhs: Entry) -> Bool {
        if lhs.voice.language != rhs.voice.language {
            return lhs.voice.language < rhs.voice.language
        }
        if qualityRank(lhs.voice) != qualityRank(rhs.voice) {
            return qualityRank(lhs.voice) > qualityRank(rhs.voice)
        }
        return lhs.voice.name < rhs.voice.name
    }

    private static func qualityRank(_ voice: AVSpeechSynthesisVoice) -> Int {
        switch voice.quality {
        case .premium: return 3
        case .enhanced: return 2
        default: return 1
        }
    }
}
