import SwiftUI

/// The text of a page that may be what you hear: when it is (`spoken`), the spoken paragraph in
/// full ink and its sentence underlined, the text following the audio; when it is not, the page
/// alone, with `savedSentence` (the saved listening spot) underlined. Its own view because the
/// sentence follows the live offset, which moves several times a second: only this leaf (and the
/// web view's bridge, which sends only changes) redraws for it, and only while `spoken`.
struct SpokenText: View {
    let speech: SpeechController
    let html: String
    let heading: ReaderHeading
    /// The page is what you hear: its text shows the playhead.
    let spoken: Bool
    /// The page's listen text: the playing session's when `spoken`, else the article's.
    let document: ParagraphDocument
    var finished = false
    var isChapter = false
    var scrubMap: ReaderScrubMap? = nil
    var scrubPreview: Int? = nil
    var savedSentence: ReaderSentence? = nil
    var jumpMode = false
    var scrollRequest: ReaderScrollRequest? = nil
    var follows = false
    var opensAtSentence = false
    var opensAt: ReadingHandOver? = nil
    var scrollHandle: ReadingScrollHandle? = nil
    var onUserScroll: () -> Void = {}
    var onSpotSide: (JumpDirection) -> Void = { _ in }
    let onTap: (Int) -> Void
    let onOpenLink: (URL) -> Void
    var onPlaySelection: ((Int, Int) -> Void)?

    var body: some View {
        let live = spoken && !finished && scrubPreview == nil
        let paragraph = spoken ? speech.currentParagraphIndex : 0
        HTMLReadingView(
            html: html,
            heading: heading,
            activeParagraphIndex: spoken ? speech.spokenParagraph(scrubPreview: scrubPreview) : nil,
            sentence: spoken ? (live ? sentence(paragraph) : nil) : savedSentence,
            spokenWord: live ? spokenWord(paragraph) : nil,
            jumpMode: jumpMode,
            scrollRequest: scrollRequest,
            follows: spoken && follows && !finished,
            opensAtSentence: opensAtSentence,
            opensAt: opensAt,
            scrollHandle: scrollHandle,
            onUserScroll: onUserScroll,
            onSpotSide: onSpotSide,
            onOpenLink: onOpenLink,
            pageTimeLeft: { [document, rate = speech.rateMultiplier, isChapter] in
                ListeningTime.leftLabel(in: document, paragraph: $0, offset: $1, rate: rate, chapter: isChapter)
            },
            onPlaySelection: onPlaySelection,
            onTapParagraph: onTap
        )
    }

    /// The word being spoken: its paragraph and the UTF-16 offset in it.
    private func spokenWord(_ paragraph: Int) -> ReadingPages.Spot? {
        guard document.paragraphs.indices.contains(paragraph) else { return nil }
        return ReadingPages.Spot(paragraph: paragraph,
                                 offset: speech.spokenUTF16Offset - document.startUTF16Offset(forParagraph: paragraph))
    }

    private func sentence(_ paragraph: Int) -> ReaderSentence? {
        guard let scrubMap, document.paragraphs.indices.contains(paragraph) else { return nil }
        let within = speech.spokenUTF16Offset - document.startUTF16Offset(forParagraph: paragraph)
        guard let range = scrubMap.sentenceRange(paragraph: paragraph, offset: within) else { return nil }
        return ReaderSentence(paragraph: paragraph, start: range.lowerBound, end: range.upperBound)
    }
}
