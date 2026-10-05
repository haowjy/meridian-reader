import Foundation

/// The listening position and history of library pages: a page's position, `lastPlayedAt` and
/// `finishedAt`. A page the library doesn't have keeps nothing.
@MainActor
final class LibraryProgressStore: ListeningProgressStoring {
    private let library: LibraryStore

    init(library: LibraryStore) {
        self.library = library
    }

    func storePosition(pageKey: UUID, paragraph: Int, utf16Offset: Int) {
        library.recordPosition(key: pageKey, paragraph: paragraph, utf16Offset: utf16Offset)
    }

    func noteListening(pageKey: UUID) {
        library.recordPlaybackStarted(key: pageKey)
    }

    func noteFinished(pageKey: UUID) {
        library.recordFinished(key: pageKey)
    }

    func flush() {
        library.commit("scene left")
    }
}

/// Now Playing's text: a page with text from the library; otherwise the `ReaderArticle` it was
/// started with, kept in memory.
@MainActor
final class LibraryContentResolver: NowPlayingContentResolving {
    private let library: LibraryStore
    private var remembered: ReaderArticle?

    init(library: LibraryStore) {
        self.library = library
    }

    func remember(_ article: ReaderArticle) {
        remembered = article
    }

    func content(for pageKey: UUID) async -> ReaderArticle? {
        if let page = library.page(key: pageKey), page.hasText {
            return ReaderArticle(page: page)
        }
        return remembered?.id == pageKey ? remembered : nil
    }
}
