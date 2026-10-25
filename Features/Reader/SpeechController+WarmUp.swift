import Foundation

extension SpeechController {
    /// A reading view of `article` (the Reader sheet, the Browser's in-place reader) has opened:
    /// align its audio identity and put its first chunk first in the render queue, so Listen
    /// starts quickly. Never touches live playback (the reading views never show what plays).
    func warmUp(_ article: ReaderArticle, from start: ListenSpot, saved: Bool) {
        guard !article.document.isEmpty else { return }
        let paragraphs = article.document.paragraphs
        ListenTimingLog.log("reader_open", [
            "key": ListenTimingLog.shortKey(article.id),
            "paragraphs": paragraphs.count,
            "chars": paragraphs.reduce(0) { $0 + $1.count },
            "resume_p": start.paragraph,
            "local_ready": localTTS.usesLocalEngine,
            "saved": saved,
        ])
        localTTS.prepareListenIdentity(key: article.id, paragraphs: paragraphs,
                                       trustedParagraphs: article.trustedParagraphs,
                                       legacyKeys: article.legacyCacheKeys, isLivePlayback: false)
        localTTS.openArticle(cacheKey: article.id, paragraphs: paragraphs, from: start.paragraph, isEphemeral: !saved)
    }
}
