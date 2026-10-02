import SwiftData
import Foundation

/// The page loaded in the browser as an article: extracted for the reader or for Save.
@MainActor
struct PageArticleService {
    let web: WebViewStore
    let extractor: any ArticleExtracting
    let context: ModelContext
    /// Recently visited pages: their icon stands in until the page's own is fetched.
    let recentVisits: [RecentVisit]

    /// The loaded page, extracted and matched to its saved row (same key on every open, so
    /// cached audio is reused), and the page's URL.
    func extract() async throws -> (article: ReaderArticle, page: URL) {
        guard let url = web.currentURL else {
            throw ExtractionError.unavailable(reason: "Open a page first.")
        }
        let html = try await web.snapshotHTML()
        let extracted = try await extractor.extract(from: ExtractionContext(url: url, pageTitle: web.pageTitle,
                                                                            htmlSnapshot: html))
        var article = ArticleLibrary.readerArticle(url: url, extracted: extracted, in: context)
        if article.faviconData == nil {
            article.faviconData = recentFavicon(for: url)
        }
        return (article, url)
    }

    /// The page's best icon: from the live document, else the host's conventional icons.
    func favicon(for url: URL) async -> Data? {
        await FaviconFetcher.best(for: url, webView: web.webView)
    }

    /// An icon already on hand for this page or its site (history).
    func recentFavicon(for url: URL) -> Data? {
        guard let host = url.host else { return nil }
        let urlString = url.absoluteString
        return recentVisits.first {
            $0.urlString == urlString || $0.host.caseInsensitiveCompare(host) == .orderedSame
        }?.faviconData
    }
}
