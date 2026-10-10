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
    /// them once), what the lock screen shows, and the address 🎧 compares against.
    @MainActor
    static func page(_ page: Page) -> SpeechSession {
        SpeechSession(id: page.listenKey, document: page.listenDocument(),
                      detectedLanguage: page.detectedLanguageBackfilling(),
                      title: page.title, site: page.byline, artwork: page.artworkData,
                      canonicalURL: page.canonicalURL ?? page.urlString.map { ArticleIdentity.canonicalURLString(from: $0) },
                      host: page.byline)
    }
}
