import Foundation

/// What a row's menu marks on pages and chapters: finished or not, skipped in playback or not,
/// and their downloaded audio. Marks never touch playback. A mark whose save fails is rolled back
/// and throws `LibraryStoreError.saveFailed`.
extension LibraryStore {
    /// *Mark as Finished* / *Mark as Unfinished* (rows, Edit's *Mark Finished*). A finished page
    /// starts again from its top; a folder shows as finished once every page in it that plays is
    /// (`FolderProgress.isFinished`).
    func setFinished(_ pages: [Page], _ finished: Bool) throws {
        try edit(finished ? "mark finished" : "mark unfinished") {
            for page in pages {
                page.finishedAt = finished ? (page.finishedAt ?? now()) : nil
            }
        }
    }

    /// *Mark All Above as Finished*: every page before `page` in its folder's play order.
    func markAllAbove(_ page: Page) throws {
        guard let folder = page.folder else { return }
        let order = pages(in: folder)
        guard let index = order.firstIndex(where: { $0 === page }), index > 0 else { return }
        try setFinished(Array(order[..<index]), true)
    }

    /// *Skip in Playback*: carrying on through its folder passes over the page (it still plays
    /// when started directly).
    func setSkipsInPlayback(_ page: Page, _ skips: Bool) throws {
        guard page.skipsInPlayback != skips else { return }
        try edit(skips ? "skip in playback" : "play in playback") { page.skipsInPlayback = skips }
    }

    /// *Delete Downloads* on a folder: the audio of every page in it; the pages stay saved.
    func deleteDownloads(of folder: Folder) {
        for page in pages(in: folder) { deleteDownloads(page) }
    }

    /// Whether `page` has audio on disk for any voice (*Delete Downloads* is offered).
    func hasDownloads(_ page: Page) -> Bool {
        guard let key = page.key else { return false }
        return tts.hasListenAudio(for: key)
    }
}
