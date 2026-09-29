import Foundation

/// Value snapshot rendered by `ArticleReaderScreen` — the same shape whether the article came
/// from Browse (fresh extraction) or Saved (SwiftData row). The screen never holds the
/// `SavedArticle` model itself, so Save/Unsave can flip the bookmark without tearing down the
/// view or the playing session.
struct ReaderArticle: Equatable, Identifiable {
    /// Listen/cache key. Equals `SavedArticle.id` once saved (see `ArticleIdentity`).
    var id: UUID
    var urlString: String
    var canonicalURL: String
    var title: String
    var siteDomain: String
    var siteName: String?
    var cleanedHTML: String
    var plainText: String
    var excerpt: String
    var faviconData: Data?
    /// Listen blocks (same order as HTML highlight/tap indices). May be empty briefly while an
    /// older saved row builds them off the main thread.
    var document: ParagraphDocument
    /// `cleanedHTML` with a duplicated leading `<h1>` title stripped (done once, not per render).
    var displayHTML: String
    /// Initial playhead when this article is not the live session.
    var resumeParagraph: Int = 0
    /// Paragraphs known to match any pre-v2 (unhashed) CAFs under `id` — used once to stamp them.
    var trustedParagraphs: [String]? = nil
    /// Old v1 cache keys that may hold audio for this content (adopted on open).
    var legacyCacheKeys: [UUID] = []
    /// Detected language stored on the saved row, if any (see `detectedLanguage`).
    var storedDetectedLanguage: String? = nil

    /// Article language for Listen (Automatic): the saved row's value, else detected from the
    /// listen blocks (memoized). nil while blocks are still building or text is too short.
    var detectedLanguage: String? {
        storedDetectedLanguage ?? (document.isEmpty ? nil : ListenLanguage.detectCached(paragraphs: document.paragraphs))
    }

    var url: URL? { URL(string: urlString) }

    var extracted: ExtractedArticle {
        ExtractedArticle(
            title: title,
            siteName: siteName,
            cleanedHTML: cleanedHTML,
            plainText: plainText,
            excerpt: excerpt
        )
    }

    /// Fresh Browse extraction. `id` should come from `ArticleLibrary.resolveKey`.
    init(id: UUID, url: URL, extracted: ExtractedArticle, document: ParagraphDocument? = nil) {
        self.id = id
        self.urlString = url.absoluteString
        self.canonicalURL = ArticleIdentity.canonicalURLString(from: url)
        self.title = extracted.title
        self.siteDomain = url.host ?? extracted.siteName ?? url.absoluteString
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

    /// Saved row. Uses stored listen blocks when valid; otherwise `document` is empty and the
    /// caller builds it off-main (`SavedArticle.buildListenDocument`).
    @MainActor
    init(saved: SavedArticle) {
        self.id = saved.id
        self.urlString = saved.urlString
        self.canonicalURL = saved.canonicalURL.isEmpty
            ? ArticleIdentity.canonicalURLString(from: saved.urlString)
            : saved.canonicalURL
        self.title = saved.title
        self.siteDomain = saved.siteDomain
        self.siteName = nil
        self.cleanedHTML = saved.cleanedHTML
        self.plainText = saved.plainText
        self.excerpt = saved.excerpt
        self.faviconData = saved.faviconData
        let cached = saved.cachedListenParagraphs
        self.document = cached.map { ParagraphDocument(parts: $0) } ?? .empty
        self.trustedParagraphs = cached
        self.displayHTML = ParagraphDocument.readingHTML(
            saved.cleanedHTML,
            matchingTitle: saved.title
        )
        self.resumeParagraph = saved.playbackParagraphIndex
        self.storedDetectedLanguage = saved.detectedLanguageCode
    }
}
