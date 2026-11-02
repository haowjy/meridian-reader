import Foundation
import NaturalLanguage

/// Article language for Listen: detection (`NLLanguageRecognizer` over the listen blocks), checked
/// against the article's engine's `EngineDescriptor.supportedLanguages`. An article detected in
/// a language its engine doesn't speak isn't read or prepared; one with nothing detected is read.
enum ListenLanguage {
    /// Characters of listen text fed to the recognizer (first blocks, in order).
    static let sampleCharacterLimit = 4_000
    /// Below this the text is too short to trust (returns nil: read in the engine's language).
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

    /// The language detected in `paragraphs` when `engine` doesn't speak it ("fr"); nil when it
    /// does, or when nothing is detected.
    static func unspoken(in paragraphs: [String], by engine: EngineDescriptor) -> String? {
        guard let code = detectCached(paragraphs: paragraphs), !engine.supportsLanguage(code) else { return nil }
        return code
    }

    /// What ▶ and Prepare say about an article in `code`: "Can't read French yet."
    static func refusal(_ code: String) -> String {
        String(localized: "Can’t read \(displayName(for: code)) yet.")
    }
}
