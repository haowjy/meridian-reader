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

    /// A lightweight voice descriptor for ranking logic that tests can inject without
    /// constructing real `AVSpeechSynthesisVoice` instances.
    struct VoiceProxy: Equatable {
        var identifier: String
        var name: String
        var language: String
        var quality: AVSpeechSynthesisVoiceQuality
        var gender: AVSpeechSynthesisVoiceGender

        init(_ voice: AVSpeechSynthesisVoice) {
            identifier = voice.identifier
            name = voice.name
            language = voice.language
            quality = voice.quality
            gender = voice.gender
        }

        init(identifier: String, name: String, language: String,
             quality: AVSpeechSynthesisVoiceQuality, gender: AVSpeechSynthesisVoiceGender = .unspecified) {
            self.identifier = identifier
            self.name = name
            self.language = language
            self.quality = quality
            self.gender = gender
        }
    }

    struct LanguageOption: Identifiable, Hashable {
        var id: String { code }
        var code: String
        var displayName: String
    }

    /// All non-novelty installed voices, including Standard quality, sorted by language then
    /// quality descending then name. Standard voices appear below Enhanced/Premium in each
    /// language group and are labelled "Standard".
    static func allGoodEntries(
        from all: [AVSpeechSynthesisVoice] = AVSpeechSynthesisVoice.speechVoices()
    ) -> [Entry] {
        all
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
    /// the best installed voice, following the C139 English preference order for English (Nora /
    /// "Voice 4" first, then Premium/Enhanced with gender+region scoring, then Samantha, Daniel,
    /// Karen, Moira, Tessa, then any remaining Standard), or quality+gender+region for other
    /// languages. Novelty voices are excluded. Siri's voices aren't offered to apps, so these are
    /// the Spoken Content voices.
    static func bestVoice(
        forLanguage code: String,
        gender: AVSpeechSynthesisVoiceGender? = nil,
        from all: [AVSpeechSynthesisVoice] = AVSpeechSynthesisVoice.speechVoices()
    ) -> AVSpeechSynthesisVoice? {
        let proxies = all.map { VoiceProxy($0) }
        guard let best = bestVoiceProxy(forLanguage: code, gender: gender, from: proxies) else {
            return AVSpeechSynthesisVoice(language: code.replacingOccurrences(of: "_", with: "-"))
        }
        return all.first { $0.identifier == best.identifier }
            ?? AVSpeechSynthesisVoice(language: code.replacingOccurrences(of: "_", with: "-"))
    }

    /// Rankable voice selection extracted for unit testing (inject any `[VoiceProxy]`).
    static func bestVoiceProxy(
        forLanguage code: String,
        gender: AVSpeechSynthesisVoiceGender? = nil,
        from proxies: [VoiceProxy]
    ) -> VoiceProxy? {
        let base = ListenLanguage.baseCode(code)
        let wanted = canonicalLang(code)
        let region = wanted.contains("-") ? String(wanted.split(separator: "-").last ?? "")
            : Locale.current.region?.identifier.lowercased()
        let isEnglish = base == "en"
        let candidates = proxies.filter { ListenLanguage.baseCode($0.language) == base && !isNoveltyName($0.name) }
        func score(_ v: VoiceProxy) -> Int {
            if isEnglish && isNoraNatural(v) { return 100_000 }
            var s = qualityRank(v.quality) * 100
            if let gender, gender != .unspecified, v.gender == gender { s += 10 }
            if let region, canonicalLang(v.language).hasSuffix("-" + region) { s += 5 }
            if isEnglish { s += englishFallbackBonus(for: v) }
            return s
        }
        return candidates.max { score($0) < score($1) }
    }

    /// Whether any Enhanced or Premium voice is installed for `code` (Settings' prepare hint).
    static func hasHighQualityVoice(forLanguage code: String,
                                    from all: [AVSpeechSynthesisVoice] = AVSpeechSynthesisVoice.speechVoices()) -> Bool {
        let base = ListenLanguage.baseCode(code)
        return all.contains { ListenLanguage.baseCode($0.language) == base && qualityRank($0.quality) >= 2 }
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

    private static func isNoveltyName(_ name: String) -> Bool {
        let lowered = name.lowercased()
        let blocked = ["zarvox", "trinoids", "whisper", "bad news", "good news", "bells", "bubbles", "cellos", "boing",
                       "bahh", "wobble", "jester", "organ", "superstar", "albert"]
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
        if qualityRank(lhs.voice.quality) != qualityRank(rhs.voice.quality) {
            return qualityRank(lhs.voice.quality) > qualityRank(rhs.voice.quality)
        }
        return lhs.voice.name < rhs.voice.name
    }

    private static func qualityRank(_ quality: AVSpeechSynthesisVoiceQuality) -> Int {
        switch quality {
        case .premium: return 3
        case .enhanced: return 2
        default: return 1
        }
    }

    /// C139: Nora's natural-voice id pattern (iOS id differs from macOS; match id first, name as
    /// a fallback for future system variants).
    private static func isNoraNatural(_ v: VoiceProxy) -> Bool {
        v.identifier.lowercased().contains("siri.natural.nora") || v.name == "Voice 4"
    }

    /// C139: bonus for Standard-quality English named fallback voices in preference order.
    /// Scores sit above Standard+gender+region max (115) and below Enhanced minimum (200).
    private static func englishFallbackBonus(for v: VoiceProxy) -> Int {
        guard v.quality == .default else { return 0 }
        let id = v.identifier.lowercased()
        let name = v.name.lowercased()
        if id.contains("samantha") || name == "samantha" { return 80 }
        if id.contains("daniel")   || name == "daniel"   { return 65 }
        if id.contains("karen")    || name == "karen"     { return 50 }
        if id.contains("moira")    || name == "moira"     { return 35 }
        if id.contains("tessa")    || name == "tessa"     { return 20 }
        return 0
    }
}
