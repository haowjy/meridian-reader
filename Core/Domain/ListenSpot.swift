import Foundation

/// Where listening to a page starts: a paragraph and, inside it, a spot (a document UTF-16
/// offset, as a saved listening position stores it). The offset counts only while it lies in the
/// paragraph; otherwise the paragraph plays from its start.
struct ListenSpot: Equatable, Sendable {
    var paragraph: Int
    var utf16Offset: Int = 0

    /// The page's top.
    static let top = ListenSpot(paragraph: 0)

    /// Past the top: the Reader's Listen says Resume and underlines the spot's sentence.
    var isPartWay: Bool { paragraph > 0 || utf16Offset > 0 }

    /// The spot in `document`: the paragraph clamped to it, and the offset when it lies in that
    /// paragraph, else the paragraph's start.
    func resolved(in document: ParagraphDocument) -> (paragraph: Int, utf16Offset: Int) {
        guard !document.isEmpty else { return (0, 0) }
        let p = max(0, min(paragraph, document.count - 1))
        let inside = document.index(containingUTF16Offset: utf16Offset) == p
        return (p, inside ? utf16Offset : document.startUTF16Offset(forParagraph: p))
    }
}
