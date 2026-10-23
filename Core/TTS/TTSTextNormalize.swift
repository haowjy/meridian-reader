import Foundation

/// Shared meaning-preserving cleanup before synth (any on-device engine).
/// Whitespace collapse, aside/em dashes → colon pauses, clause semicolons → comma pauses,
/// punctuation tidy. Does not change displayed reader HTML — listen path only.
enum TTSTextNormalize {
    /// Light, meaning-preserving cleanup before synth.
    /// - collapses all whitespace runs (incl. newlines / NBSP) to one space
    /// - turns aside dashes and glued em/horizontal-bar dashes into colons so the engine pauses
    ///   (` - `, `worse—and`, spaced ` — `); ASCII hyphen compounds stay (`Ashby-Lowell`,
    ///   `three-day`); en/figure dashes between word characters stay (ranges: `10–12`,
    ///   `Monday–Friday`)
    /// - turns clause semicolons into commas (`foo; bar` → `foo, bar`); semicolons inside
    ///   tokens (URLs / query params: `a.com/x;y`) stay
    static func normalize(_ text: String) -> String {
        var s = text.replacingOccurrences(of: "\u{00A0}", with: " ")
        s = s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !s.isEmpty else { return s }
        s = replaceAsideDashes(s)
        // Clause semicolons → comma pauses (Kokoro/Phonon often ignore `;`). Keep `;` that is
        // not a clause break (URL / path / code: `a.com/x;y=1`).
        s = s.replacingOccurrences(of: #";(?=\s|$)"#, with: ",", options: .regularExpression)
        // Tidy punctuation the dash / semicolon passes can create.
        s = s.replacingOccurrences(of: #"\s+:"#, with: ":", options: .regularExpression)
        s = s.replacingOccurrences(of: #":(\s*[:,])+|,(\s*,)*\s*:"#, with: ":", options: .regularExpression)
        s = s.replacingOccurrences(of: #"([.!?…]):"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #":\s*([.!?…])"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"^:\s*"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+,"#, with: ",", options: .regularExpression)
        s = s.replacingOccurrences(of: #",(\s*,)+"#, with: ",", options: .regularExpression)
        s = s.replacingOccurrences(of: #"([.!?…]),"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #",\s*([.!?…])"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"^,\s*"#, with: "", options: .regularExpression)
        s = s.split(whereSeparator: { $0 == " " }).joined(separator: " ")
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// Em / horizontal-bar dashes are clause breaks even when glued between words (`worse—and`).
    /// En / figure dashes between word characters stay (numeric and word ranges). ASCII `-`
    /// between letters/digits stays (compounds / ranges).
    private static func replaceAsideDashes(_ s: String) -> String {
        let dashes: Set<Character> = ["-", "–", "—", "‒", "―"]
        // Between word characters, only these become a colon pause.
        let clauseDashes: Set<Character> = ["—", "―"]
        let quoteLike: Set<Character> = ["\"", "'", "“", "”", "‘", "’", "«", "»", "(", ")", "[", "]"]
        let chars = Array(s)
        var out = ""
        out.reserveCapacity(chars.count + 8)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            guard dashes.contains(c) else {
                out.append(c)
                i += 1
                continue
            }
            var j = i
            while j < chars.count, dashes.contains(chars[j]) { j += 1 }
            let run = chars[i..<j]
            let before: Character? = i > 0 ? chars[i - 1] : nil
            let after: Character? = j < chars.count ? chars[j] : nil
            let spaceBefore = before == nil || before!.isWhitespace
            let spaceAfter = after == nil || after!.isWhitespace
            let wordBefore = before.map { $0.isLetter || $0.isNumber } ?? false
            let wordAfter = after.map { $0.isLetter || $0.isNumber } ?? false
            let onlyASCIIHyphen = run.allSatisfy { $0 == "-" }
            if wordBefore && wordAfter {
                if onlyASCIIHyphen || run.allSatisfy({ !clauseDashes.contains($0) }) {
                    // Intra-word hyphen / en-dash range: keep as-is (`Ashby-Lowell`, `10–12`).
                    out.append(contentsOf: run)
                } else {
                    // Em / horizontal-bar between words → colon pause (books: "worse—and" → "worse: and").
                    out.append(": ")
                }
            } else if spaceBefore || spaceAfter {
                // Aside / trailing / leading dash → pause.
                if spaceBefore && !spaceAfter {
                    out.append(": ") // " -nobody" → " : nobody" (tidied to ": nobody")
                } else {
                    out.append(":") // "year- " / " - " → "year: " / " : "
                }
            } else if wordBefore, let a = after, ".,;:!?…".contains(a),
                      j + 1 == chars.count || chars[j + 1].isWhitespace || quoteLike.contains(chars[j + 1]) {
                // Dash glued to closing punctuation ("etc-." / "etc-,"): drop it.
            } else if (before.map(quoteLike.contains) ?? false) || (after.map(quoteLike.contains) ?? false) {
                // Quote/bracket-adjacent (e.g. quote-dash or dash-quote): soft pause.
                out.append(", ")
            } else {
                // Inside a token next to other punctuation (URL / path / code: `a.com/-/x`,
                // `foo-_bar`): keep as-is; a ", " here would put a space into the URL.
                out.append(contentsOf: run)
            }
            i = j
        }
        return out
    }
}
