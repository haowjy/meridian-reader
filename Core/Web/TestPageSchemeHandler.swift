#if DEBUG
import Foundation
import WebKit

/// Offline pages (Debug builds only), served at `reader-test://<host>/<name>`:
///
/// - **`pages`**: the browser's, with `LaunchOptions.servesTestPages` (real navigations, so they
///   get real back/forward history):
///   - `one`: not an article (no 📄 / 🎧), with links to the others;
///   - `two` ("Second page") and `three` ("Third page"): articles (pass `isProbablyReaderable`);
///   - `thin` ("Thin page"): readable by that check, but its article text is invisible, so the
///     saved copy (which drops short invisible text) has almost nothing to listen to;
///   - `book-N`: chapter N of the demo book (`DemoBook`, `-seedDemoBook`).
/// - **`fetch`**: `URLPageFetcher`'s, always served to it in Debug builds:
///   - `hidden-span` ("Hidden span page"): an article whose paragraphs carry two short lines the
///     page's stylesheet hides (`hiddenLines`), as anti-copy lines are hidden;
///   - `stall`: never answers, so a load waits until it is stopped.
///
/// An unknown name is page one.
final class TestPageSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "reader-test"
    /// `reader-test://fetch/hidden-span`.
    static let hiddenSpanPage = URL(string: "reader-test://fetch/hidden-span")!
    /// `reader-test://fetch/stall`.
    static let stallingPage = URL(string: "reader-test://fetch/stall")!

    /// The lines `hidden-span` hides with its stylesheet: one with `display: none`, one placed far
    /// off the page's left edge (which only layout can tell).
    static let hiddenLines = [
        "This sentence is hidden by the page's stylesheet and should never be read aloud.",
        "This sentence sits far off the left edge of the page and should never be read aloud.",
    ]

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else { return }
        let html: String
        if url.host == "fetch" {
            guard let page = Self.fetchPage(url.lastPathComponent) else { return }
            html = page
        } else {
            html = Self.page(url.lastPathComponent)
        }
        let data = Data(html.utf8)
        let response = URLResponse(url: url, mimeType: "text/html", expectedContentLength: data.count, textEncodingName: "utf-8")
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    /// Every `pages` page served, by name.
    static var pageNames: [String] {
        ["one", "two", "three", "thin"] + DemoBook.chapters.indices.map { "book-\($0)" }
    }

    /// The `pages` page's HTML; an unknown name is page one.
    static func page(_ name: String) -> String {
        let sentence = "This offline test article has a long paragraph so Readability counts it as real reading content. "
        let title: String
        var body: String
        if let chapter = DemoBook.testPage(name) {
            return document(title: chapter.title, body: chapter.body)
        }
        switch name {
        case "two":
            title = "Second page"
            body = (1...5).map { _ in "<p>" + String(repeating: sentence, count: 4) + "</p>" }.joined()
        case "three":
            title = "Third page"
            let other = "A different offline article, about harbors and the boats that come and go with the tide. "
            body = (1...5).map { _ in "<p>" + String(repeating: other, count: 4) + "</p>" }.joined()
        case "thin":
            title = "Thin page"
            // Each paragraph is long enough for the readable check (which ignores opacity) and
            // short enough for the snapshot to drop as hidden text.
            let hidden = "Hidden text that only the readability check can see, never the listener, on this page."
            body = (1...5).map { _ in "<p style=\"opacity:0\">" + hidden + " " + hidden + "</p>" }.joined()
                + "<p>Only a line here.</p>"
        default:
            title = "First page"
            let link = "style=\"display:block;padding:24px;background:#ddd;margin-bottom:8px\""
            body = "<p><a href=\"reader-test://pages/two\" \(link)>Next page</a></p>"
                + "<p><a href=\"reader-test://pages/three\" \(link)>Third page</a></p>"
                + "<p><a href=\"reader-test://pages/thin\" \(link)>Thin page</a></p>"
        }
        return document(title: title, body: body)
    }

    /// The `fetch` page's HTML; nil for `stall`, which never answers. An unknown name is page one.
    static func fetchPage(_ name: String) -> String? {
        switch name {
        case "stall":
            return nil
        case "hidden-span":
            // The hiding rules sit in the stylesheet, by class (as anti-copy lines are hidden):
            // Readability looks only at inline styles, so without the snapshot both lines would
            // reach the saved text.
            let style = ".k3v9q{display:none}.q8x2m{position:absolute;left:-9999px}"
            let sentence = "The keeper of the lighthouse wrote the weather in the log every evening before the lamp was lit. "
            let paragraphs = (1...5).map { i -> String in
                let hidden = switch i {
                case 2: " <span class=\"k3v9q\">\(hiddenLines[0])</span> "
                case 4: " <span class=\"q8x2m\">\(hiddenLines[1])</span> "
                default: " "
                }
                return "<p>Paragraph \(i). " + String(repeating: sentence, count: 2) + hidden + sentence + "</p>"
            }
            return document(title: "Hidden span page", body: paragraphs.joined(), style: style)
        default:
            return page(name)
        }
    }

    private static func document(title: String, body: String, style: String? = nil) -> String {
        """
        <html><head><meta name="viewport" content="width=device-width"><title>\(title)</title>\(style.map { "<style>\($0)</style>" } ?? "")</head>
        <body style="font: 20px -apple-system; padding: 24px"><h1>\(title)</h1>\(body)</body></html>
        """
    }
}
#endif
