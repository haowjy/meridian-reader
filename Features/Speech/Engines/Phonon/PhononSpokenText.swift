import Foundation

/// Phonon-only spoken-text footguns applied at render (not at plan time).
///
/// **Not** a second normalizer. Gradium's English `normalize_text` already runs inside every
/// `Phonon.synthesize` because we load with `language: .english` (see `PhononHost`). That
/// rewrite owns numbers, symbols, currency, ellipsis→`.`, dash→space, `;`/`:`→comma pauses.
/// Meridian's shared `TTSTextNormalize` stays upstream for pause rules Gradium does not do
/// the way we want (em dash → colon pause for both engines). This type only fixes Gradium
/// mishandles *before* that path: shouty ALL CAPS (31m reads them oddly) and `?.` / `?…`
/// (StringAppender pops `?`/`!` when it later pushes `.`). Must only change letter case or
/// drop redundant `.`/`…` after `?`/`!` — planned chunks still reassemble to
/// `TTSTextNormalize.normalize(paragraph)` for SubParagraphPosition / cache invariants.
enum PhononSpokenText {
    static func prepare(_ text: String) -> String {
        var s = preserveQuestionAndExclaim(text)
        s = softenAllCaps(s)
        return s
    }

    /// Phonon's `StringAppender` pops a preceding `?`/`!` when it later pushes `.` or `,`.
    /// Ellipsis is rewritten to `.`, so `Really?…` becomes `Really.`. Collapse those so the
    /// ender that carries intonation reaches the model.
    static func preserveQuestionAndExclaim(_ text: String) -> String {
        text.replacingOccurrences(of: #"([?!])[.…]+"#, with: "$1", options: .regularExpression)
    }

    /// Downcase shouty prose / long ALL-CAPS words; keep short acronyms (`FBI`, `NASA`, `HTML`).
    static func softenAllCaps(_ text: String) -> String {
        let letters = text.filter(\.isLetter)
        guard letters.count >= 6 else { return text }
        let upper = letters.filter(\.isUppercase).count
        let ratio = Double(upper) / Double(letters.count)
        if ratio >= 0.85, hasLongAllCapsWord(text) {
            return sentenceCase(text)
        }
        return text.split(separator: " ", omittingEmptySubsequences: false)
            .map { softenWord(String($0)) }
            .joined(separator: " ")
    }

    // MARK: - Helpers

    private static func hasLongAllCapsWord(_ text: String) -> Bool {
        for raw in text.split(whereSeparator: { $0.isWhitespace }) {
            let body = alphabeticBody(of: String(raw))
            if body.count >= 5, body.unicodeScalars.allSatisfy({ CharacterSet.uppercaseLetters.contains($0) }) {
                return true
            }
        }
        return false
    }

    private static func softenWord(_ word: String) -> String {
        guard let (lead, body, trail) = splitPunctuation(word) else { return word }
        guard body.count >= 5,
              body.unicodeScalars.allSatisfy({ CharacterSet.uppercaseLetters.contains($0) }),
              body.contains(where: { "AEIOUY".contains($0) }) else { return word }
        return lead + body.lowercased() + trail
    }

    private static func sentenceCase(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        var capitalizeNext = true
        for c in text {
            if c.isLetter {
                if capitalizeNext {
                    out.append(contentsOf: String(c).uppercased())
                    capitalizeNext = false
                } else {
                    out.append(contentsOf: String(c).lowercased())
                }
            } else {
                out.append(c)
                if ".!?…".contains(c) { capitalizeNext = true }
            }
        }
        return out
    }

    private static func alphabeticBody(of word: String) -> String {
        String(word.filter(\.isLetter))
    }

    /// Leading non-letters, alphabetic body, trailing non-letters. Nil when no letters.
    private static func splitPunctuation(_ word: String) -> (String, String, String)? {
        let chars = Array(word)
        guard let first = chars.firstIndex(where: { $0.isLetter }),
              let last = chars.lastIndex(where: { $0.isLetter }) else { return nil }
        let lead = String(chars[..<first])
        let body = String(chars[first...last])
        let trail = String(chars[(last + 1)...])
        // Only soften pure-letter bodies (no digits / hyphens inside).
        guard body.allSatisfy(\.isLetter) else { return nil }
        return (lead, body, trail)
    }
}
