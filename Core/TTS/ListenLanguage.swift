import Foundation
import NaturalLanguage

/// Article language for Listen: detection (`NLLanguageRecognizer` over the listen blocks) and
/// resolution against the user's setting (Automatic vs a manual language) and the selected
/// engine's `EngineDescriptor.supportedLanguages`.
enum ListenLanguage {
    /// Characters of listen text fed to the recognizer (first blocks, in order).
    static let sampleCharacterLimit = 4_000
    /// Below this the text is too short to trust (returns nil → setting's language).
    static let minimumSampleCharacters = 24
    static let minimumConfidence = 0.5

    /// "en-US" / "en_GB" / "zh-Hans" → "en" / "en" / "zh".
    static func baseCode(_ code: String) -> String {
        let normalized = code.replacingOccurrences(of: "_", with: "-")
        return (normalized.split(separator: "-").first.map(String.init) ?? normalized).lowercased()
    }

    /// "French" for "fr" / "fr-CA".
    static func displayName(for code: String) -> String {
        Locale.current.localizedString(forLanguageCode: baseCode(code)) ?? code
    }

    /// First `sampleCharacterLimit` characters of the listen blocks.
    static func sample(_ paragraphs: [String]) -> String {
        var out = ""
        for p in paragraphs {
            if !out.isEmpty { out += "\n" }
            out += p
            if out.count >= sampleCharacterLimit { break }
        }
        return String(out.prefix(sampleCharacterLimit))
    }

    /// Dominant language of the listen text as an `NLLanguage` code ("en", "fr", "zh-Hans"),
    /// nil when the text is too short or the recognizer isn't confident.
    static func detect(paragraphs: [String]) -> String? {
        detect(text: sample(paragraphs))
    }

    static func detect(text: String) -> String? {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        guard letters >= minimumSampleCharacters else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
              language != .undetermined, confidence >= minimumConfidence else { return nil }
        return language.rawValue
    }

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cache: [String: String] = [:]
    nonisolated(unsafe) private static var misses: Set<String> = []

    /// `detect(paragraphs:)` memoized by sample text (open / play / bake gates call this often).
    static func detectCached(paragraphs: [String]) -> String? {
        let text = sample(paragraphs)
        cacheLock.lock()
        if let hit = cache[text] { cacheLock.unlock(); return hit }
        if misses.contains(text) { cacheLock.unlock(); return nil }
        cacheLock.unlock()
        let result = detect(text: text)
        cacheLock.lock()
        if cache.count + misses.count > 128 { cache.removeAll(); misses.removeAll() }
        if let result { cache[text] = result } else { misses.insert(text) }
        cacheLock.unlock()
        return result
    }
}

/// Which language an article speaks in and which engine speaks it.
struct ListenLanguageResolution: Equatable, Sendable {
    enum Source: String, Equatable, Sendable {
        /// Automatic, detected from the article text.
        case detected
        /// The user picked a language.
        case manual
        /// Automatic, but nothing was detected: the manual/device language.
        case fallback
    }

    let languageCode: String
    let source: Source
    /// Engine that speaks this article: the selected engine, or Apple when the selected engine
    /// can't speak `languageCode` (per article; the setting doesn't change).
    let engineID: SpeechEngineID
    /// The selected engine when it was bypassed for this language.
    let unsupportedEngineID: SpeechEngineID?
    /// Subtle UI note for the fallback, e.g. "Apple · French (Kokoro is English-only)".
    let note: String?

    var languageName: String { ListenLanguage.displayName(for: languageCode) }

    static func resolve(
        automatic: Bool,
        manualCode: String,
        detectedCode: String?,
        selectedEngine: EngineDescriptor?
    ) -> ListenLanguageResolution {
        let code: String
        let source: Source
        if automatic, let detectedCode {
            code = detectedCode
            source = .detected
        } else {
            code = manualCode
            source = automatic ? .fallback : .manual
        }
        guard let engine = selectedEngine, engine.id.isLocal, !engine.supportsLanguage(code) else {
            return ListenLanguageResolution(
                languageCode: code, source: source, engineID: selectedEngine?.id ?? .apple,
                unsupportedEngineID: nil, note: nil)
        }
        let limit = engine.languageLimitNote ?? "\(engine.shortName) can't speak it"
        return ListenLanguageResolution(
            languageCode: code, source: source, engineID: .apple, unsupportedEngineID: engine.id,
            note: "Apple · \(ListenLanguage.displayName(for: code)) (\(limit))")
    }
}
