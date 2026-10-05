import Foundation

/// Now Playing's text is the playing page's: saved, played without saving (kept 7 days) or a link
/// holding the text it was played from, so it is there after a relaunch too.
extension LibraryStore: NowPlayingContentResolving {
    func content(for pageKey: UUID) async -> ReaderArticle? {
        guard let page = page(key: pageKey), page.hasText else { return nil }
        return ReaderArticle(page: page)
    }
}

/// Books and series carry on chapter to chapter through the library (`SpeechController+Advance`).
extension LibraryStore: NextChapterProviding {
    func folder(containing pageKey: UUID) -> PlaybackFolder? {
        guard let folder = page(key: pageKey)?.folder, folder.kind.isFixed else { return nil }
        return PlaybackFolder(id: folder.id, name: folder.displayName)
    }

    func chapters(of folderID: UUID) -> [ChapterAdvance.Chapter] {
        folder(id: folderID).map(chapterSnapshot(of:)) ?? []
    }

    func load(_ pageKey: UUID) -> SpeechSession? {
        guard let page = page(key: pageKey), page.hasText else { return nil }
        return .page(page)
    }

    /// No page fetcher is connected: a link chapter can't be fetched, so playback ends there
    /// with "Couldn't get the next chapter".
    func fetch(_ pageKey: UUID) async -> Bool {
        log("no fetcher for link chapter \(Self.short(pageKey))")
        return false
    }

    func pageFinished(key: UUID) {
        guard let page = page(key: key) else { return }
        recordFinished(page)
    }
}
