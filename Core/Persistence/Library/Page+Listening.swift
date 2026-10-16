import Foundation

extension Page {
    /// The page's listen / audio cache key. Every page `LibraryStore` makes has one; a page
    /// synced without it would use its address's key.
    var listenKey: UUID {
        key ?? ArticleIdentity.articleKey(canonicalURL: canonicalURL ?? urlString ?? title)
    }

    /// Where listening to the page starts: its saved spot, or its top once it is finished.
    var listenStart: ListenSpot {
        finishedAt == nil ? ListenSpot(paragraph: positionParagraph, utf16Offset: positionUTF16) : .top
    }

    /// Saved in the Library: what the reader's 🔖 and ⋯ → Save show as saved. A link (a favorite
    /// only) or a page played without saving isn't.
    var isSavedToLibrary: Bool { isSaved && isInLibrary }
}

extension SpeechSession {
    /// A library page's listening session: its stored paragraphs (older pages build and store
    /// them once), what the lock screen shows, and the address 🎧 compares against. A page in a
    /// folder carries its folder (playback goes on to the next page). A page in a book or series
    /// also shows the book's byline, and the book's cover when it has no artwork of its own.
    @MainActor
    static func page(_ page: Page) -> SpeechSession {
        let folder = page.folder
        let book = folder.flatMap { $0.kind.isBookOrSeries ? $0 : nil }
        return SpeechSession(id: page.listenKey, document: page.listenDocument(),
                             detectedLanguage: page.detectedLanguageBackfilling(),
                             title: page.title, site: book?.byline ?? page.byline,
                             artwork: page.artworkData ?? book?.coverData,
                             canonicalURL: page.canonicalURL ?? page.urlString.map { ArticleIdentity.canonicalURLString(from: $0) },
                             sourceLabel: page.byline, folder: folder.map(PlaybackFolder.init))
    }
}
