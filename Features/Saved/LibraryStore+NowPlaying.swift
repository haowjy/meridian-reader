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
        guard let folder = page(key: pageKey)?.folder else { return nil }
        return PlaybackFolder(folder)
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
    init(_ folder: Folder) {
        self.init(id: folder.id, name: folder.name, isBookOrSeries: folder.kind.isBookOrSeries)
    }
}
