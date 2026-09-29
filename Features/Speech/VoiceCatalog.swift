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

    static func goodVoices(
        from all: [AVSpeechSynthesisVoice] = AVSpeechSynthesisVoice.speechVoices(),
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> (recommended: [Entry], more: [Entry]) {
        let good = allGoodEntries(from: all)
        let preferredCodes = preferredLanguages.map { canonicalLang($0) }
        let deviceLang = canonicalLang(Locale.current.language.languageCode?.identifier ?? "en")

        func isPreferred(_ entry: Entry) -> Bool {
            let code = canonicalLang(entry.voice.language)
            if preferredCodes.contains(where: { code.hasPrefix($0) || $0.hasPrefix(code) }) { return true }
            return code.hasPrefix(deviceLang)
        }

        let recommended = good.filter(isPreferred).sorted(by: sortEntries)
        let recommendedIDs = Set(recommended.map(\.id))
        let more = good.filter { !recommendedIDs.contains($0.id) }.sorted(by: sortEntries)
        return (recommended, more)
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

    /// Apple voice for speaking `code` when the user hasn't picked one for that language:
    /// the system's voice for the exact code, else the best installed voice sharing the base
    /// language (current region first, then quality).
    static func bestVoice(
        forLanguage code: String,
        from all: [AVSpeechSynthesisVoice] = AVSpeechSynthesisVoice.speechVoices()
    ) -> AVSpeechSynthesisVoice? {
        if code.contains("-") || code.contains("_"),
           let exact = AVSpeechSynthesisVoice(language: code.replacingOccurrences(of: "_", with: "-")) {
            return exact
        }
        let base = ListenLanguage.baseCode(code)
        let region = Locale.current.region?.identifier.lowercased()
        let candidates = all.filter { ListenLanguage.baseCode($0.language) == base }
        return candidates.max { a, b in
            func score(_ v: AVSpeechSynthesisVoice) -> Int {
                var s = qualityRank(v) * 10
                if let region, canonicalLang(v.language).hasSuffix("-" + region) { s += 100 }
                if isNoveltyName(v.name) { s -= 1_000 }
                return s
            }
            return score(a) < score(b)
        } ?? AVSpeechSynthesisVoice(language: code)
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
