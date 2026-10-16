import Foundation
import SwiftData

/// What a page holds. Stored as `Page.contentStateRaw`; raw values are persisted.
/// "Audio ready" isn't a state: it depends on the voice, so `ArticleAudioCache` answers it.
enum PageContentState: String, Codable {
    /// A web address the user chose to keep (a favorite, a series chapter not fetched yet). Any
    /// text it holds is a cache, refreshed when it is played again and cleared by the prune.
    case link
    /// Text and listen blocks kept.
    case saved
}

/// Link pages: how fetching their text went. Raw values are persisted.
enum PageFetchState: String, Codable {
    case none
    case fetching
    case failed
    case locked
    case needsBrowser
}

/// A page in the library tree: a saved article, a link (favorite), a book chapter, a page you
/// played without saving (`addedAt == nil`, kept 7 days), or one you removed from the Library
/// (`removedAt`, in no list, kept 7 days as well). One page per canonical URL, app-wide,
/// enforced by `LibraryStore` and the launch dedupe pass rather than `.unique` (CloudKit can't
/// sync unique constraints).
@Model
final class Page {
    /// The audio cache / listen session key. Copied verbatim from `SavedArticle.id` at migration
    /// and never recomputed: rows saved before identity v2 have random ids, and their audio,
    /// crash resume and pending bakes are keyed by them.
    var key: UUID?
    var title: String = ""
    /// The site domain for web pages; the author for book chapters.
    var byline: String = ""
    var urlString: String?
    /// Web pages: `ArticleIdentity.canonicalURLString`. One page per canonical URL.
    var canonicalURL: String?
    /// Book chapters: "href#fragment" of the contents entry.
    var locator: String?
    var contentStateRaw: String = PageContentState.link.rawValue
    /// nil = not in the Library: played without saving, or removed (`removedAt`). Pruned 7 days
    /// after it was last played.
    var addedAt: Date?
    /// When *Remove from Library* took it out of the Library, until you listen to it again from
    /// its article (🎧, the Reader's Listen: `LibraryStore.recordPlayback`). Out of the Library
    /// with this set, it is in no list, not even *Not saved* (`LibraryQueries`); it is kept only
    /// for what plays and the bar until the prune. Playing on, pausing and resuming leave it set.
    /// Read only with `addedAt == nil`: saving it again leaves the date, which the next remove
    /// replaces.
    var removedAt: Date?
    /// Favorite is an independent flag; it does not imply a special location in the tree.
    var isFavorite: Bool = false
    /// Order inside its folder, or among pages with no folder.
    var sortKey: Double = 0
    /// `folder?.id`, kept by `LibraryStore`, so predicates never go through the optional
    /// relationship (iOS 17).
    var folderID: UUID?
    /// The favicon. Book and series pages use the folder's cover.
    @Attribute(.externalStorage) var artworkData: Data?
    /// The cleaned reading HTML, UTF-8.
    @Attribute(.externalStorage) var bodyHTML: Data?
    @Attribute(.externalStorage) var plainTextData: Data?
    var excerpt: String = ""
    /// Listen paragraphs (JSON `[String]`), same order as the reader's highlight / tap blocks.
    @Attribute(.externalStorage) var listenBlocksData: Data?
    /// `ListenHTMLBlocks.version` used for `listenBlocksData`; 0 means never built.
    var listenBlocksVersion: Int = 0
    var detectedLanguageCode: String?
    var wordCount: Int = 0
    /// The number of listen blocks; "audio ready" compares the audio cache against it.
    var paragraphCount: Int = 0
    var positionParagraph: Int = 0
    var positionUTF16: Int = 0
    var lastPlayedAt: Date?
    var finishedAt: Date?
    /// Front matter, licence pages, or the user's "Skip in Playback": never reached by carrying
    /// on from the chapter before.
    var skipsInPlayback: Bool = false
    var fetchStateRaw: String = PageFetchState.none.rawValue
    var folder: Folder?

    init(key: UUID, title: String, byline: String, urlString: String?, contentState: PageContentState,
         addedAt: Date?, sortKey: Double = 0, artworkData: Data? = nil) {
        self.key = key
        self.title = title
        self.byline = byline
        self.urlString = urlString
        self.canonicalURL = urlString.map(ArticleIdentity.canonicalURLString(from:))
        self.contentStateRaw = contentState.rawValue
        self.addedAt = addedAt
        self.sortKey = sortKey
        self.artworkData = artworkData
    }

    var contentState: PageContentState {
        get { PageContentState(rawValue: contentStateRaw) ?? .link }
        set { contentStateRaw = newValue.rawValue }
    }

    var fetchState: PageFetchState {
        get { PageFetchState(rawValue: fetchStateRaw) ?? .none }
        set { fetchStateRaw = newValue.rawValue }
    }

    var isSaved: Bool { contentState == .saved }
    var isLink: Bool { contentState == .link }
    var isInLibrary: Bool { addedAt != nil }
    var url: URL? { urlString.flatMap(URL.init(string:)) }

    var cleanedHTML: String {
        get { bodyHTML.flatMap { String(data: $0, encoding: .utf8) } ?? "" }
        set { bodyHTML = newValue.isEmpty ? nil : Data(newValue.utf8) }
    }

    var plainText: String {
        get { plainTextData.flatMap { String(data: $0, encoding: .utf8) } ?? "" }
        set { plainTextData = newValue.isEmpty ? nil : Data(newValue.utf8) }
    }

    /// Holds reading text: a saved page, or a link page carrying a text cache.
    var hasText: Bool { bodyHTML != nil || plainTextData != nil || listenBlocksData != nil }

    /// Listening time at 1× from the stored word count (`ListeningTime`'s rate).
    var estimatedMinutes: Int { ListeningTime.minutes(words: wordCount, rate: 1) }

    /// Points `folder` and `folderID` at `newFolder` together. Every move goes through here.
    func setFolder(_ newFolder: Folder?) {
        folder = newFolder
        folderID = newFolder?.id
    }
}

// MARK: - Stored listen paragraphs

extension Page {
    /// Stored paragraphs when present and built by the current parser rules; nil means rebuild.
    var cachedListenParagraphs: [String]? {
        Self.decodeListenParagraphs(listenBlocksData, version: listenBlocksVersion)
    }

    /// Stores the listen paragraphs, their count and the language detected from them.
    func storeListenParagraphs(_ paragraphs: [String]) {
        listenBlocksData = try? JSONEncoder().encode(paragraphs)
        listenBlocksVersion = ListenHTMLBlocks.version
        paragraphCount = paragraphs.count
        detectedLanguageCode = ListenLanguage.detectCached(paragraphs: paragraphs)
    }

    /// Stored detected language; a page without one detects it from its listen blocks once.
    @discardableResult
    func detectedLanguageBackfilling() -> String? {
        if let detectedLanguageCode { return detectedLanguageCode }
        guard let paragraphs = cachedListenParagraphs else { return nil }
        let code = ListenLanguage.detectCached(paragraphs: paragraphs)
        if let code { detectedLanguageCode = code }
        return code
    }

    /// Stored paragraphs if valid, otherwise built now and stored (one-time backfill).
    func listenDocument() -> ParagraphDocument {
        if let cached = cachedListenParagraphs {
            return ParagraphDocument(parts: cached)
        }
        let doc = Self.buildListenDocument(plainText: plainText, cleanedHTML: cleanedHTML, title: title)
        storeListenParagraphs(doc.paragraphs)
        return doc
    }

    /// Stored paragraphs regardless of the rules version (layout migration only).
    nonisolated static func decodeAnyListenParagraphs(_ data: Data?) -> [String]? {
        guard let data else { return nil }
        return try? JSONDecoder().decode([String].self, from: data)
    }

    nonisolated static func decodeListenParagraphs(_ data: Data?, version: Int) -> [String]? {
        guard version == ListenHTMLBlocks.version, let data else { return nil }
        return try? JSONDecoder().decode([String].self, from: data)
    }

    nonisolated static func buildListenDocument(plainText: String, cleanedHTML: String, title: String) -> ParagraphDocument {
        ParagraphDocument.forListening(plainText: plainText, cleanedHTML: cleanedHTML, matchingTitle: title)
    }
}
