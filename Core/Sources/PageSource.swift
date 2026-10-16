import Foundation

/// Where pages come from: the web page the browser shows (`SingleWebPageSource`), an imported book
/// (`EPUBSource`), later a web serial. Every source hands out the same thing, normalized page
/// content whose listen blocks are its reading blocks, so the reader, the render queue and the
/// audio cache treat every page alike. A source never decides playback.
@MainActor
protocol PageSource {
    /// The folder a source fills (a book's title, author, cover, key); nil for a single web page,
    /// which makes one page in no folder.
    var details: FolderDetails? { get }
    /// The pages known now: a book's chapters, all of them; a single web page, one.
    func knownPages() async throws -> [PageRef]
    /// The page after `ref`; nil when the source has ended.
    func page(after ref: PageRef) async throws -> PageRef?
    /// The page's text, normalized.
    func content(of ref: PageRef) async throws -> PageContent
}

/// One page of a source, before its content is fetched.
struct PageRef: Hashable, Sendable {
    enum Locator: Hashable, Sendable {
        /// A web page, by its address as visited.
        case web(URL)
        /// A book chapter, by its place in the book.
        case book(EPUBLocator)
    }

    /// The listen and audio cache key: `ArticleIdentity.articleKey` of the canonical address (the
    /// library keeps an older page's own key for its address), or `BookIdentity.chapterKey`.
    var key: UUID
    var locator: Locator
    /// Place in the source's order, from 0.
    var ordinal: Int
    var title: String?
    /// Front or back matter: kept, but never reached by carrying on from the page before.
    var skipsInPlayback: Bool = false
}

/// A page's text, normalized: the reading HTML is the listening HTML.
struct PageContent: Sendable {
    var ref: PageRef
    var title: String
    /// Web pages: the site's own name.
    var siteName: String?
    /// Normalized HTML (`ListenContentNormalizer`).
    var bodyHTML: String
    var plainText: String
    var excerpt: String
    /// The listen blocks, built from `bodyHTML` as `ReaderArticle` builds them.
    var document: ParagraphDocument
    /// Book chapters: the book's language. Web pages: nil (detected from the listen blocks).
    var languageCode: String?

    init(ref: PageRef, title: String, siteName: String? = nil, bodyHTML: String, plainText: String,
         excerpt: String, languageCode: String? = nil) {
        self.ref = ref
        self.title = title
        self.siteName = siteName
        self.bodyHTML = bodyHTML
        self.plainText = plainText
        self.excerpt = excerpt
        self.document = ParagraphDocument.forListening(plainText: plainText, cleanedHTML: bodyHTML, matchingTitle: title)
        self.languageCode = languageCode
    }

    var extracted: ExtractedArticle {
        ExtractedArticle(title: title, siteName: siteName, cleanedHTML: bodyHTML, plainText: plainText, excerpt: excerpt)
    }
}

/// What a source hands the library to make its folder.
struct FolderDetails: Equatable, Sendable {
    var kind: FolderKind
    var title: String
    /// The author.
    var byline: String?
    /// A thumbnail of the cover.
    var cover: Data?
    /// Series: the contents page, or the first chapter.
    var sourceURL: URL?
    /// One folder per identifier: a book's key, a series' canonical contents URL.
    var sourceIdentifier: String
    /// Per kind (`Folder.sourceStateData`): a book's file fingerprint.
    var sourceState: Data?
}

/// Why a source couldn't give a page.
enum PageSourceError: Error, Equatable {
    /// Not one of this source's pages.
    case unknownPage
}
