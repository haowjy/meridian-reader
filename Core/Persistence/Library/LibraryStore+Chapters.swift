import Foundation

/// Folders as playback goes through them: the pages `ChapterAdvance` works on, the folder's place
/// (`Folder.currentPageKey`, the page that last played) and when it is finished. Every folder
/// (a book, a series, one you made) plays in its sort, which is yours; a book's or series' starts as
/// the source's order.
extension LibraryStore {
    /// The folder's pages in play order, skipped ones included. A link page plays (after its
    /// fetch) only in a series; elsewhere it is skipped (a favorite is an address, with nothing
    /// to fetch it). A locked series chapter, or one that needs the browser, says why it can't.
    func chapterSnapshot(of folder: Folder) -> [ChapterAdvance.Chapter] {
        chapterSnapshot(of: folder, pages: playOrder(of: folder))
    }

    /// The snapshot of `pages`, the folder's pages in play order (before they are saved, for
    /// *Replace*).
    func chapterSnapshot(of folder: Folder, pages: [Page]) -> [ChapterAdvance.Chapter] {
        pages.map { page in
            ChapterAdvance.Chapter(key: page.listenKey, isLink: page.isLink,
                                   skipsInPlayback: page.skipsInPlayback || (page.isLink && folder.kind != .series),
                                   isFinished: page.finishedAt != nil,
                                   blockedReason: page.isLink ? Self.blockedReason(page.fetchState) : nil)
        }
    }

    /// The notice playback ends with at a link chapter that can't be fetched.
    static func blockedReason(_ state: PageFetchState) -> String? {
        switch state {
        case .locked: String(localized: "Next chapter is locked")
        case .needsBrowser: String(localized: "Open in browser to continue")
        case .none, .fetching, .failed: nil
        }
    }

    /// Where Continue on a folder starts (`ChapterAdvance.start`): its place at the saved
    /// spot while unfinished, else the next chapter from its start. With no place yet (nothing in
    /// it played since it was made), the first page at its own saved spot, so a page heard part
    /// way on its own resumes. A finished folder starts again at its first page and is no longer
    /// finished. nil when that page isn't saved yet.
    func continueStart(of folder: Folder) -> (page: Page, spot: ListenSpot)? {
        let next = ChapterAdvance.start(chapterSnapshot(of: folder), place: folder.currentPageKey)
        guard case .ready(let key) = next, let page = page(key: key) else { return nil }
        if folder.finishedAt != nil {
            folder.finishedAt = nil
            commit("restart book")
        }
        let atPlace = key == folder.currentPageKey || folder.currentPageKey == nil
        return (page, atPlace ? page.listenStart : .top)
    }

    /// A page in a folder started playing at `date`: the folder's place moves to it, and the
    /// folder is listened to again (dated, unfinished). Saved by the caller.
    func placeChapter(_ page: Page, at date: Date) {
        guard let folder = page.folder, let key = page.key else { return }
        folder.currentPageKey = key
        folder.lastPlayedAt = date
        folder.finishedAt = nil
    }

    /// A page in a folder played to its end at `date`: the folder is finished when no playable
    /// page comes after it. Saved by the caller.
    func noteChapterFinished(_ page: Page, at date: Date) {
        guard let folder = page.folder else { return }
        folder.lastPlayedAt = date
        if ChapterAdvance.after(page.listenKey, in: chapterSnapshot(of: folder)) == .none {
            folder.finishedAt = date
        }
    }
}
