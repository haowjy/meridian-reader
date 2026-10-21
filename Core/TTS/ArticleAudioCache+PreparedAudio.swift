import Foundation

/// What the Prepared Audio list asks the audio cache: which voice a page's audio is in.
extension ArticleAudioCache {
    /// The cache voice key most of the article's paragraphs were rendered in (a voice change
    /// leaves the older voice's paragraphs in place until each is rendered again); nil when it has
    /// no audio. Ties go to the index's own voice, the one it was last rendered in.
    func renderedVoice(articleID: UUID) -> String? {
        _ = contentRevision
        guard let index = index(for: articleID), !index.paragraphs.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        for entry in index.paragraphs { counts[index.voice(of: entry), default: 0] += 1 }
        let most = counts.values.max() ?? 0
        if counts[index.voiceID] == most { return index.voiceID }
        return counts.filter { $0.value == most }.keys.sorted().first
    }
}
