import Foundation

/// Live-page extraction via HTML snapshot + Mozilla Readability (off-screen WKWebView).
struct ReadabilityArticleExtractor: ArticleExtracting {
    func availability(for context: ExtractionContext) async -> ArticleAvailability {
        guard let html = context.htmlSnapshot, !html.isEmpty else {
            return .unavailable(reason: "Page HTML isn’t available yet.")
        }
        return .available
    }

    func extract(from context: ExtractionContext) async throws -> ExtractedArticle {
        guard let html = context.htmlSnapshot, !html.isEmpty else {
            throw ExtractionError.engineFailed(message: "No HTML snapshot from the live page.")
        }
        let parsed = try await ReadabilityRunner.parse(html: html, baseURL: context.url)
        return ExtractedArticle(
            title: parsed.title,
            siteName: parsed.siteName ?? context.url.host,
            cleanedHTML: parsed.contentHTML,
            plainText: parsed.textContent,
            excerpt: parsed.excerpt
        )
    }
}
