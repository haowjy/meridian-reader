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

    var plainText: String { document.joinedText }

    init(id: UUID, document: ParagraphDocument, detectedLanguage: String? = nil,
         title: String? = nil, site: String? = nil, artwork: Data? = nil) {
        self.id = id
        self.document = document
        self.detectedLanguage = detectedLanguage
        self.title = title
        self.site = site
        self.artwork = artwork
    }

    /// Uses the paragraphs stored at save time; older saves build and store them once.
    static func saved(_ article: SavedArticle) -> SpeechSession {
        let document = article.listenDocument()
        return SpeechSession(id: article.id, document: document,
                             detectedLanguage: article.detectedLanguageBackfilling(),
                             title: article.title, site: article.siteDomain, artwork: article.faviconData)
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
