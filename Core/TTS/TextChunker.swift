import Foundation

/// Splits one listen paragraph into per-call synth chunks for an on-device engine.
///
/// Why: every local engine has a per-call input/output cap (Kokoro: 510 IPA phonemes /
/// 2000 frames). Oversized input fails (or wastes a whole decode) instead of truncating, so we
/// keep every chunk under the engine's `hardMax` *estimated* units (chars, digits weighted ×3
/// because "2240" is spoken as four words). Limits come from the engine's `EngineDescriptor`.
///
/// Paragraphs stay the UI/listen unit; chunks are an internal synth detail.
/// Invariants (tested, incl. 10k-char paragraphs): every chunk ≤ `hardMax`; the first chunk of
/// a multi-chunk paragraph ≤ `firstTarget`; words are never cut while a space exists;
/// `chunks(for: t).joined(separator: " ") == normalize(t)` unless a single whitespace-free run
/// exceeds the limit (then it is cut mid-run and the pieces concatenate back to the run).
enum TextChunker {
    /// Per-engine chunk sizing (estimated units ≈ chars, digits ×3).
    struct Limits: Equatable, Sendable {
        /// Preferred chunk size. Merges tiny sentences up to this.
        var target: Int
        /// Never exceed this.
        var hardMax: Int
        /// First chunk of a multi-chunk paragraph never exceeds this, so first audio lands sooner.
        var firstTarget: Int
        /// Below this we stop re-splitting on synth overflow and fall back to Apple TTS.
        var minResplit: Int
        /// Split off a short first chunk even when the whole paragraph would fit one call
        /// (fast first audio on slower engines). Paragraphs ≤ `firstTarget + firstSlack` stay whole.
        var alwaysSplitFirst: Bool = false
        /// Second chunk budget (nil = `target`). With a short first chunk, the second must render
        /// within the first chunk's audio, so it ramps (≈160) before full-size chunks.
        var secondTarget: Int? = nil
        static let firstSlack = 24
        /// When the first sentence has no clause boundary (`; : —`, comma, before a conjunction)
        /// inside `firstTarget`, the first chunk may grow up to `firstTarget + firstStretch` to reach
        /// one (or the sentence end) instead of cutting between bare words. Kokoro ONNX on the phone
        /// (iPhone 17 Pro, 231 chunks, 2026-09-25): render ≈ 0.35 s + 23 ms/char (median), worst
        /// ≈ 28 ms/char → 80 units ≈ 2.2 s (worst 2.8 s) to first audio, 120 units ≈ 3.1 s (worst
        /// 4.1 s). +40 keeps first audio ≈ 3 s typical; beyond that the wait becomes noticeable.
        static let firstStretch = 40

        /// Engines capped at ≈10 s of audio per call (e.g. Qwen3-TTS: 125 codec tokens).
        /// 140 units ≈ 9.0 s at a measured p95 of 0.064 s of audio per char. Also used to split
        /// Apple *fallback* text. (Formerly `.nano`, sized for the retired Chatterbox Nano.)
        static let tenSecondCall = Limits(target: 120, hardMax: 140, firstTarget: 90, minResplit: 24)

        /// Kokoro (KokoroAne): input cap 510 IPA phonemes (`KokoroAneConstants.maxPhonemeLength`,
        /// ALBERT 512 ctx) and 2000 acoustic frames (≈50 s at 40 frames/s — never binds first).
        /// English Misaki IPA runs ≈0.8–1.0 phoneme chars per text char (stress marks included),
        /// so 300 units stays well under 510 even for dense text; overflow is re-split anyway.
        /// First chunk kept short (~100 chars ≈ 6 s audio) for fast first audio.
        static let kokoro = Limits(target: 220, hardMax: 300, firstTarget: 100, minResplit: 24)

        /// Kokoro on the ONNX CPU route (the default route since 2026-09-24). ≈1.0–1.3 phonemes
        /// per char. Chunks ramp so playback never waits after the first one: first ≤ 80 units
        /// (≈5 s of audio, ≈1.5 s to render on iPhone 17 Pro at ≈2.7× real time), second ≤ 160
        /// (renders in ≈3.5 s, inside the first chunk's 5 s), then whole sentences packed to 240,
        /// never over 280 (≈300 tokens, ≈18 s of audio; ORT activation memory grows ≈1.3 MB/token,
        /// ≈+380 MB at 300 tokens measured on the Mac). Longer chunks = fewer joins and Kokoro
        /// keeps sentence prosody; sentences are only split when longer than 280 (at clauses).
        /// Deterministic per text, so live chunks and bake-ahead share one plan.
        static let kokoroCPU = Limits(target: 240, hardMax: 280, firstTarget: 80, minResplit: 24,
                                      alwaysSplitFirst: true, secondTarget: 160)
    }

    /// Defaults = Kokoro (the only on-device engine). Callers normally pass `limits:`.
    static let target = Limits.kokoro.target
    static let hardMax = Limits.kokoro.hardMax
    static let firstTarget = Limits.kokoro.firstTarget
    static let minResplit = Limits.kokoro.minResplit

    static func chunks(for text: String, limits: Limits) -> [String] {
        chunks(for: text, target: limits.target, hardMax: limits.hardMax, firstTarget: limits.firstTarget,
               secondTarget: limits.secondTarget, alwaysSplitFirst: limits.alwaysSplitFirst)
    }

    // MARK: - Normalization

    /// Light, meaning-preserving cleanup before synth.
    /// - collapses all whitespace runs (incl. newlines / NBSP) to one space
    /// - turns "aside" dashes (`-nobody … year-`, `–nurse, etc-`, ` - `) into commas so the engine
    ///   pauses instead of reading/choking on stray hyphens; intra-word hyphens stay
    ///   (`Ericcson-Sprucefeld`, `three-day`).
    static func normalize(_ text: String) -> String {
        var s = text.replacingOccurrences(of: "\u{00A0}", with: " ")
        s = s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !s.isEmpty else { return s }
        s = replaceAsideDashes(s)
        // Tidy punctuation the dash pass can create.
        s = s.replacingOccurrences(of: #"\s+,"#, with: ",", options: .regularExpression)
        s = s.replacingOccurrences(of: #",(\s*,)+"#, with: ",", options: .regularExpression)
        s = s.replacingOccurrences(of: #"([.!?…]),"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #",\s*([.!?…])"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"^,\s*"#, with: "", options: .regularExpression)
        s = s.split(whereSeparator: { $0 == " " }).joined(separator: " ")
        return s.trimmingCharacters(in: .whitespaces)
    }

    private static func replaceAsideDashes(_ s: String) -> String {
        let dashes: Set<Character> = ["-", "–", "—", "‒", "―"]
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
            let before: Character? = i > 0 ? chars[i - 1] : nil
            let after: Character? = j < chars.count ? chars[j] : nil
            let spaceBefore = before == nil || before!.isWhitespace
            let spaceAfter = after == nil || after!.isWhitespace
            let wordBefore = before.map { $0.isLetter || $0.isNumber } ?? false
            let wordAfter = after.map { $0.isLetter || $0.isNumber } ?? false
            if wordBefore && wordAfter {
                // Intra-word hyphen / range: keep as-is.
                out.append(contentsOf: chars[i..<j])
            } else if spaceBefore || spaceAfter {
                // Aside / trailing / leading dash → pause.
                if spaceBefore && !spaceAfter {
                    out.append(", ")       // " -nobody" → " , nobody" (tidied to ", nobody")
                } else {
                    out.append(",")        // "year- " / " - " → "year, " / " , "
                }
            } else if wordBefore, let a = after, ".,;:!?…".contains(a),
                      j + 1 == chars.count || chars[j + 1].isWhitespace || quoteLike.contains(chars[j + 1]) {
                // Dash glued to closing punctuation ("etc-." / "etc-,"): drop it.
            } else if (before.map(quoteLike.contains) ?? false) || (after.map(quoteLike.contains) ?? false) {
                // Quote/bracket-adjacent (e.g. `”-` or `-“`): soft pause.
                out.append(", ")
            } else {
                // Inside a token next to other punctuation (URL / path / code: `a.com/-/x`,
                // `foo-_bar`): keep as-is. (Used to become ", ", inserting a space into URLs.)
                out.append(contentsOf: chars[i..<j])
            }
            i = j
        }
        return out
    }

    // MARK: - Chunking

    /// Estimated spoken length. Digits read as several syllables ("2.5 hundred", years).
    static func estimatedUnits(_ s: String) -> Int {
        var n = 0
        for c in s { n += c.isNumber ? 3 : 1 }
        return n
    }

    /// Hierarchical: paragraph → sentences → (only for sentences that don't fit) clauses → words.
    /// - Whole sentences are packed greedily up to the chunk's budget (first: `firstTarget`,
    ///   second: `secondTarget`, then `target`); a sentence that fits `hardMax` is never split
    ///   except to make the short first/second chunk.
    /// - The first chunk: the first sentence if ≤ `firstTarget + firstSlack`, else its head cut at
    ///   the strongest boundary that fits (`; : —` > `,` > before a conjunction > space).
    /// - The second chunk (when `secondTarget` is set): a sentence longer than it is cut only at a
    ///   clause boundary (`; : —` or `,`); if it has none, it stays whole.
    /// - Sentences longer than `hardMax` are cut into balanced pieces at the strongest boundaries.
    static func chunks(
        for text: String,
        target: Int = TextChunker.target,
        hardMax: Int = TextChunker.hardMax,
        firstTarget: Int = TextChunker.firstTarget,
        secondTarget: Int? = nil,
        alwaysSplitFirst: Bool = false
    ) -> [String] {
        let normalized = normalize(text)
        guard !normalized.isEmpty else { return [] }
        let target = min(target, hardMax)
        let wholeLimit = alwaysSplitFirst
            ? min(firstTarget + Limits.firstSlack, target, hardMax)
            : target
        if estimatedUnits(normalized) <= wholeLimit { return [normalized] }

        let firstLimit = min(firstTarget, target)
        let firstCap = min(firstLimit + Limits.firstStretch, hardMax)
        let secondLimit = min(secondTarget ?? target, target)
        var queue = splitSentences(normalized)
        queue.reverse() // pop from the end
        var out: [String] = []
        var buffer = ""

        func flush() {
            if !buffer.isEmpty { out.append(buffer); buffer = "" }
        }

        // Head-start ramp: chunk k (k ≥ 1) must finish rendering before the audio already
        // queued ahead of it runs out. Rendering runs ≥ 2× real time (≈2.4–3.1× measured on the
        // phone), so render(1…k) ≤ audio(0…k−1) holds when u_k ≤ 2·u_0 + u_1 + … + u_{k−1}.
        func budget(_ k: Int) -> Int {
            if k == 0 { return firstLimit }
            guard secondTarget != nil else { return target }
            let lead = 2 * estimatedUnits(out[0]) + out.dropFirst().reduce(0) { $0 + estimatedUnits($1) }
            return min(k == 1 ? secondLimit : target, max(firstLimit, lead))
        }

        while let sentence = queue.popLast() {
            let k = out.count
            let budget = budget(k)
            let units = estimatedUnits(sentence)
            if !buffer.isEmpty {
                let candidate = buffer + " " + sentence
                if estimatedUnits(candidate) <= budget {
                    buffer = candidate
                } else if k == 0, let merged = growShortFirst(buffer, sentence, cap: firstCap) {
                    // A tiny first sentence ("Yes.") would play out long before the next chunk is
                    // rendered (a stall right after first audio): take the next sentence, or its
                    // head at a clause, into the first chunk while it stays within the cap.
                    out.append(merged.head)
                    buffer = ""
                    if let rest = merged.rest { queue.append(rest) }
                } else {
                    flush()
                    queue.append(sentence)
                }
                continue
            }
            if units <= budget {
                buffer = sentence
                continue
            }
            if k == 0 {
                // Short first chunk (fast first audio), never cut between bare words when avoidable:
                // 1. the whole first sentence if it fits the budget (+ a little slack);
                // 2. else its head at the best clause boundary inside the budget
                //    (`; : —` > comma > before a conjunction), head ≥ a third of the budget;
                // 3. else a slightly bigger first chunk (≤ firstTarget + firstStretch): the whole
                //    sentence, or its head at the nearest clause boundary past the budget;
                // 4. only then (a clause-free run) a space cut inside the budget.
                let cap = firstCap
                let minHead = max(12, firstLimit / 3)
                if units <= min(firstLimit + Limits.firstSlack, hardMax) {
                    out.append(sentence)
                } else if let (head, rest) = splitHead(sentence, maxUnits: firstLimit, minStrength: .conjunction,
                                                       minHead: minHead) {
                    out.append(head)
                    queue.append(rest)
                } else if units <= cap {
                    out.append(sentence)
                } else if let (head, rest) = stretchedHead(sentence, from: firstLimit, maxUnits: cap) {
                    out.append(head)
                    queue.append(rest)
                } else if let (head, rest) = splitHead(sentence, maxUnits: firstLimit, minStrength: .space) {
                    out.append(head)
                    queue.append(rest)
                } else {
                    // No usable space (e.g. a long URL): the old clause/space/hard-cut splitter.
                    let head = splitOversized(sentence, hardMax: firstLimit)[0]
                    out.append(head)
                    // The rest stays one piece: hard-cut pieces must not be re-joined with spaces.
                    let rest = sentence.dropFirst(head.count).drop(while: { $0 == " " })
                    if !rest.isEmpty { queue.append(String(rest)) }
                }
                continue
            }
            // Ramp chunk: cut at a clause only when the sentence clearly overshoots (+25% ≈ the
            // measured 2.4× worst case instead of the 2× planning rate); otherwise keep it whole.
            if budget < target, units > budget + budget / 4, units <= hardMax,
               let (head, rest) = splitHead(sentence, maxUnits: budget, minStrength: .comma) {
                out.append(head)
                queue.append(rest)
                continue
            }
            if units <= hardMax {
                out.append(sentence) // a whole sentence beats a cut
                continue
            }
            out.append(contentsOf: balancedSplit(sentence, target: target, hardMax: hardMax))
        }
        flush()
        return out
    }

    // MARK: - Cut points

    /// Strength of a cut *after* the text before it.
    enum CutStrength: Int, Comparable {
        case space = 0, conjunction = 1, comma = 2, strong = 3, sentence = 4
        static func < (a: CutStrength, b: CutStrength) -> Bool { a.rawValue < b.rawValue }
    }

    /// Words a clause often starts with; cutting just before them keeps phrases intact.
    static let conjunctions: Set<String> = [
        "and", "but", "or", "nor", "so", "yet", "because", "when", "while", "which", "who", "whom",
        "whose", "where", "although", "though", "if", "until", "unless", "since", "after", "before",
        "then", "whether", "whereas", "once",
    ]

    /// Cut candidates at spaces: (index of the space in `chars`, units before it, strength).
    private static func cutCandidates(_ chars: [Character]) -> [(space: Int, units: Int, strength: CutStrength)] {
        var out: [(Int, Int, CutStrength)] = []
        var units = 0
        var wordStart = 0
        var wordsBefore = 0
        for (i, c) in chars.enumerated() {
            if c == " " {
                let prevWord = String(chars[wordStart..<i]).lowercased().trimmingCharacters(in: .punctuationCharacters)
                wordsBefore += 1
                // Previous char decides clause strength; the next word decides "conjunction".
                let prev = i > 0 ? chars[i - 1] : " "
                var j = i + 1
                var next = ""
                while j < chars.count, chars[j] != " " { next.append(chars[j]); j += 1 }
                let nextWord = next.lowercased().trimmingCharacters(in: .punctuationCharacters)
                let strength: CutStrength
                var e = i - 1
                while e > 0, "\"'”’)]»".contains(chars[e]) { e -= 1 }
                if e >= 0, ".!?…".contains(chars[e]), i + 1 < chars.count,
                   isBoundary(chars: chars, enderIndex: e, afterIndex: i + 1) {
                    strength = .sentence
                } else if ";:—–".contains(prev) {
                    strength = .strong
                } else if prev == "," {
                    strength = .comma
                } else if wordsBefore >= 3, conjunctions.contains(nextWord),
                          !conjunctions.contains(prevWord) { // not "and | then"
                    strength = .conjunction
                } else {
                    strength = .space
                }
                out.append((i, units, strength))
                wordStart = i + 1
            }
            units += c.isNumber ? 3 : 1
        }
        return out
    }

    /// Cut `sentence` into (head, rest) with head ≤ `maxUnits`, at the strongest boundary
    /// (ties → the longest head). nil if no boundary of at least `minStrength` fits.
    static func splitHead(_ sentence: String, maxUnits: Int, minStrength: CutStrength,
                          minHead: Int = 12) -> (String, String)? {
        let chars = Array(sentence)
        let fits = cutCandidates(chars).filter { $0.units <= maxUnits && $0.units >= minHead && $0.strength >= minStrength }
        // Strongest boundary in the back half of the budget (a tiny head wastes the chunk);
        // if the back half has none, the strongest anywhere. Ties → the longest head.
        let backHalf = fits.filter { $0.units >= maxUnits / 2 }
        let pool = backHalf.isEmpty ? fits : backHalf
        guard let best = pool.max(by: { ($0.strength, $0.units) < ($1.strength, $1.units) }) else { return nil }
        return (String(chars[..<best.space]), String(chars[(best.space + 1)...]))
    }

    /// The first chunk is a short sentence and the next one would outrun it (rendering ≈ 2× real
    /// time: the next sentence needs more than twice the first's audio to render): grow the first
    /// chunk by the whole next sentence, or by its head at a clause boundary, within `cap`.
    static func growShortFirst(_ first: String, _ next: String, cap: Int) -> (head: String, rest: String?)? {
        let u = estimatedUnits(first)
        guard estimatedUnits(next) > 2 * u else { return nil }
        let whole = first + " " + next
        if estimatedUnits(whole) <= cap { return (whole, nil) }
        let room = cap - u - 1
        guard room >= 12, let (head, rest) = splitHead(next, maxUnits: room, minStrength: .conjunction) else { return nil }
        return (first + " " + head, rest)
    }

    /// First-chunk stretch: the head ending at a clause boundary (≥ conjunction) with
    /// `from` < units ≤ `maxUnits` — strongest first, ties → the shortest (sooner first audio).
    static func stretchedHead(_ sentence: String, from: Int, maxUnits: Int) -> (String, String)? {
        let chars = Array(sentence)
        let pool = cutCandidates(chars).filter { $0.units > from && $0.units <= maxUnits && $0.strength >= .conjunction }
        guard let best = pool.max(by: { ($0.strength, -$0.units) < ($1.strength, -$1.units) }) else { return nil }
        return (String(chars[..<best.space]), String(chars[(best.space + 1)...]))
    }

    /// True when `word` (the first word of the following chunk) starts a clause, so a cut just
    /// before it is a clause join, not a bare word join.
    static func startsClause(_ word: String) -> Bool {
        conjunctions.contains(word.lowercased().trimmingCharacters(in: .punctuationCharacters))
    }

    /// Cut a sentence longer than `hardMax` into the fewest pieces ≤ `hardMax`, choosing cut
    /// points that are strong (clause > conjunction > space) and keep the pieces near equal
    /// (no stray 5-char tail). Dynamic programming over the space positions.
    static func balancedSplit(_ sentence: String, target: Int, hardMax: Int) -> [String] {
        let chars = Array(sentence)
        let total = estimatedUnits(sentence)
        guard total > hardMax else { return [sentence] }
        let cands = cutCandidates(chars)
        // Any single word longer than hardMax → fall back to the space/hard-cut splitter.
        let words = sentence.split(separator: " ")
        if words.contains(where: { estimatedUnits(String($0)) > hardMax }) || cands.isEmpty {
            return splitOversized(sentence, hardMax: hardMax)
        }
        // Nodes: 0 = start, 1...n = cut after candidate i-1, n+1 = end.
        let n = cands.count
        func startUnits(_ node: Int) -> Int { node == 0 ? 0 : cands[node - 1].units + 1 }
        func endUnits(_ node: Int) -> Int { node == n + 1 ? total : cands[node - 1].units }
        let pieces = Int((Double(total) / Double(target)).rounded(.up))
        let ideal = Double(total) / Double(max(1, pieces))
        let penalty: [CutStrength: Double] = [.sentence: 0, .strong: 0.5, .comma: 1, .conjunction: 3, .space: 12]
        var best = [Double](repeating: .infinity, count: n + 2)
        var prev = [Int](repeating: -1, count: n + 2)
        best[0] = 0
        for j in 1...(n + 1) {
            for i in stride(from: j - 1, through: 0, by: -1) {
                let len = endUnits(j) - startUnits(i)
                if len > hardMax { break }
                guard best[i].isFinite, len > 0 else { continue }
                let cut = j == n + 1 ? 0 : penalty[cands[j - 1].strength]!
                let size = pow((Double(len) - ideal) / ideal, 2) * 6
                let cost = best[i] + cut + size + 4 // +4 per piece: prefer fewer pieces
                if cost < best[j] { best[j] = cost; prev[j] = i }
            }
        }
        guard best[n + 1].isFinite else { return splitOversized(sentence, hardMax: hardMax) }
        var cuts: [Int] = []
        var node = prev[n + 1]
        while node > 0 { cuts.append(cands[node - 1].space); node = prev[node] }
        cuts.reverse()
        var out: [String] = []
        var start = 0
        for c in cuts {
            out.append(String(chars[start..<c]))
            start = c + 1
        }
        out.append(String(chars[start...]))
        return out.filter { !$0.isEmpty }
    }

    /// Split one chunk that still overflowed the engine (retry path): roughly in half at the best
    /// clause/space boundary. Returns `[text]` when it cannot be split further.
    static func resplit(_ text: String, minResplit: Int = TextChunker.minResplit) -> [String] {
        let units = estimatedUnits(text)
        guard units > minResplit * 2 else { return [text] }
        let half = max(minResplit, units / 2 + 8)
        let pieces = chunks(for: text, target: half, hardMax: half, firstTarget: half)
        return pieces.count > 1 ? pieces : [text]
    }

    // MARK: - Sentence splitting

    private static let abbreviations: Set<String> = [
        "mr", "mrs", "ms", "dr", "st", "jr", "sr", "vs", "etc", "prof", "gen", "col", "lt", "sgt",
        "capt", "cmdr", "gov", "sen", "rep", "rev", "mt", "ft", "vol", "fig",
        "approx", "dept", "inc", "ltd", "corp", "e.g", "i.e", "a.m", "p.m", "u.s",
        "u.k", "u.s.a", "cf", "al",
    ]

    private static let sentenceEndingAbbreviations: Set<String> = ["etc", "inc", "ltd", "corp", "al"]

    /// Sentence boundaries: `.`/`!`/`?`/`…` (+ closing quotes/brackets) followed by a space.
    /// Not a boundary after known abbreviations, single-letter initials ("I. Ericcson"),
    /// dotted acronyms ("U.S.A."), or when the next word starts lowercase (". and", "... then").
    static func splitSentences(_ text: String) -> [String] {
        let chars = Array(text)
        let enders: Set<Character> = [".", "!", "?", "…"]
        let closers: Set<Character> = ["\"", "'", "”", "’", ")", "]", "»"]
        var sentences: [String] = []
        var start = 0
        var i = 0
        while i < chars.count {
            guard enders.contains(chars[i]) else { i += 1; continue }
            var j = i
            while j + 1 < chars.count, enders.contains(chars[j + 1]) { j += 1 }
            while j + 1 < chars.count, closers.contains(chars[j + 1]) { j += 1 }
            // Need a space after and some next word.
            guard j + 2 < chars.count, chars[j + 1] == " " else { i = j + 1; continue }
            if isBoundary(chars: chars, enderIndex: i, afterIndex: j + 2) {
                let s = String(chars[start...j]).trimmingCharacters(in: .whitespaces)
                if !s.isEmpty { sentences.append(s) }
                start = j + 2
            }
            i = j + 1
        }
        if start < chars.count {
            let tail = String(chars[start...]).trimmingCharacters(in: .whitespaces)
            if !tail.isEmpty { sentences.append(tail) }
        }
        return sentences
    }

    static func isBoundary(chars: [Character], enderIndex: Int, afterIndex: Int) -> Bool {
        let next = chars[afterIndex]
        // Next word starts lowercase → likely abbreviation / mid-sentence ellipsis.
        if next.isLetter && next.isLowercase { return false }
        guard chars[enderIndex] == "." else { return true }
        // Word immediately before the period.
        var k = enderIndex - 1
        while k >= 0, !chars[k].isWhitespace, !"\"'“‘(".contains(chars[k]) { k -= 1 }
        let word = String(chars[(k + 1)..<enderIndex])
        if word.isEmpty { return true }
        let lower = word.lowercased()
        // "etc. The" / "et al. They": these usually end the sentence when a capital follows
        // (titles like "Dr." are always followed by a capitalised name, so they stay joined).
        if sentenceEndingAbbreviations.contains(lower) { return true }
        if abbreviations.contains(lower) { return false }
        // Single-letter initial: "I. Ericcson", "J. R. R."
        if word.count == 1, word.first!.isUppercase { return false }
        // Dotted acronym: "U.S.A", "e.g"
        if word.contains("."), word.split(separator: ".").allSatisfy({ $0.count <= 2 }) { return false }
        return true
    }

    // MARK: - Oversized sentence splitting

    /// Clause boundaries first (`,` `;` `:` followed by space), then spaces, then hard cut.
    private static func splitOversized(_ sentence: String, hardMax: Int) -> [String] {
        let clauses = splitAfter(sentence, separators: [",", ";", ":"])
        var out: [String] = []
        var buffer = ""
        func flush() {
            if !buffer.isEmpty { out.append(buffer); buffer = "" }
        }
        for clause in clauses {
            if estimatedUnits(clause) > hardMax {
                flush()
                out.append(contentsOf: splitAtSpaces(clause, hardMax: hardMax))
                continue
            }
            let candidate = buffer.isEmpty ? clause : buffer + " " + clause
            if estimatedUnits(candidate) <= hardMax {
                buffer = candidate
            } else {
                flush()
                buffer = clause
            }
        }
        flush()
        return out
    }

    private static func splitAfter(_ text: String, separators: Set<Character>) -> [String] {
        let chars = Array(text)
        var parts: [String] = []
        var start = 0
        var i = 0
        while i < chars.count {
            if separators.contains(chars[i]), i + 1 < chars.count, chars[i + 1] == " " {
                parts.append(String(chars[start...i]))
                start = i + 2
                i += 2
                continue
            }
            i += 1
        }
        if start < chars.count { parts.append(String(chars[start...])) }
        return parts.filter { !$0.isEmpty }
    }

    private static func splitAtSpaces(_ text: String, hardMax: Int) -> [String] {
        let words = text.split(separator: " ").map(String.init)
        var out: [String] = []
        var buffer = ""
        for word in words {
            if estimatedUnits(word) > hardMax {
                if !buffer.isEmpty { out.append(buffer); buffer = "" }
                // Pathological whitespace-free run (URL etc.): hard cut.
                var rest = Substring(word)
                while !rest.isEmpty {
                    var take = 0
                    var units = 0
                    for c in rest {
                        let u = c.isNumber ? 3 : 1
                        if units + u > hardMax { break }
                        units += u
                        take += 1
                    }
                    take = max(1, take)
                    out.append(String(rest.prefix(take)))
                    rest = rest.dropFirst(take)
                }
                continue
            }
            let candidate = buffer.isEmpty ? word : buffer + " " + word
            if estimatedUnits(candidate) <= hardMax {
                buffer = candidate
            } else {
                out.append(buffer)
                buffer = word
            }
        }
        if !buffer.isEmpty { out.append(buffer) }
        return out
    }
}

private extension Character {
    var isQuoteMark: Bool { "\"'“”‘’«»".contains(self) }
}
