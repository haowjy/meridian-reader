import Foundation

/// What a row's menu marks on pages and chapters: finished or not, skipped in playback or not,
/// and their prepared audio. Marks never touch playback. A mark whose save fails is rolled back
/// and throws `LibraryStoreError.saveFailed`.
extension LibraryStore {
    /// *Mark as Finished* / *Mark as Unfinished* (rows, Edit's *Mark Finished*). A finished page
    /// starts again from its top; a folder shows as finished once every page in it that plays is
    /// (`FolderProgress.isFinished`).
    func setFinished(_ articles: [Article], _ finished: Bool) throws {
        try edit(finished ? "mark finished" : "mark unfinished") {
            for article in articles {
                article.finishedAt = finished ? (article.finishedAt ?? now()) : nil
            }
        }
    }

    /// *Mark All Above as Finished*: every page before `article` in its folder's play order.
    func markAllAbove(_ article: Article) throws {
        guard let folder = article.folder else { return }
        let order = articles(in: folder)
        guard let index = order.firstIndex(where: { $0 === article }), index > 0 else { return }
        try setFinished(Array(order[..<index]), true)
    }

    /// *Skip in Playback*: carrying on through its folder passes over the page (it still plays
    /// when started directly).
    func setSkipsInPlayback(_ article: Article, _ skips: Bool) throws {
        guard article.skipsInPlayback != skips else { return }
        try edit(skips ? "skip in playback" : "play in playback") { article.skipsInPlayback = skips }
    }

    /// Whether `article` has audio on disk for any voice (*Remove Prepared audio* is offered).
    func hasPreparedAudio(_ article: Article) -> Bool {
        guard let key = article.key else { return false }
        return audio.audioCache.hasCache(for: key)
    }
}
