import Foundation

/// One web page, as a source: its snapshot extracted (Readability, then the listen normalizer).
/// One page in no folder. The browser's page goes through it, and so does a page `URLPageFetcher`
/// loaded, so the two extract alike.
@MainActor
struct SingleWebPageSource: PageSource {
    let url: URL
    let context: ExtractionContext
    let extractor: any ArticleExtracting

    init(url: URL, pageTitle: String?, htmlSnapshot: String?, extractor: any ArticleExtracting) {
        self.url = url
        self.context = ExtractionContext(origin: .web(url), pageTitle: pageTitle, htmlSnapshot: htmlSnapshot)
        self.extractor = extractor
    }

    var details: FolderDetails? { nil }

    var page: PageRef {
        PageRef(key: ArticleIdentity.articleKey(url: url), locator: .web(url), ordinal: 0, title: context.pageTitle)
    }

    func knownPages() async throws -> [PageRef] { [page] }

    func page(after ref: PageRef) async throws -> PageRef? { nil }

    func content(of ref: PageRef) async throws -> PageContent {
        guard ref == page else { throw PageSourceError.unknownPage }
        let extracted = try await extractor.extract(from: context)
        return PageContent(ref: ref, title: extracted.title, siteName: extracted.siteName, bodyHTML: extracted.cleanedHTML,
                           plainText: extracted.plainText, excerpt: extracted.excerpt)
    }
}
