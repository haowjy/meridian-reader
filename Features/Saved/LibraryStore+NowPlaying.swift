import Foundation

extension LibraryStore {
    /// Now Playing's text: the playing page's. `SpeechSession` carries the paragraphs, not the
    /// reading HTML, and some starts never had a `ReaderArticle` (a Library row's ▶, crash resume),
    /// so it is looked up by key. The library has every page that has played: saved, played
    /// without saving (kept 7 days) or a link holding the text it was played from, so it is there
    /// after a relaunch too. nil when the page holds no text.
    func nowPlayingContent(for pageKey: UUID) -> ReaderArticle? {
        guard let page = page(key: pageKey), page.hasText else { return nil }
        return ReaderArticle(page: page)
    }
}

/// A page in a folder carries on through it, page to page (`SpeechController+Advance`), in the
/// folder's order.
extension LibraryStore: NextChapterProviding {
    func folder(containing pageKey: UUID) -> PlaybackFolder? {
        page(key: pageKey).flatMap(PlaybackFolder.init)
    }

    func chapters(of folderID: UUID) -> [ChapterAdvance.Chapter] {
        folder(id: folderID).map(chapterSnapshot(of:)) ?? []
    }

    func load(_ pageKey: UUID) -> SpeechSession? {
        guard let page = page(key: pageKey), page.hasText else { return nil }
        return .page(page)
    }

    func pageFinished(key: UUID, text: String?) {
        guard let page = page(key: key), holds(page, text: text) else { return }
        recordFinished(page)
    }
}

extension PlaybackFolder {
    /// The folder `page` plays on through; nil out of a folder. A chapter's is a book's.
    init?(_ page: Page) {
        guard let folder = page.folder else { return nil }
        self.init(id: folder.id, name: folder.name, isBookOrSeries: page.isChapter)
    }
}
