import Foundation

/// One article loaded for listening: its id (the listen / cache key), its paragraphs and what the
/// lock screen shows.
struct SpeechSession: Equatable, Sendable, Identifiable {
    let id: UUID
    /// Built once at session creation — speech and reading surfaces must not re-split.
    let document: ParagraphDocument
    /// Article language detected from the listen blocks (`ListenLanguage`), nil if unknown.
    /// Used when Settings → Language is Automatic.
    let detectedLanguage: String?
    /// Lock screen / Control Center (Now Playing): the title (nil: the page has none), the site's
    /// name or the book's author, and the favicon or cover.
    var title: String?
    var site: String?
    var artwork: Data?
    /// The page's canonical URL (web pages): what 🎧 on that page compares against.
    var canonicalURL: String?
    /// The site ("investopedia.com") or the author: the Now Playing bar's source line.
    var sourceLabel: String?
    /// The folder this page is in: playback carries on through its pages (`ChapterAdvance`), and
    /// it is what the page plays from. nil for a page in no folder, which plays to its end and
    /// stops.
    var folder: PlaybackFolder?

    var folderID: UUID? { folder?.id }
    var plainText: String { document.joinedText }

    init(id: UUID, document: ParagraphDocument, detectedLanguage: String? = nil,
         title: String? = nil, site: String? = nil, artwork: Data? = nil,
         canonicalURL: String? = nil, sourceLabel: String? = nil, folder: PlaybackFolder? = nil) {
        self.id = id
        self.document = document
        self.detectedLanguage = detectedLanguage
        self.title = title
        self.site = site
        self.artwork = artwork
        self.canonicalURL = canonicalURL
        self.sourceLabel = sourceLabel
        self.folder = folder
    }

    /// A page shown in the Reader or extracted for 🎧.
    init(article: ReaderArticle) {
        self.init(id: article.id, document: article.document, detectedLanguage: article.detectedLanguage,
                  title: article.title, site: article.siteName ?? article.sourceLabel, artwork: article.artwork,
                  canonicalURL: article.origin.canonicalURL, sourceLabel: article.sourceLabel)
    }

}

extension SpeechSession {
    /// A library page's listening session: its stored paragraphs (older pages build and store
    /// them once), what the lock screen shows, and the address 🎧 compares against. A page in a
    /// folder carries its folder (playback goes on to the next page). A page in a book or series
    /// also shows the book's byline, and the book's cover when it has no artwork of its own.
    @MainActor
    static func page(_ page: Page) -> SpeechSession {
        let book = page.isChapter ? page.folder : nil
        return SpeechSession(id: page.listenKey, document: page.listenDocument(),
                             detectedLanguage: page.detectedLanguageBackfilling(),
                             title: page.givenTitle, site: book?.byline ?? page.byline,
                             artwork: page.artworkData ?? book?.coverData,
                             canonicalURL: page.origin.canonicalURL,
                             sourceLabel: page.byline, folder: PlaybackFolder(page))
    }
}
