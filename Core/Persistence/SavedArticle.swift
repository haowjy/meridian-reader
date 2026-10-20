import Foundation
import SwiftData

/// A saved article as the app stored it before the library (`Folder` / `Article`). **Frozen:** the
/// library migration copies each row once into a `Article` (same key) and nothing writes these rows
/// again, so a rollback to an older build finds its saves as it left them. The model stays in
/// the "local" store until a later release removes it.
@Model
final class SavedArticle {
    /// Listen/cache identity, copied verbatim to `Article.key`. Rows saved since identity v2 use
    /// `ArticleIdentity.articleKey(canonicalURL:)`; older rows keep their random UUID.
    @Attribute(.unique) var id: UUID
    var urlString: String
    /// `ArticleIdentity.canonicalURLString`. Empty on rows saved before identity v2 and never
    /// backfilled; the migration recomputes it from `urlString`.
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
    /// Listen paragraphs (JSON `[String]`), same order as the reader's highlight / tap blocks.
    /// See `ListenHTMLBlocks`.
    @Attribute(.externalStorage) var listenBlocksData: Data?
    /// `ListenHTMLBlocks.version` used for `listenBlocksData`; 0 means never built (older saves).
    var listenBlocksVersion: Int = 0
    /// Article language detected from the listen blocks (`ListenLanguage.detect`), e.g. "en",
    /// "fr"; nil on older rows.
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
}
