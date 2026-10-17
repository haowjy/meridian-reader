import Foundation

/// Folders as playback goes through them: the pages `ChapterAdvance` works on and the folder's
/// place (`Folder.currentPageKey`, the page that last played). Every folder (a book, a followed
/// story, one you made) plays in its sort, which is yours; a book's or story's starts as the
/// source's order.
/// Whether a folder is finished isn't stored: `FolderProgress.isFinished` works it out from its
/// pages.
extension LibraryStore {
    /// The folder's pages in play order, skipped ones included. A link page in a followed story
    /// (`FolderKind.series`) is a chapter waiting for its text, which playback stops before; a link
    /// anywhere else is skipped (a favorite is an address, and nothing fetches it for playback).
    func chapterSnapshot(of folder: Folder) -> [ChapterAdvance.Chapter] {
        chapterSnapshot(pages(in: folder))
    }

    /// The snapshot of `pages`, a folder's pages in play order.
    func chapterSnapshot(_ pages: [Page]) -> [ChapterAdvance.Chapter] {
        pages.map { page in
            ChapterAdvance.Chapter(key: page.listenKey, isWaiting: page.isWaitingChapter,
                                   skipsInPlayback: page.skipsInPlayback || (page.isLink && !page.isWaitingChapter),
                                   isFinished: page.finishedAt != nil)
        }
    }

    /// Where Continue on a folder starts (`ChapterAdvance.start`): its place at the saved
    /// spot while unfinished, else the next chapter from its start. With no place yet (nothing in
    /// it played since it was made), the first page at its own saved spot, so a page heard part
    /// way on its own resumes. A finished folder starts again at its first page. The page may be a
    /// chapter still waiting for its text (`Page.isLink`); nil when nothing in it plays.
    func continueStart(of folder: Folder) -> (page: Page, spot: ListenSpot)? {
        let next = ChapterAdvance.start(chapterSnapshot(of: folder), place: folder.currentPageKey)
        guard let key = next.key, let page = page(key: key) else { return nil }
        let atPlace = key == folder.currentPageKey || folder.currentPageKey == nil
        return (page, atPlace ? page.listenStart : .top)
    }

    /// A page in a folder started playing: the folder's place moves to it. Saved by the caller.
    func placeChapter(_ page: Page) {
        guard let folder = page.folder, let key = page.key else { return }
        folder.currentPageKey = key
    }
}
