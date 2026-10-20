import Foundation

/// One web page, as a source: its snapshot extracted (Readability, then the listen normalizer).
/// One page in no folder. The browser's page goes through it, and so does a page `URLPageFetcher`
/// loaded, so the two extract alike.
@MainActor
struct SingleWebPageSource: ArticleSource {
    let url: URL
    let context: ExtractionContext
    let extractor: any ArticleExtracting

    init(url: URL, htmlSnapshot: String?, extractor: any ArticleExtracting) {
        self.url = url
        self.context = ExtractionContext(origin: .web(url), htmlSnapshot: htmlSnapshot)
        self.extractor = extractor
    }

    var details: FolderDetails? { nil }

    var article: ArticleRef {
        ArticleRef(key: ArticleIdentity.articleKey(url: url), locator: .web(url), ordinal: 0)
    }

    func knownArticles() async throws -> [ArticleRef] { [article] }

    func content(of ref: ArticleRef) async throws -> ArticleContent {
        guard ref == article else { throw ArticleSourceError.unknownArticle }
        let extracted = try await extractor.extract(from: context)
        return ArticleContent(ref: ref, title: extracted.title, siteName: extracted.siteName, bodyHTML: extracted.cleanedHTML,
                           plainText: extracted.plainText, excerpt: extracted.excerpt)
    }
}
