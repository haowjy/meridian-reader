import Foundation
import UIKit
import WebKit

enum FaviconFetcher {
    /// A page's best icon: from its live document when the web view still shows that page, else
    /// the host's conventional icons. Asked after an extraction or a save, the web view may have
    /// moved on to another page by then; its icon isn't this page's.
    @MainActor
    static func best(for url: URL, webView: WKWebView?) async -> Data? {
        if let live = document(in: webView, showing: url), let icon = await fetch(from: live) { return icon }
        guard let host = url.host else { return nil }
        return await fetch(forHost: host)
    }

    /// `webView` while it shows the page at `url` (the same page, `URL.isSamePage`), else nil.
    @MainActor
    static func document(in webView: WKWebView?, showing url: URL) -> WKWebView? {
        guard let webView, webView.url.map({ $0.isSamePage(as: url) }) == true else { return nil }
        return webView
    }

    /// Best-effort icon URL from the live document, then its bytes (`download`).
    @MainActor
    private static func fetch(from webView: WKWebView) async -> Data? {
        let href = await iconHREF(from: webView)
        guard let href, let url = URL(string: href) else { return nil }
        return await download(url: url)
    }

    @MainActor
    private static func iconHREF(from webView: WKWebView) async -> String? {
        let js = """
        (function() {
          function abs(u) {
            try { return new URL(u, document.baseURI).href; } catch (e) { return null; }
          }
          // Prefer the biggest declared icon (apple-touch-icon is usually 180 px); a 16 px
          // favicon only as a last resort.
          var nodes = Array.prototype.slice.call(
            document.querySelectorAll('link[rel~="icon"], link[rel="shortcut icon"], link[rel="apple-touch-icon"], link[rel="apple-touch-icon-precomposed"]')
          );
          var best = null, bestScore = -1;
          for (var i = 0; i < nodes.length; i++) {
            var href = nodes[i].getAttribute('href');
            if (!href || href.toLowerCase().split('?')[0].slice(-4) === '.svg') continue;
            var a = abs(href);
            if (!a) continue;
            var rel = (nodes[i].getAttribute('rel') || '').toLowerCase();
            var m = /([0-9]+)x[0-9]+/.exec(nodes[i].getAttribute('sizes') || '');
            var score = m ? parseInt(m[1], 10) : (rel.indexOf('apple-touch-icon') >= 0 ? 180 : 16);
            if (score > bestScore) { best = a; bestScore = score; }
          }
          if (best) return best;
          try { return new URL('/favicon.ico', document.baseURI).href; } catch (e) { return null; }
        })();
        """
        do {
            let result = try await webView.evaluateJavaScript(js)
            return result as? String
        } catch {
            return nil
        }
    }

    /// The icon at `url`, or nil when the answer isn't one (`icon(_:response:)`).
    private static func download(url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            return icon(data, response: response)
        } catch {
            return nil
        }
    }

    /// A download's bytes when they are an icon: a 2xx answer, neither empty nor huge, that
    /// decodes as an image. Many sites answer a missing `/favicon.ico` with a 200 HTML page.
    static func icon(_ data: Data, response: URLResponse) -> Data? {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              data.count > 32, data.count < 256_000, UIImage(data: data) != nil else { return nil }
        return data
    }

    /// Fallback when no live WebView (e.g. backfill): the conventional `apple-touch-icon.png`
    /// (big enough for a tile), then `favicon.ico`.
    static func fetch(forHost host: String) async -> Data? {
        let cleaned = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        for path in ["apple-touch-icon.png", "favicon.ico"] {
            guard let url = URL(string: "https://\(cleaned)/\(path)") else { continue }
            if let data = await download(url: url) { return data }
        }
        return nil
    }

    /// Whether icon bytes are big enough to fill a tile (tiny 16 px icons look smeared).
    static func isTileSized(_ data: Data?) -> Bool {
        guard let data, let image = UIImage(data: data) else { return false }
        return image.size.width * image.scale >= 24
    }
}
