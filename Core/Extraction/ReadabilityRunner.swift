import Foundation
import WebKit

/// Runs Mozilla Readability against an HTML snapshot in an off-screen web view
/// (`OffscreenWebView`), then the listen normalizer in the same view
/// (`ListenContentNormalizer`).
///
/// The snapshot is the live page after its own JavaScript ran (`WebViewStore.snapshotHTML`), so
/// the page's scripts stay off here: running its `<script>` tags and inline handlers a second time
/// would fire network requests and change the DOM before Readability reads it.
@MainActor
enum ReadabilityRunner {
    struct ParseResult: Sendable {
        /// nil: the page has none (Readability found no `<title>`, heading or title metadata).
        var title: String?
        var byline: String?
        var contentHTML: String
        var textContent: String
        var excerpt: String
        var siteName: String?
    }

    /// The base a page without a web address (a book's chapter, a test page) is parsed against:
    /// its relative links come out under it, and point nowhere.
    static let placeholderBase = URL(string: "https://reader.invalid/")!

    static func parse(html: String, baseURL: URL) async throws -> ParseResult {
        let readabilityJS = try loadResource("Readability", ext: "js")
        let readerableJS = (try? loadResource("Readability-readerable", ext: "js")) ?? ""

        let bridge = """
        (function() {
          try {
            if (typeof isProbablyReaderable === 'function' && !isProbablyReaderable(document)) {
              return JSON.stringify({ ok: false, reason: 'Page is probably not an article.' });
            }
            var article = new Readability(document.cloneNode(true)).parse();
            if (!article) {
              return JSON.stringify({ ok: false, reason: 'Readability returned no article.' });
            }
            return JSON.stringify({
              ok: true,
              title: article.title || '',
              byline: article.byline || '',
              content: article.content || '',
              textContent: article.textContent || '',
              excerpt: article.excerpt || '',
              siteName: article.siteName || ''
            });
          } catch (e) {
            return JSON.stringify({ ok: false, reason: String(e) });
          }
        })();
        """

        let webView = OffscreenWebView.make()
        // Only web base URLs load; other schemes (e.g. the UI tests' `reader-test://` pages) never
        // finish, so parse those against a neutral https base.
        let webBase = baseURL.isWeb ? baseURL : placeholderBase
        try await OffscreenWebView.load(webView, html: html, baseURL: webBase)
        _ = try await webView.evaluateJavaScript(readabilityJS + "\n" + readerableJS)
        let raw = try await webView.evaluateJavaScript(bridge)
        guard let jsonString = raw as? String,
              let data = jsonString.data(using: .utf8),
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ExtractionError.engineFailed(message: "Readability returned an unexpected payload.")
        }
        guard (obj["ok"] as? Bool) == true else {
            let reason = (obj["reason"] as? String) ?? "Extraction failed."
            throw ExtractionError.unavailable(reason: reason)
        }
        let site = (obj["siteName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        // Without the site's name after a separator: the heading below and the page's title say
        // the same, and the source line names the site. A page without one has none.
        let title = ((obj["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { $0.isEmpty ? nil : ArticleTitle.withoutSiteSuffix($0, siteName: site, host: baseURL.host) }
        let text = (obj["textContent"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let content = try await ListenContentNormalizer.normalize((obj["content"] as? String) ?? "", in: webView)
        if text.isEmpty || content.isEmpty {
            throw ExtractionError.emptyContent
        }
        let excerpt = (obj["excerpt"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? String(text.prefix(140))
        let byline = (obj["byline"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let wrapped = """
        <!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        body{font:-apple-system-body;padding:16px;line-height:1.55;color:#111}
        h1{font:-apple-system-title1;margin-bottom:8px}
        img{max-width:100%;height:auto}
        </style></head><body>
        \(title.map { "<h1>\(htmlEscape($0))</h1>" } ?? "")
        \(byline.map { "<p><em>\(htmlEscape($0))</em></p>" } ?? "")
        \(content)
        </body></html>
        """
        return ParseResult(
            title: title,
            byline: byline,
            contentHTML: wrapped,
            textContent: text,
            excerpt: excerpt,
            siteName: site
        )
    }

    private static func loadResource(_ name: String, ext: String) throws -> String {
        let candidates = [
            Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Readability"),
            Bundle.main.url(forResource: name, withExtension: ext)
        ].compactMap { $0 }
        guard let url = candidates.first else {
            throw ExtractionError.engineFailed(message: "Missing \(name).\(ext) in app bundle. Check Resources/Readability.")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func htmlEscape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
