import Foundation

/// Article position ↔ scrubber fraction. Each paragraph gets width ∝ its length, so the fill tracks
/// how much of the article has been read. Scrubbing snaps to **sentence starts**: `target(at:)` is
/// the sentence under the finger, and the scrubber ticks a haptic whenever that target changes.
struct ReaderScrubMap: Equatable, Sendable {
    /// Cumulative weight before each paragraph.
    let starts: [Double]
    let total: Double
    /// Paragraph texts (bubble snippet).
    let texts: [String]
    /// Per paragraph: UTF-16 offsets of its sentence starts (always starts with 0).
    let sentenceStarts: [[Int]]

    var paragraphCount: Int { starts.count }

    /// A scrub destination: the start of sentence `sentence` of `paragraph`, `offset` UTF-16 units
    /// into the paragraph.
    struct Target: Equatable, Sendable {
        var paragraph: Int
        var sentence: Int
        var offset: Int
    }

    /// `sentences: false` skips sentence tokenization (every paragraph is one sentence): enough
    /// for position ↔ fraction, which only needs paragraph lengths.
    init(paragraphs: [String], sentences: Bool = true) {
        var starts: [Double] = []
        var acc = 0.0
        for p in paragraphs {
            starts.append(acc)
            acc += Double(max(1, p.utf16.count))
        }
        self.starts = starts
        self.total = max(acc, 1)
        self.texts = paragraphs
        self.sentenceStarts = paragraphs.map { sentences ? SentenceStarts.offsets(in: $0) : [0] }
    }

    func sentenceCount(paragraph: Int) -> Int {
        sentenceStarts.indices.contains(paragraph) ? sentenceStarts[paragraph].count : 1
    }

    /// The sentence containing `offset` (UTF-16, paragraph-relative) of `paragraph`.
    func target(paragraph: Int, offset: Int) -> Target {
        guard !starts.isEmpty else { return Target(paragraph: 0, sentence: 0, offset: 0) }
        let p = min(max(0, paragraph), starts.count - 1)
        let sentences = sentenceStarts.indices.contains(p) ? sentenceStarts[p] : [0]
        let s = sentences.lastIndex { $0 <= offset } ?? 0
        return Target(paragraph: p, sentence: s, offset: sentences[s])
    }

    /// The sentence under `fraction` (its start: releasing mid-sentence plays that sentence).
    func target(at fraction: Double) -> Target {
        guard !starts.isEmpty else { return Target(paragraph: 0, sentence: 0, offset: 0) }
        let p = paragraph(at: fraction)
        let x = min(max(0, fraction), 1) * total - starts[p]
        return target(paragraph: p, offset: Int(x.rounded(.down)))
    }

    /// Fraction of a target's sentence start.
    func fraction(of target: Target) -> Double {
        guard !starts.isEmpty else { return 0 }
        let p = min(max(0, target.paragraph), starts.count - 1)
        return (starts[p] + Double(max(0, target.offset))) / total
    }

    /// Fraction at paragraph offset `offset` (UTF-16) of `paragraph`.
    func fraction(paragraph: Int, offset: Int) -> Double {
        guard !starts.isEmpty else { return 0 }
        let p = min(max(0, paragraph), starts.count - 1)
        let len = texts.indices.contains(p) ? texts[p].utf16.count : 0
        let within = len > 0 ? Double(min(max(0, offset), len)) / Double(len) : 0
        return fraction(paragraph: p, within: min(within, 0.999))
    }

    /// First words of the target's sentence (the drag bubble).
    func snippet(for target: Target, maxLength: Int = 90) -> String {
        guard texts.indices.contains(target.paragraph) else { return "" }
        let text = texts[target.paragraph] as NSString
        let sentences = sentenceStarts[target.paragraph]
        let end = target.sentence + 1 < sentences.count ? sentences[target.sentence + 1] : text.length
        let start = min(max(0, target.offset), text.length)
        var sentence = text.substring(with: NSRange(location: start, length: max(0, min(end, text.length) - start)))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if sentence.count > maxLength {
            let cut = sentence.prefix(maxLength)
            let trimmed = cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? String(cut)
            sentence = trimmed + "…"
        }
        return sentence
    }

    /// Fraction at `paragraph` plus `within` (0…1) of it.
    func fraction(paragraph: Int, within: Double = 0) -> Double {
        guard !starts.isEmpty else { return 0 }
        let p = min(max(0, paragraph), starts.count - 1)
        let end = p + 1 < starts.count ? starts[p + 1] : total
        let w = min(max(0, within), 1)
        return (starts[p] + (end - starts[p]) * w) / total
    }

    /// Paragraph under `fraction`.
    func paragraph(at fraction: Double) -> Int {
        guard !starts.isEmpty else { return 0 }
        let x = min(max(0, fraction), 1) * total
        var lo = 0, hi = starts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if starts[mid] <= x { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    /// Scrubber stretches covered by `paragraphs` (adjacent paragraphs merge into one span).
    func spans(covering paragraphs: Set<Int>) -> [ClosedRange<Double>] {
        var result: [ClosedRange<Double>] = []
        var runStart: Int?
        for i in 0...starts.count where i < starts.count || runStart != nil {
            let inSet = i < starts.count && paragraphs.contains(i)
            if inSet, runStart == nil { runStart = i }
            if !inSet, let s = runStart {
                result.append(fraction(paragraph: s)...fraction(paragraph: i - 1, within: 1))
                runStart = nil
            }
        }
        return result
    }
}
