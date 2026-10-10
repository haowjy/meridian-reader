import Foundation

/// Live-page extraction via HTML snapshot + Mozilla Readability (off-screen WKWebView).
struct ReadabilityArticleExtractor: ArticleExtracting {
    func availability(for context: ExtractionContext) async -> ArticleAvailability {
        guard context.origin.url != nil else { return .unavailable(reason: Self.webOnly) }
        guard let html = context.htmlSnapshot, !html.isEmpty else {
            return .unavailable(reason: "Page HTML isn’t available yet.")
        }
        return .available
    }

    func extract(from context: ExtractionContext) async throws -> ExtractedArticle {
        guard let url = context.origin.url else { throw ExtractionError.unavailable(reason: Self.webOnly) }
        guard let html = context.htmlSnapshot, !html.isEmpty else {
            throw ExtractionError.engineFailed(message: "No HTML snapshot from the live page.")
        }
        let parsed = try await ReadabilityRunner.parse(html: html, baseURL: url)
        return ExtractedArticle(
            title: parsed.title,
            siteName: parsed.siteName ?? url.host,
            cleanedHTML: parsed.contentHTML,
            plainText: parsed.textContent,
            excerpt: parsed.excerpt
        )
    }

    /// Readability reads web pages; book chapters go to the normalizer alone.
    private static let webOnly = "Reader mode reads web pages."
}
