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
    /// Lock screen / Control Center (Now Playing): article title, site and favicon.
    var title: String?
    var site: String?
    var artwork: Data?
    /// The page's canonical URL (web pages): what 🎧 on that page compares against.
    var canonicalURL: String?
    /// The page's host ("investopedia.com"): the Now Playing bar's source line.
    var host: String?
    /// The book or series this page is a chapter of: playback carries on through its chapters
    /// (`ChapterAdvance`). nil for any other page, which plays to its end and stops.
    var folderID: UUID?
    /// The book's or series' name: the lock screen's album, the bar's source.
    var folderName: String?

    var plainText: String { document.joinedText }

    init(id: UUID, document: ParagraphDocument, detectedLanguage: String? = nil,
         title: String? = nil, site: String? = nil, artwork: Data? = nil,
         canonicalURL: String? = nil, host: String? = nil, folderID: UUID? = nil, folderName: String? = nil) {
        self.id = id
        self.document = document
        self.detectedLanguage = detectedLanguage
        self.title = title
        self.site = site
        self.artwork = artwork
        self.canonicalURL = canonicalURL
        self.host = host
        self.folderID = folderID
        self.folderName = folderName
    }

    /// A page shown in the Reader or extracted for 🎧.
    init(article: ReaderArticle) {
        self.init(id: article.id, document: article.document, detectedLanguage: article.detectedLanguage,
                  title: article.title, site: article.siteName ?? article.siteDomain, artwork: article.faviconData,
                  canonicalURL: article.canonicalURL, host: article.siteDomain)
    }

    static func reader(
        id: UUID,
        plainText: String,
        cleanedHTML: String? = nil,
        matchingTitle: String? = nil
    ) -> SpeechSession {
        let doc = ParagraphDocument.forListening(
            plainText: plainText,
            cleanedHTML: cleanedHTML,
            matchingTitle: matchingTitle
        )
        return SpeechSession(id: id, document: doc,
                             detectedLanguage: ListenLanguage.detectCached(paragraphs: doc.paragraphs))
    }
}
