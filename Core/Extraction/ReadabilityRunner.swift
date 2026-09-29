import Foundation
import WebKit
import ObjectiveC

/// Runs Mozilla Readability against an HTML snapshot inside an off-screen WKWebView.
@MainActor
enum ReadabilityRunner {
    struct ParseResult: Sendable {
        var title: String
        var byline: String?
        var contentHTML: String
        var textContent: String
        var excerpt: String
        var siteName: String?
    }

    static func parse(html: String, baseURL: URL) async throws -> ParseResult {
        let readabilityJS = try loadResource("Readability", ext: "js")
        let readerableJS = (try? loadResource("Readability-readerable", ext: "js")) ?? ""
        let normalizeJS = ReaderScripts.normalizeContent ?? ""
        let listenSelector = ListenHTMLBlocks.innerSelector

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
              content: (typeof __readerNormalizeContent === 'function')
                ? __readerNormalizeContent(article.content || '', '\(listenSelector)')
                : (article.content || ''),
              textContent: article.textContent || '',
              excerpt: article.excerpt || '',
              siteName: article.siteName || ''
            });
          } catch (e) {
            return JSON.stringify({ ok: false, reason: String(e) });
          }
        })();
        """

        let webView = WKWebView(frame: .zero)
        // Only web base URLs load; other schemes (e.g. the UI tests' `reader-test://` pages) never
        // finish, so parse those against a neutral https base.
        let webBase = baseURL.scheme == "http" || baseURL.scheme == "https"
            ? baseURL : URL(string: "https://reader.invalid/")!
        try await loadHTML(webView, html: html, baseURL: webBase)
        _ = try await webView.evaluateJavaScript(readabilityJS + "\n" + readerableJS + "\n" + normalizeJS)
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
        let title = (obj["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let text = (obj["textContent"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let content = (obj["content"] as? String) ?? ""
        if title.isEmpty || text.isEmpty || content.isEmpty {
            throw ExtractionError.emptyContent
        }
        let excerpt = (obj["excerpt"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? String(text.prefix(140))
        let site = (obj["siteName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let byline = (obj["byline"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let wrapped = """
        <!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        body{font:-apple-system-body;padding:16px;line-height:1.55;color:#111}
        h1{font:-apple-system-title1;margin-bottom:8px}
        img{max-width:100%;height:auto}
        </style></head><body>
        <h1>\(htmlEscape(title))</h1>
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

    private static func loadHTML(_ webView: WKWebView, html: String, baseURL: URL) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let nav = NavigationWaiter(continuation: cont)
            webView.navigationDelegate = nav
            objc_setAssociatedObject(webView, &Associated.navKey, nav, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    private static func htmlEscape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private enum Associated {
        static var navKey: UInt8 = 0
    }

    private final class NavigationWaiter: NSObject, WKNavigationDelegate {
        private var continuation: CheckedContinuation<Void, Error>?
        private var finished = false

        init(continuation: CheckedContinuation<Void, Error>) {
            self.continuation = continuation
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            finish(.success(()))
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            finish(.failure(ExtractionError.engineFailed(message: error.localizedDescription)))
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            finish(.failure(ExtractionError.engineFailed(message: error.localizedDescription)))
        }

        private func finish(_ outcome: Swift.Result<Void, Error>) {
            guard !finished else { return }
            finished = true
            continuation?.resume(with: outcome)
            continuation = nil
        }
    }
}
