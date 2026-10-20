import Foundation

/// Folders as playback goes through them: the pages `ChapterAdvance` works on and the folder's
/// place (`Folder.currentArticleKey`, the page that last played). Every folder (a book, a followed
/// story, one you made) plays in its sort, which is yours; a book's or story's starts as the
/// source's order.
/// Whether a folder is finished isn't stored: `FolderProgress.isFinished` works it out from its
/// pages.
extension LibraryStore {
    /// The folder's pages in play order, skipped ones included. A link page in a followed story
    /// (`FolderKind.series`) is a chapter waiting for its text, which playback stops before; a link
    /// anywhere else is skipped (a favorite is an address, and nothing fetches it for playback).
    func chapterSnapshot(of folder: Folder) -> [ChapterAdvance.Chapter] {
        chapterSnapshot(articles(in: folder))
    }

    /// The snapshot of `articles`, a folder's pages in play order.
    func chapterSnapshot(_ articles: [Article]) -> [ChapterAdvance.Chapter] {
        articles.map { article in
            ChapterAdvance.Chapter(key: article.listenKey, isWaiting: article.isWaitingChapter,
                                   skipsInPlayback: article.skipsInPlayback || (article.isLink && !article.isWaitingChapter),
                                   isFinished: article.finishedAt != nil)
        }
    }

    /// Where Continue on a folder starts (`ChapterAdvance.start`): its place at the saved
    /// spot while unfinished, else the next chapter from its start. With no place yet (nothing in
    /// it played since it was made), the first page at its own saved spot, so a page heard part
    /// way on its own resumes. A finished folder starts again at its first page. The page may be a
    /// chapter still waiting for its text (`Article.isLink`); nil when nothing in it plays.
    func continueStart(of folder: Folder) -> (article: Article, spot: ListenSpot)? {
        let next = ChapterAdvance.start(chapterSnapshot(of: folder), place: folder.currentArticleKey)
        guard let key = next.key, let article = article(key: key) else { return nil }
        let atPlace = key == folder.currentArticleKey || folder.currentArticleKey == nil
        return (article, atPlace ? article.listenStart : .top)
    }

    /// A page in a folder started playing: the folder's place moves to it. Saved by the caller.
    func placeChapter(_ article: Article) {
        guard let folder = article.folder, let key = article.key else { return }
        folder.currentArticleKey = key
    }
}
