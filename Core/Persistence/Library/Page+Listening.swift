import Foundation

extension Page {
    /// The page's listen / audio cache key. Every page `LibraryStore` makes has one; a page
    /// synced without it would use its address's key.
    var listenKey: UUID {
        key ?? ArticleIdentity.articleKey(canonicalURL: canonicalURL ?? urlString ?? title)
    }

    /// Saved in the Library: what the reader's 🔖 and ⋯ → Save show as saved. A link (a favorite
    /// only) or a page played without saving isn't.
    var isSavedToLibrary: Bool { isSaved && isInLibrary }
}

extension SpeechSession {
    /// A library page's listening session: its stored paragraphs (older pages build and store
    /// them once), what the lock screen shows, and the address 🎧 compares against. A chapter of
    /// a book or series carries its folder (playback goes on to the next chapter), shows the
    /// book's byline, and the book's cover when it has no artwork of its own.
    @MainActor
    static func page(_ page: Page) -> SpeechSession {
        let book = page.folder.flatMap { $0.kind.isFixed ? $0 : nil }
        return SpeechSession(id: page.listenKey, document: page.listenDocument(),
                             detectedLanguage: page.detectedLanguageBackfilling(),
                             title: page.title, site: book?.byline ?? page.byline,
                             artwork: page.artworkData ?? book?.coverData,
                             canonicalURL: page.canonicalURL ?? page.urlString.map { ArticleIdentity.canonicalURLString(from: $0) },
                             sourceLabel: page.byline, folderID: book?.id, folderName: book?.displayName)
    }
}
