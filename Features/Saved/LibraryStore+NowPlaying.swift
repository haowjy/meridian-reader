import Foundation

extension LibraryStore {
    /// Now Playing's text: the playing page's. `SpeechSession` carries the paragraphs, not the
    /// reading HTML, and some starts never had a `ReaderArticle` (a Library row's ▶, crash resume),
    /// so it is looked up by key. The library has every page that has played: saved, played
    /// without saving (kept 7 days) or a link holding the text it was played from, so it is there
    /// after a relaunch too. nil when the page holds no text.
    func nowPlayingContent(for articleKey: UUID) -> ReaderArticle? {
        guard let article = article(key: articleKey), article.hasText else { return nil }
        return ReaderArticle(article: article)
    }
}

/// A page in a folder carries on through it, page to page (`SpeechController+Advance`), in the
/// folder's order.
extension LibraryStore: NextChapterProviding {
    func folder(containing articleKey: UUID) -> PlaybackFolder? {
        article(key: articleKey).flatMap(PlaybackFolder.init)
    }

    func chapters(of folderID: UUID) -> [ChapterAdvance.Chapter] {
        folder(id: folderID).map(chapterSnapshot(of:)) ?? []
    }

    func load(_ articleKey: UUID) -> SpeechSession? {
        guard let article = article(key: articleKey), article.hasText else { return nil }
        return .article(article)
    }

    func articleFinished(key: UUID, text: String?) {
        guard let article = article(key: key), holds(article, text: text) else { return }
        recordFinished(article)
    }
}

extension PlaybackFolder {
    /// The folder `article` plays on through; nil out of a folder. A chapter's is a book's.
    init?(_ article: Article) {
        guard let folder = article.folder else { return nil }
        self.init(id: folder.id, name: folder.name, isBookOrSeries: article.isChapter)
    }
}
