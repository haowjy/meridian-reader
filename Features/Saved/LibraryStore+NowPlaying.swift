import Foundation

/// Now Playing's text is the playing page's: saved, played without saving (kept 7 days) or a link
/// holding the text it was played from, so it is there after a relaunch too.
extension LibraryStore: NowPlayingContentResolving {
    func content(for pageKey: UUID) async -> ReaderArticle? {
        guard let page = page(key: pageKey), page.hasText else { return nil }
        return ReaderArticle(page: page)
    }
}
