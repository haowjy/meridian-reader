import Foundation
import NaturalLanguage

/// Positions inside a paragraph (sentence-level seek). Offsets are UTF-16 offsets into the
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
