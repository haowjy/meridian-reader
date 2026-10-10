import Foundation

/// How far through a page or chapter is, as its row and Continue card show it: its length
/// unplayed, the fraction and time left part-way, finished, or skipped.
enum PageProgress {
    /// The row's progress. Only a part-way page reads its stored paragraphs, so long folders
    /// stay cheap to draw.
    static func of(_ page: Page) -> ListRow.Progress {
        if page.finishedAt != nil { return .finished }
        if page.skipsInPlayback { return .skipped }
        if isPartWay(page), let paragraphs = page.cachedListenParagraphs, !paragraphs.isEmpty {
            let document = ParagraphDocument(parts: paragraphs)
            let offset = utf16Offset(in: document, paragraph: page.positionParagraph, utf16Offset: page.positionUTF16)
            return .partWay(fraction: document.progress(atUTF16Offset: offset),
                            minutesLeft: ListeningTime.minutesLeft(in: document, fromUTF16Offset: offset))
        }
        return .unplayed(minutes: page.hasText ? page.estimatedMinutes : nil)
    }

    /// Fraction listened, 0…1, for a Continue card.
    static func fraction(of page: Page) -> Double {
        if page.finishedAt != nil { return 1 }
        guard let paragraphs = page.cachedListenParagraphs else { return 0 }
        return fraction(paragraphs: paragraphs, paragraph: page.positionParagraph, utf16Offset: page.positionUTF16)
    }

    /// Fraction listened, weighted by text length (the scrubber's measure). `utf16Offset` indexes
    /// the article's listen text (`ParagraphDocument.joinedText`); only paragraph lengths matter,
    /// so the scrub map skips sentence tokenizing.
    static func fraction(paragraphs: [String], paragraph: Int, utf16Offset: Int) -> Double {
        let document = ParagraphDocument(parts: paragraphs)
        guard !document.isEmpty else { return 0 }
        let p = min(max(0, paragraph), document.count - 1)
        let map = ReaderScrubMap(paragraphs: document.paragraphs, sentences: false)
        return map.fraction(paragraph: p, offset: utf16Offset - document.startUTF16Offset(forParagraph: p))
    }

    /// Started and not finished.
    static func isPartWay(_ page: Page) -> Bool {
        page.finishedAt == nil && (page.positionParagraph > 0 || page.positionUTF16 > 0)
    }

    /// The stored spot as an offset into the listen text: the offset when it lies in the stored
    /// paragraph, else that paragraph's start.
    private static func utf16Offset(in document: ParagraphDocument, paragraph: Int, utf16Offset: Int) -> Int {
        let p = min(max(0, paragraph), document.count - 1)
        let start = document.startUTF16Offset(forParagraph: p)
        return utf16Offset >= start ? utf16Offset : start
    }
}
