import SwiftData
import Foundation

/// What the browser does with the page it has loaded: show it in the reader, save it, bookmark
/// it, record it in History. Extraction resolves the article's identity against the library, so
/// the same page gets the same key (and its cached audio) every time.
@MainActor
struct PageArticleService {
    let shell: ShellState
    let extractor: any ArticleExtracting
    let context: ModelContext
    let speech: SpeechController
    /// Recently visited pages: their icon stands in until the page's own is fetched.
    let recentVisits: [RecentVisit]

    private var web: WebViewStore { shell.web }

    /// Address-bar reader icon / ⋯ → Reader: the page in the reader overlay. The reader icon spins
    /// meanwhile.
    func openInReader() async throws {
        shell.busy = .reader
        defer { shell.busy = nil }
        let (article, url) = try await extract()
        shell.showReader(article)
        if article.faviconData == nil {
            let icon = await favicon(for: url)
            shell.updateReader(id: article.id) { if $0.faviconData == nil { $0.faviconData = icon } }
        }
    }

    /// ⋯ → Save article. ⋯ spins meanwhile.
    func save() async throws {
        shell.busy = .save
        defer { shell.busy = nil }
        var (article, url) = try await extract()
        if article.faviconData == nil {
            article.faviconData = await favicon(for: url)
        }
        ArticleSaveCoordinator(context: context, speech: speech).save(article)
    }

    /// ⋯ → Bookmark / Remove Bookmark (URL, title, icon only; independent of Save).
    func toggleBookmark(in store: BookmarkStore) async {
        guard let url = web.currentURL, BookmarkStore.isBookmarkable(url) else { return }
        let liveTitle = web.webView?.title.flatMap { $0.isEmpty ? nil : $0 }
        await store.toggle(url: url, title: liveTitle ?? web.pageTitle, faviconData: recentFavicon(for: url)) {
            await favicon(for: url)
        }
    }

    /// The page finished loading: add it to History with its icon.
    func recordVisit() async {
        guard let url = web.currentURL, url.isWeb else { return }
        let icon = await favicon(for: url)
        RecentVisitRecorder.record(url: url, title: web.pageTitle, faviconData: icon, in: context)
    }

    // MARK: - Pieces

    private func extract() async throws -> (article: ReaderArticle, page: URL) {
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
    private func favicon(for url: URL) async -> Data? {
        await FaviconFetcher.best(for: url, webView: web.webView)
    }

    /// An icon already on hand for this page or its site (History).
    private func recentFavicon(for url: URL) -> Data? {
        guard let host = url.host else { return nil }
        let urlString = url.absoluteString
        return recentVisits.first {
            $0.urlString == urlString || $0.host.caseInsensitiveCompare(host) == .orderedSame
        }?.faviconData
    }
}
