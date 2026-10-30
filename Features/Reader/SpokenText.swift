import SwiftUI

/// The text of the page you hear (Listen): the spoken paragraph in full ink and its sentence
/// underlined, the text following the audio. Its own view because the sentence follows the live
/// offset, which moves several times a second: only this leaf (and the web view's bridge, which
/// sends only changes) redraws for it.
struct SpokenText: View {
    let speech: SpeechController
    let html: String
    let heading: ReaderHeading
    var finished = false
    var isChapter = false
    var scrubMap: ReaderScrubMap? = nil
    var scrubPreview: Int? = nil
    var jumpMode = false
    var scrollRequest: ReaderScrollRequest? = nil
    var follows = false
    var opensAt: ReadingHandOver? = nil
    var onUserScroll: () -> Void = {}
    var onSpotSide: (JumpDirection) -> Void = { _ in }
    let onTap: (Int) -> Void
    let onOpenLink: (URL) -> Void
    var onPlaySelection: ((Int, Int) -> Void)?

    var body: some View {
        let live = !finished && scrubPreview == nil
        let paragraph = speech.currentParagraphIndex
        HTMLReadingView(
            html: html,
            heading: heading,
            activeParagraphIndex: speech.spokenParagraph(scrubPreview: scrubPreview),
            sentence: live ? sentence(paragraph) : nil,
            spokenWord: live ? spokenWord(paragraph) : nil,
            jumpMode: jumpMode,
            scrollRequest: scrollRequest,
            follows: follows && !finished,
            opensAt: opensAt,
            onUserScroll: onUserScroll,
            onSpotSide: onSpotSide,
            onOpenLink: onOpenLink,
            pageTimeLeft: { [document = speech.document, rate = speech.rateMultiplier, isChapter] in
                ListeningTime.leftLabel(in: document, paragraph: $0, offset: $1, rate: rate, chapter: isChapter)
            },
            onPlaySelection: onPlaySelection,
            onTapParagraph: onTap
        )
    }

    /// The word being spoken: its paragraph and the UTF-16 offset in it.
    private func spokenWord(_ paragraph: Int) -> ReadingPages.Spot? {
        let document = speech.document
        guard document.paragraphs.indices.contains(paragraph) else { return nil }
        return ReadingPages.Spot(paragraph: paragraph,
                                 offset: speech.spokenUTF16Offset - document.startUTF16Offset(forParagraph: paragraph))
    }

    private func sentence(_ paragraph: Int) -> ReaderSentence? {
        let document = speech.document
        guard let scrubMap, document.paragraphs.indices.contains(paragraph) else { return nil }
        let within = speech.spokenUTF16Offset - document.startUTF16Offset(forParagraph: paragraph)
        guard let range = scrubMap.sentenceRange(paragraph: paragraph, offset: within) else { return nil }
        return ReaderSentence(paragraph: paragraph, start: range.lowerBound, end: range.upperBound)
    }
}
