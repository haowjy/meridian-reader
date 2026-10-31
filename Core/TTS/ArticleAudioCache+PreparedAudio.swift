import Foundation

/// What the Prepared Audio list asks the audio cache: which voice a page's audio is in.
extension ArticleAudioCache {
    /// The cache voice key the article's audio is in (one voice per live directory); nil when it
    /// has no audio.
    func renderedVoice(articleID: UUID) -> String? {
        _ = contentRevision
        return audioVoice(of: articleID)?.voiceID
    }
}
