import Foundation
import NaturalLanguage

/// Reader local patch (C132): context-aware heteronyms for the CPU Kokoro frontend.
///
/// `us_lexicon_cache.json` keeps one pronunciation per word (Misaki's `DEFAULT`), so `read`,
/// `live`, `lead`, `close`, `record`… always sound the same. This restores Misaki's
/// part-of-speech entries (`KokoroHeteronyms.json`, the 639 us_gold words whose variants
/// differ) and picks one per occurrence the way Misaki's `Lexicon.get_word` does: the
/// token's tag, then its parent tag (VERB/NOUN/ADJ/ADV), then `DEFAULT`. Tags come from
/// Apple's `NLTagger(.lexicalClass)` (on-device). NLTagger has no tense, so past forms
/// (`VBD`/`VBN`) are word rules (`choose`): `read`/`reread` → rɛd after have/has/had/was/were/
/// been/being/is/are/get… (adverbs and `not` may sit between), `wound` as a verb → wWnd, and
/// `used to` → jˈust (not after was/is: `was used to build`).
///
/// Output: the text with each re-pronounced occurrence replaced by a placeholder word, plus
/// the placeholder → IPA overrides for the phonemizer's custom lexicon (checked first).
struct KokoroHeteronyms: Sendable {
    let entries: [String: [String: String]]

    static let placeholderPrefix = "zqhet"

    init(entries: [String: [String: String]]) { self.entries = entries }

    /// Loads `KokoroHeteronyms.json`, dropping phonemes the vocab can't encode.
    init?(url: URL, allowedTokens: Set<String>) {
        guard let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode([String: [String: String]].self, from: data)
        else { return nil }
        var out: [String: [String: String]] = [:]
        for (word, variants) in raw {
            let ok = variants.filter { $0.value.allSatisfy { allowedTokens.contains(String($0)) } }
            if ok["DEFAULT"] != nil, ok.count > 1 { out[word.lowercased()] = ok }
        }
        entries = out
    }

    static let auxiliaries: Set<String> = [
        "have", "has", "had", "having", "'ve", "’ve", "'d", "’d",
        "was", "were", "been", "being", "is", "are", "am", "be", "'s", "’s", "'re", "’re", "'m", "’m",
        "get", "gets", "got", "gotten", "getting",
    ]
    static let skippable: Set<String> = ["not", "n't", "n’t", "never", "just", "already", "also", "all", "once", "since"]

    /// Cheap pre-check: does any word of `text` have variants? Most sentences don't, and skip
    /// the tagger entirely.
    func mayApply(to text: String) -> Bool {
        var word = ""
        for ch in text {
            if ch.isLetter { word.append(ch) } else {
                if !word.isEmpty, entries[word.lowercased()] != nil { return true }
                word.removeAll(keepingCapacity: true)
            }
        }
        return !word.isEmpty && entries[word.lowercased()] != nil
    }

    func annotate(_ text: String) -> (text: String, overrides: [String: String]) {
        guard !entries.isEmpty, mayApply(to: text) else { return (text, [:]) }
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        tagger.setLanguage(.english, range: text.startIndex..<text.endIndex)
        var tokens: [(range: Range<String.Index>, word: String, tag: NLTag?)] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass,
                             options: [.omitWhitespace, .omitPunctuation]) { tag, range in
            tokens.append((range, text[range].lowercased(), tag))
            return true
        }
        var picks: [(Range<String.Index>, String)] = []
        for (i, token) in tokens.enumerated() {
            guard let variants = entries[token.word], let fallback = variants["DEFAULT"] else { continue }
            // Inside a hyphenated or glued word (`well-read`): leave it to the lexicon.
            if token.range.lowerBound > text.startIndex {
                let before = text[text.index(before: token.range.lowerBound)]
                if before == "-" || before.isLetter { continue }
            }
            if token.range.upperBound < text.endIndex {
                let after = text[token.range.upperBound]
                if after == "-" || after.isLetter { continue }
            }
            let next = i + 1 < tokens.count ? tokens[i + 1].word : nil
            let ipa = Self.choose(token.word, variants, tag: token.tag, afterAuxiliary: afterAuxiliary(tokens, i),
                                  next: next) ?? fallback
            if ipa != fallback { picks.append((token.range, ipa)) }
        }
        guard !picks.isEmpty else { return (text, [:]) }
        var out = ""
        var overrides: [String: String] = [:]
        var cursor = text.startIndex
        for (n, (range, ipa)) in picks.enumerated() {
            let key = Self.placeholderPrefix + Self.letters(n)
            out += text[cursor..<range.lowerBound]
            out += key
            overrides[key] = ipa
            cursor = range.upperBound
        }
        out += text[cursor...]
        return (out, overrides)
    }

    private func afterAuxiliary(_ tokens: [(range: Range<String.Index>, word: String, tag: NLTag?)], _ i: Int) -> Bool {
        var j = i - 1
        var skipped = 0
        while j >= 0, skipped <= 2 {
            let w = tokens[j].word
            if Self.auxiliaries.contains(w) { return true }
            guard tokens[j].tag == .adverb || Self.skippable.contains(w) else { return false }
            skipped += 1
            j -= 1
        }
        return false
    }

    /// Misaki's past forms only where it means them: `read`/`reread` after an auxiliary
    /// (`had read`, `was read`); `wound` whenever it is a verb; `used` only as `used to`.
    static func choose(_ word: String, _ v: [String: String], tag: NLTag?, afterAuxiliary: Bool,
                       next: String?) -> String? {
        let past = v["VBN"] ?? v["VBD"]
        switch word {
        case "used": return next == "to" && !afterAuxiliary ? v["VBD"] : nil
        case "wound": return tag == .verb ? past : nil
        case "read", "reread":
            if afterAuxiliary, tag == .verb || tag == .adjective { return past }
        default: break
        }
        switch tag {
        case .verb?: return v["VERB"]
        case .noun?: return v["NOUN"]
        case .adjective?: return v["ADJ"]
        case .adverb?: return v["ADV"]
        case .determiner?: return v["DT"]
        default: return nil
        }
    }

    /// Placeholders are letters only (`zqheta`, `zqhetb`, … `zqhetba`), so the phonemizer's
    /// word splitter keeps them whole.
    private static func letters(_ n: Int) -> String {
        var n = n, s = ""
        repeat { s = String(UnicodeScalar(UInt8(97 + n % 26))) + s; n /= 26 } while n > 0
        return s
    }
}
