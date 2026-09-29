import Foundation
import NaturalLanguage

/// Positions inside a paragraph (Nav I: sub-paragraph seek). Offsets are UTF-16 offsets into the
/// paragraph's own text (what `ParagraphDocument` and the reader use).
enum SentenceStarts {
    /// Start offset of every sentence in `text` (always begins with 0 for non-empty text).
    static func offsets(in text: String) -> [Int] {
        guard !text.isEmpty else { return [0] }
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var starts: [Int] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            // Skip leading whitespace so a start lands on the sentence's first character.
            var lower = range.lowerBound
            while lower < range.upperBound, text[lower].isWhitespace { lower = text.index(after: lower) }
            starts.append(text.utf16.distance(from: text.startIndex, to: lower))
            return true
        }
        if starts.first != 0 { starts.insert(0, at: 0) }
        var seen = Set<Int>()
        return starts.filter { seen.insert($0).inserted }.sorted()
    }
}

/// Where each synth chunk (`TextChunker`, normalized text) begins in the paragraph's original text.
/// Chunking only rewrites whitespace and punctuation, so chunk boundaries are found by counting
/// letters and digits: chunk *i* starts at the paragraph's (sum of alphanumerics in chunks
/// 0..<i)-th alphanumeric character.
enum ChunkOffsets {
    static func starts(paragraph: String, chunks: [String]) -> [Int] {
        guard chunks.count > 1 else { return [0] }
        // UTF-16 offset of every alphanumeric character of the paragraph, in order.
        var alnumOffsets: [Int] = []
        var utf16 = 0
        for scalar in paragraph.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) { alnumOffsets.append(utf16) }
            utf16 += scalar.utf16.count
        }
        var result: [Int] = [0]
        var alnumBefore = 0
        for chunk in chunks.dropLast() {
            alnumBefore += chunk.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.count
            let offset = alnumOffsets.indices.contains(alnumBefore)
                ? alnumOffsets[alnumBefore]
                : (paragraph.utf16.count * result.count / chunks.count) // mismatch: proportional guess
            result.append(max(result.last ?? 0, offset))
        }
        return result
    }

    /// Chunk containing `offset` and how far into it (0…1, by characters).
    static func locate(offset: Int, starts: [Int], length: Int) -> (chunk: Int, fraction: Double) {
        guard !starts.isEmpty else { return (0, 0) }
        let k = max(0, (starts.lastIndex { $0 <= offset }) ?? 0)
        let end = k + 1 < starts.count ? starts[k + 1] : length
        let span = max(1, end - starts[k])
        return (k, min(1, max(0, Double(offset - starts[k]) / Double(span))))
    }

    /// Paragraph offset at `fraction` of chunk `chunk` (inverse of `locate`).
    static func offset(chunk: Int, fraction: Double, starts: [Int], length: Int) -> Int {
        guard !starts.isEmpty else { return Int(Double(length) * min(1, max(0, fraction))) }
        let k = min(max(0, chunk), starts.count - 1)
        let end = k + 1 < starts.count ? starts[k + 1] : length
        return starts[k] + Int((Double(end - starts[k]) * min(1, max(0, fraction))).rounded(.down))
    }

    /// Chunk + fraction for `time` seconds into a whole-paragraph file whose chunks last
    /// `durations` (nil / mismatched: the whole file is one proportional span).
    static func locate(time: Double, fileDuration: Double, durations: [Double]?, chunkCount: Int)
        -> (chunk: Int, fraction: Double) {
        if let durations, durations.count == chunkCount, chunkCount > 1 {
            var t0 = 0.0
            for (k, d) in durations.enumerated() {
                if time < t0 + d || k == durations.count - 1 {
                    return (k, d > 0 ? min(1, max(0, (time - t0) / d)) : 0)
                }
                t0 += d
            }
        }
        return (-1, fileDuration > 0 ? min(1, max(0, time / fileDuration)) : 0)
    }
}
