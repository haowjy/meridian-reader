import Foundation

/// Splits giant paragraphs (> 1,200 characters) into balanced pieces at sentence ends, for
/// display, navigation (Jump, resume, render marks) and audio alike. Applied in exactly one place
/// per source: `ListenHTMLBlocks.splitLongBlocks` for article HTML (via
/// `ParagraphDocument.readingHTML`) and `ParagraphDocument(plainText:)` for plain text, so the
/// reader view, the listen paragraph list, the render queue and the audio cache see one list.
///
/// Rules (2026-09-25, The Forgotten's 2,543-char run-on paragraph):
/// - Paragraphs ≤ `threshold` characters are never split.
/// - Cuts only at sentence ends (`TextChunker.isBoundary`: abbreviations, initials, "U.S.A.",
///   lowercase continuations, quotes/brackets after the period, "etc-. The").
/// - Piece count k = ⌈length / 900⌉ (≥ 2); cut points chosen to make pieces as even as possible
///   (DP, squared deviation from length / k), each piece ≥ `minPiece`. If that is impossible with
///   k pieces, fewer pieces are tried; if even 2 pieces can't be balanced (e.g. one sentence is
///   most of the paragraph), the paragraph stays whole.
enum ParagraphSplitter {
    static let threshold = 1_200
    static let targetMax = 900
    static let minPiece = 300

    /// UTF-8 offsets (into `text`) where pieces 2…k begin (first char of a sentence). Empty = keep whole.
    static func pieceStartUTF8Offsets(_ text: String) -> [Int] {
        let chars = Array(text)
        guard chars.count > threshold else { return [] }
        let cuts = cutCharIndices(chars)
        guard !cuts.isEmpty else { return [] }
        var utf8 = [Int](repeating: 0, count: chars.count + 1)
        for (i, c) in chars.enumerated() { utf8[i + 1] = utf8[i] + c.utf8.count }
        return cuts.map { utf8[$0] }
    }

    /// The pieces themselves (trimmed). `[text]` when the paragraph stays whole.
    static func pieces(_ text: String) -> [String] {
        let chars = Array(text)
        guard chars.count > threshold else { return [text] }
        let cuts = cutCharIndices(chars)
        guard !cuts.isEmpty else { return [text] }
        var out: [String] = []
        var start = 0
        for c in cuts + [chars.count] {
            out.append(String(chars[start..<c]).trimmingCharacters(in: .whitespacesAndNewlines))
            start = c
        }
        return out
    }

    /// Character indices where a new sentence starts (candidate cut points).
    static func sentenceStarts(_ chars: [Character]) -> [Int] {
        let enders: Set<Character> = [".", "!", "?", "…"]
        let closers: Set<Character> = ["\"", "'", "”", "’", ")", "]", "»"]
        var out: [Int] = []
        var i = 0
        while i < chars.count {
            guard enders.contains(chars[i]) else { i += 1; continue }
            var j = i
            while j + 1 < chars.count, enders.contains(chars[j + 1]) { j += 1 }
            while j + 1 < chars.count, closers.contains(chars[j + 1]) { j += 1 }
            var k = j + 1
            guard k < chars.count, chars[k].isWhitespace else { i = j + 1; continue }
            while k < chars.count, chars[k].isWhitespace { k += 1 }
            if k < chars.count, TextChunker.isBoundary(chars: chars, enderIndex: i, afterIndex: k) {
                out.append(k)
            }
            i = k
        }
        return out
    }

    private static func cutCharIndices(_ chars: [Character]) -> [Int] {
        let starts = sentenceStarts(chars)
        guard !starts.isEmpty else { return [] }
        let total = chars.count
        let k0 = max(2, Int((Double(total) / Double(targetMax)).rounded(.up)))
        for k in stride(from: min(k0, starts.count + 1), through: 2, by: -1) {
            if let cuts = balancedCuts(starts, total: total, pieces: k) { return cuts }
        }
        return []
    }

    /// DP: choose `pieces − 1` of `starts` minimising Σ (size − total/pieces)², sizes ≥ minPiece.
    private static func balancedCuts(_ starts: [Int], total: Int, pieces: Int) -> [Int]? {
        let pos = [0] + starts + [total] // node 0 = start, last = end
        let n = pos.count
        let ideal = Double(total) / Double(pieces)
        // best[j][p] = min cost to reach node j using p pieces.
        var best = [[Double]](repeating: [Double](repeating: .infinity, count: pieces + 1), count: n)
        var prev = [[Int]](repeating: [Int](repeating: -1, count: pieces + 1), count: n)
        best[0][0] = 0
        for j in 1..<n {
            for i in 0..<j {
                let size = pos[j] - pos[i]
                guard size >= minPiece else { continue }
                let d = Double(size) - ideal
                for p in 1...pieces where best[i][p - 1].isFinite {
                    let c = best[i][p - 1] + d * d
                    if c < best[j][p] { best[j][p] = c; prev[j][p] = i }
                }
            }
        }
        guard best[n - 1][pieces].isFinite else { return nil }
        var cuts: [Int] = []
        var j = n - 1, p = pieces
        while p > 0 {
            let i = prev[j][p]
            if i > 0 { cuts.append(pos[i]) }
            j = i; p -= 1
        }
        return cuts.reversed()
    }
}

/// Maps a reading position from one paragraph list to another built from the same text (e.g.
/// before / after giant paragraphs were split) by counting non-whitespace characters, so the
/// position lands in the same sentence even though separators changed (" " → "\n\n").
enum ParagraphPositionMap {
    struct Position: Equatable { var paragraph: Int; var utf16Offset: Int }

    /// `offset` is a UTF-16 offset into `old.joinedText`; if it doesn't fall inside `paragraph`
    /// (stale), the paragraph's start is used.
    static func map(paragraph: Int, utf16Offset offset: Int, from old: ParagraphDocument,
                    to new: ParagraphDocument) -> Position {
        guard !old.isEmpty, !new.isEmpty else { return Position(paragraph: 0, utf16Offset: 0) }
        let p = max(0, min(paragraph, old.count - 1))
        let range = old.utf16Ranges[p]
        let inside = offset >= range.location && offset < range.location + range.length
        let oldOffset = inside ? offset : range.location
        let target = nonWhitespaceCount(old.joinedText, upToUTF16: oldOffset)
        let newOffset = utf16Offset(new.joinedText, afterNonWhitespace: target)
        let newParagraph = new.index(containingUTF16Offset: newOffset)
        return Position(paragraph: newParagraph, utf16Offset: newOffset)
    }

    /// New index of the piece holding old paragraph `index`'s first character.
    static func mapParagraphStart(_ index: Int, from old: ParagraphDocument, to new: ParagraphDocument) -> Int {
        guard !old.isEmpty else { return 0 }
        let p = max(0, min(index, old.count - 1))
        return map(paragraph: p, utf16Offset: old.utf16Ranges[p].location, from: old, to: new).paragraph
    }

    private static func nonWhitespaceCount(_ s: String, upToUTF16 limit: Int) -> Int {
        var n = 0, u = 0
        for scalar in s.unicodeScalars {
            if u >= limit { break }
            if !CharacterSet.whitespacesAndNewlines.contains(scalar) { n += 1 }
            u += scalar.utf16.count
        }
        return n
    }

    /// UTF-16 offset of the first non-whitespace scalar after `count` non-whitespace scalars.
    private static func utf16Offset(_ s: String, afterNonWhitespace count: Int) -> Int {
        var n = 0, u = 0
        for scalar in s.unicodeScalars {
            let ws = CharacterSet.whitespacesAndNewlines.contains(scalar)
            if !ws {
                if n == count { return u }
                n += 1
            }
            u += scalar.utf16.count
        }
        return max(0, u - 1)
    }
}
