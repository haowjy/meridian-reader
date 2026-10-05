import Foundation

/// What a row's menu marks on pages and chapters: finished or not, skipped in playback or not,
/// and their downloaded audio. Marks never touch playback. A mark whose save fails is rolled back
/// and throws `LibraryStoreError.saveFailed`.
extension LibraryStore {
    /// *Mark as Finished* / *Mark as Unfinished* (rows, Edit's *Mark Finished*). A finished page
    /// starts again from its top; a book or series is finished once every chapter that plays is.
    func setFinished(_ pages: [Page], _ finished: Bool) throws {
        try edit(finished ? "mark finished" : "mark unfinished") {
            for page in pages {
                page.finishedAt = finished ? (page.finishedAt ?? now()) : nil
            }
            var books: [Folder] = []
            for page in pages {
                if let folder = page.folder, folder.kind.isFixed, !books.contains(where: { $0 === folder }) {
                    books.append(folder)
                }
            }
            books.forEach(refreshFinished)
        }
    }

    /// *Mark All Above as Finished*: every chapter before `page` in play order.
    func markAllAbove(_ page: Page) throws {
        guard let folder = page.folder, folder.kind.isFixed else { return }
        let order = playOrder(of: folder)
        guard let index = order.firstIndex(where: { $0 === page }), index > 0 else { return }
        try setFinished(Array(order[..<index]), true)
    }

    /// *Skip in Playback*: carrying on passes over the chapter (it still plays when started
    /// directly).
    func setSkipsInPlayback(_ page: Page, _ skips: Bool) throws {
        guard page.skipsInPlayback != skips else { return }
        try edit(skips ? "skip in playback" : "play in playback") {
            page.skipsInPlayback = skips
            if let folder = page.folder, folder.kind.isFixed { refreshFinished(folder) }
        }
    }

    /// *Delete Downloads* on a book or series: every chapter's audio; the chapters stay saved.
    func deleteDownloads(of folder: Folder) {
        for page in playOrder(of: folder) { deleteDownloads(page) }
    }

    /// Whether `page` has audio on disk for any voice (*Delete Downloads* is offered).
    func hasDownloads(_ page: Page) -> Bool {
        guard let key = page.key else { return false }
        return tts.hasListenAudio(for: key)
    }

    /// A book or series is finished when it has a chapter that plays and every one of them is.
    private func refreshFinished(_ folder: Folder) {
        let playable = playOrder(of: folder).filter { !$0.skipsInPlayback && !$0.isLink }
        let done = !playable.isEmpty && playable.allSatisfy { $0.finishedAt != nil }
        if done, folder.finishedAt == nil { folder.finishedAt = now() }
        if !done { folder.finishedAt = nil }
    }
}
