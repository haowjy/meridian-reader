import Foundation

/// The spoken sentence inside the spoken paragraph: UTF-16 offsets into the paragraph's text, as
/// the session counts them (`ListenHTMLBlocks` text, or a plain-text paragraph as it is).
struct ReaderSentence: Equatable {
    var paragraph: Int
    var start: Int
    var end: Int
}

extension ReaderSentence {
    /// The sentence of `paragraph` holding `utf16Offset` (an offset into the whole document, as
    /// a saved listening position stores it); the paragraph's first sentence when the offset lies
    /// outside it. Nil for a paragraph the document doesn't have. Tokenizes that one paragraph.
    init?(in document: ParagraphDocument, paragraph: Int, utf16Offset: Int) {
        guard document.paragraphs.indices.contains(paragraph) else { return nil }
        let text = document.paragraphs[paragraph]
        let within = utf16Offset - document.startUTF16Offset(forParagraph: paragraph)
        let offset = (0..<text.utf16.count).contains(within) ? within : 0
        guard let range = ReaderScrubMap(paragraphs: [text]).sentenceRange(paragraph: 0, offset: offset) else { return nil }
        self.init(paragraph: paragraph, start: range.lowerBound, end: range.upperBound)
    }
}
