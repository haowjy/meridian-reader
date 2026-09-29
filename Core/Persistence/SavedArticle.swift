import Foundation
import SwiftData

@Model
final class SavedArticle {
    /// Listen/cache identity. New saves use `ArticleIdentity.articleKey(canonicalURL:)` so the
    /// Browse reader and Saved share one key; legacy rows keep their random UUID.
    @Attribute(.unique) var id: UUID
    var urlString: String
    /// `ArticleIdentity.canonicalURLString` — one saved article per canonical URL.
    /// Empty on rows saved before identity v2 until `ArticleLibrary.migrate` backfills it.
    var canonicalURL: String = ""
    var title: String
    var siteDomain: String
    var savedAt: Date
    var cleanedHTML: String
    var plainText: String
    var wordCount: Int
    var estimatedMinutes: Int
    var excerpt: String
    var playbackParagraphIndex: Int
    var playbackUTF16Offset: Int
    /// Site icon bytes (same idea as RecentVisit); nil until captured.
    @Attribute(.externalStorage) var faviconData: Data?
    /// Listen paragraphs (JSON `[String]`) built once at save so opening never re-parses HTML.
    /// Same order as the reader's highlight/tap blocks. See `ListenHTMLBlocks`.
    @Attribute(.externalStorage) var listenBlocksData: Data?
    /// `ListenHTMLBlocks.version` used for `listenBlocksData`; 0 means never built (older saves).
    var listenBlocksVersion: Int = 0
    /// Article language detected from the listen blocks (`ListenLanguage.detect`), e.g. "en",
    /// "fr". Set whenever listen blocks are stored; nil on older rows until backfilled on open
    /// (optional attribute → SwiftData lightweight migration).
    var detectedLanguageCode: String?

    init(
        id: UUID = UUID(),
        urlString: String,
        title: String,
        siteDomain: String,
        savedAt: Date = .now,
        cleanedHTML: String,
        plainText: String,
        wordCount: Int,
        estimatedMinutes: Int,
        excerpt: String,
        playbackParagraphIndex: Int = 0,
        playbackUTF16Offset: Int = 0,
        faviconData: Data? = nil
    ) {
        self.id = id
        self.urlString = urlString
        self.canonicalURL = ArticleIdentity.canonicalURLString(from: urlString)
        self.title = title
        self.siteDomain = siteDomain
        self.savedAt = savedAt
        self.cleanedHTML = cleanedHTML
        self.plainText = plainText
        self.wordCount = wordCount
        self.estimatedMinutes = estimatedMinutes
        self.excerpt = excerpt
        self.playbackParagraphIndex = playbackParagraphIndex
        self.playbackUTF16Offset = playbackUTF16Offset
        self.faviconData = faviconData
    }

    convenience init(id: UUID? = nil, url: URL, extracted: ExtractedArticle, faviconData: Data? = nil) {
        let words = extracted.plainText.split { $0.isWhitespace || $0.isNewline }.count
        let minutes = max(1, Int((Double(words) / 200.0).rounded(.up)))
        let domain = url.host ?? extracted.siteName ?? url.absoluteString
        self.init(
            id: id ?? ArticleIdentity.articleKey(url: url),
            urlString: url.absoluteString,
            title: extracted.title,
            siteDomain: domain,
            cleanedHTML: extracted.cleanedHTML,
            plainText: extracted.plainText,
            wordCount: words,
            estimatedMinutes: minutes,
            excerpt: extracted.excerpt,
            faviconData: faviconData
        )
        storeListenParagraphs(Self.buildListenDocument(
            plainText: plainText,
            cleanedHTML: cleanedHTML,
            title: title
        ).paragraphs)
    }
}

// MARK: - Stored listen paragraphs

extension SavedArticle {
    /// Stored paragraphs when present and built by the current parser rules; nil means rebuild.
    var cachedListenParagraphs: [String]? {
        Self.decodeListenParagraphs(listenBlocksData, version: listenBlocksVersion)
    }

    func storeListenParagraphs(_ paragraphs: [String]) {
        listenBlocksData = try? JSONEncoder().encode(paragraphs)
        listenBlocksVersion = ListenHTMLBlocks.version
        detectedLanguageCode = ListenLanguage.detectCached(paragraphs: paragraphs)
    }

    /// Stored detected language; older rows detect it from their listen blocks once and store it.
    @discardableResult
    func detectedLanguageBackfilling() -> String? {
        if let detectedLanguageCode { return detectedLanguageCode }
        guard let paragraphs = cachedListenParagraphs else { return nil }
        let code = ListenLanguage.detectCached(paragraphs: paragraphs)
        if let code { detectedLanguageCode = code }
        return code
    }

    /// Stored paragraphs if valid, otherwise build them now and store them (one-time backfill).
    func listenDocument() -> ParagraphDocument {
        if let cached = cachedListenParagraphs {
            return ParagraphDocument(parts: cached)
        }
        let doc = Self.buildListenDocument(plainText: plainText, cleanedHTML: cleanedHTML, title: title)
        storeListenParagraphs(doc.paragraphs)
        return doc
    }

    /// Stored paragraphs regardless of the rules version (migration only).
    nonisolated static func decodeAnyListenParagraphs(_ data: Data?) -> [String]? {
        guard let data else { return nil }
        return try? JSONDecoder().decode([String].self, from: data)
    }

    nonisolated static func decodeListenParagraphs(_ data: Data?, version: Int) -> [String]? {
        guard version == ListenHTMLBlocks.version, let data else { return nil }
        return try? JSONDecoder().decode([String].self, from: data)
    }

    nonisolated static func buildListenDocument(
        plainText: String,
        cleanedHTML: String,
        title: String
    ) -> ParagraphDocument {
        ParagraphDocument.forListening(
            plainText: plainText,
            cleanedHTML: cleanedHTML,
            matchingTitle: title
        )
    }
}

