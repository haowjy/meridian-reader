import Foundation

struct FakeArticleExtractor: ArticleExtracting {
    enum Mode: Sendable { case success, failure }
    var mode: Mode

    func availability(for context: ExtractionContext) async -> ArticleAvailability {
        switch mode {
        case .success: return .available
        case .failure: return .unavailable(reason: "This page doesn’t look like an article (fake extractor).")
        }
    }

    func extract(from context: ExtractionContext) async throws -> ExtractedArticle {
        switch mode {
        case .failure:
            throw ExtractionError.unavailable(reason: "This page doesn’t look like an article (fake extractor).")
        case .success:
            let trimmed = context.pageTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = (trimmed?.isEmpty == false) ? trimmed! : "Saved Article"
            let host = context.url.host ?? context.url.absoluteString
            let paragraphs = [
                "This is a placeholder article extracted by FakeArticleExtractor.",
                "URL: \(context.url.absoluteString)",
                "Replace this extractor with Mozilla Readability on the live WKWebView DOM after the spike."
            ]
            let body = paragraphs.joined(separator: "\n\n")
            let pTags = paragraphs.map { "<p>\(Self.escape($0))</p>" }.joined()
            // Site chrome uses <div>, not <p>, so listen indices match body paragraphs only.
            let html = """
            <!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
            <style>body{font:-apple-system-body;padding:16px;line-height:1.5}h1{font:-apple-system-title1}</style>
            </head><body>
            <h1>\(Self.escape(title))</h1>
            <div class="reader-site"><em>\(Self.escape(host))</em></div>
            \(pTags)
            </body></html>
            """
            return ExtractedArticle(
                title: title,
                siteName: host,
                cleanedHTML: html,
                plainText: body,
                excerpt: String(body.prefix(140))
            )
        }
    }

    private static func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
