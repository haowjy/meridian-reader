import Foundation

/// Value snapshot rendered by the Reader sheet (`ReaderSheetScreen`) and Now Playing — the same
/// shape whether the article came from Browse (fresh extraction) or the library (a `Page`). The
/// screens never hold the `Page` model itself, so Save/Unsave can flip the bookmark without
/// tearing down the view or the playing session.
struct ReaderArticle: Equatable, Identifiable {
    /// Listen/cache key. Equals the library page's `key` (see `ArticleIdentity`).
    var id: UUID
    /// The web address, or the chapter's place in its book.
    var origin: PageOrigin
    var title: String
    /// The site ("investopedia.com"), or a chapter's author.
    var sourceLabel: String
    /// Web pages: the site's own name, from Readability.
    var siteName: String?
    var cleanedHTML: String
    var plainText: String
    var excerpt: String
    /// The favicon, or a cover thumbnail.
    var artwork: Data?
    /// Listen blocks (same order as HTML highlight/tap indices). May be empty briefly while an
    /// older page builds them off the main thread.
    var document: ParagraphDocument
    /// `cleanedHTML` with a duplicated leading `<h1>` title stripped (done once, not per render).
    var displayHTML: String
    /// Initial playhead when this article is not the live session.
    var resumeParagraph: Int = 0
    /// Paragraphs known to match any pre-v2 (unhashed) CAFs under `id` — used once to stamp them.
    var trustedParagraphs: [String]? = nil
    /// Web pages: old v1 cache keys that may hold audio for this content (adopted on open).
    var legacyCacheKeys: [UUID] = []
    /// Detected language stored on the page, if any (see `detectedLanguage`).
    var storedDetectedLanguage: String? = nil

    /// Article language for Listen (Automatic): the page's stored value, else detected from the
    /// listen blocks (memoized). nil while blocks are still building or text is too short.
    var detectedLanguage: String? {
        storedDetectedLanguage ?? (document.isEmpty ? nil : ListenLanguage.detectCached(paragraphs: document.paragraphs))
    }

    var extracted: ExtractedArticle {
        ExtractedArticle(
            title: title,
            siteName: siteName,
            cleanedHTML: cleanedHTML,
            plainText: plainText,
            excerpt: excerpt
        )
    }

    /// Fresh Browse extraction. `id` comes from `LibraryStore.readerArticle(url:extracted:)`.
    init(id: UUID, url: URL, extracted: ExtractedArticle, document: ParagraphDocument? = nil) {
        self.id = id
        self.origin = .web(url)
        self.title = extracted.title
        self.sourceLabel = url.host ?? extracted.siteName ?? url.absoluteString
        self.siteName = extracted.siteName
        self.cleanedHTML = extracted.cleanedHTML
        self.plainText = extracted.plainText
        self.excerpt = extracted.excerpt
        self.document = document ?? ParagraphDocument.forListening(
            plainText: extracted.plainText,
            cleanedHTML: extracted.cleanedHTML,
            matchingTitle: extracted.title
        )
        self.displayHTML = ParagraphDocument.readingHTML(
            extracted.cleanedHTML,
            matchingTitle: extracted.title
        )
        self.legacyCacheKeys = [ArticleIdentity.legacyEphemeralCacheKey(
            url: url,
            plainText: extracted.plainText,
            cleanedHTML: extracted.cleanedHTML
        )]
    }

    /// A library page holding text (saved, played, or a link with a text cache). Uses stored
    /// listen blocks when valid; otherwise `document` is empty and the caller builds it off-main
    /// (`Page.buildListenDocument`).
    @MainActor
    init(page: Page) {
        self.id = page.listenKey
        self.origin = page.origin
        self.title = page.title
        self.sourceLabel = page.byline
        self.siteName = nil
        let html = page.cleanedHTML
        self.cleanedHTML = html
        self.plainText = page.plainText
        self.excerpt = page.excerpt
        self.artwork = page.artworkData
        let cached = page.cachedListenParagraphs
        self.document = cached.map { ParagraphDocument(parts: $0) } ?? .empty
        self.trustedParagraphs = cached
        self.displayHTML = ParagraphDocument.readingHTML(html, matchingTitle: page.title)
        self.resumeParagraph = page.positionParagraph
        self.storedDetectedLanguage = page.detectedLanguageCode
    }
}

extension ReaderArticle {
    /// What the Reader shows: the reading HTML, or for a plain-text article its paragraphs.
    var readingHTML: String {
        displayHTML.contains(where: { !$0.isWhitespace }) ? displayHTML : document.paragraphsHTML
    }
}
