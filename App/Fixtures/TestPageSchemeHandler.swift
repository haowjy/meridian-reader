#if DEBUG
import Foundation
import WebKit

/// Offline pages (Debug builds only), served at `reader-test://<host>/<name>`:
///
/// - **`pages`**: the browser's, with `-browseTestPages` (`RootView` gives the browser's web view
///   the handler; real navigations, so they get real back/forward history):
///   - `one`: not an article (no 📄 / 🎧), with links to the others and to a book (`bookLink`);
///   - `two` ("Second page", with a link to `three` in its text) and `three` ("Third page"): articles (pass `isProbablyReaderable`);
///   - `thin` ("Thin page"): readable by that check, but its article text is invisible, so the
///     saved copy (which drops short invisible text) has almost nothing to listen to;
///   - `untitled`: an article with no `<title>` and no heading, so it has no title (`PageTitle`);
///   - `book-N`: chapter N of the demo book (`DemoBook`, `-seedDemoBook`).
/// - **`story`**: a story to follow, served to the browser and to Follow's fetch queue, which a
///   Debug build always serves (`AppComposition.makeFollow`):
///   - `toc` ("The Tide Keeper"): the table of contents, a site menu and then the chapter list,
///     `-testStoryChapters` chapters long (8 by default), an author's note third;
///   - `chapter-N`, `note`: the chapters (a chapter links to the next). With
///     `-testStoryThrottles`, `chapter-6` doesn't load the first time in a launch (a site not
///     answering), so Follow backs off.
///
/// An unknown name is page one.
final class TestPageSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = URL.testPageScheme
    /// What a web view that serves the offline pages registers (`schemeHandlers`).
    static var handlers: [String: any WKURLSchemeHandler] { [scheme: TestPageSchemeHandler()] }
    /// `-testStoryThrottles`' failed load has happened this launch.
    @MainActor private static var throttled = false

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else { return }
        // WebKit hands a custom scheme's reply on without its HTTP status, so the offline
        // stand-in for a site that won't answer is a failed load.
        if url.host == "story", url.lastPathComponent == "chapter-6", LaunchOptions.current.testStoryThrottles, !Self.throttled {
            Self.throttled = true
            urlSchemeTask.didFailWithError(URLError(.timedOut))
            return
        }
        let html = url.host == "story" ? Self.storyPage(url.lastPathComponent) : Self.page(url.lastPathComponent)
        let data = Data(html.utf8)
        let response = URLResponse(url: url, mimeType: "text/html", expectedContentLength: data.count, textEncodingName: "utf-8")
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    /// The `pages` page's HTML; an unknown name is page one.
    static func page(_ name: String) -> String {
        let sentence = "This offline test article has a long paragraph so Readability counts it as real reading content. "
        let title: String?
        var body: String
        if let chapter = DemoBook.testPage(name) {
            return document(title: chapter.title, body: chapter.body)
        }
        switch name {
        case "two":
            title = "Second page"
            // One link in the text, to check that a link opens in the browser.
            body = (1...5).map { i in
                "<p>" + String(repeating: sentence, count: 4)
                    + (i == 3 ? "Read <a href=\"reader-test://pages/three\">the third page</a> next.</p>" : "</p>")
            }.joined()
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
        case "untitled":
            title = nil
            let plain = "An offline article that names itself nowhere, neither in its head nor in a heading of its own. "
            body = (1...5).map { _ in "<p>" + String(repeating: plain, count: 4) + "</p>" }.joined()
        default:
            title = "First page"
            let link = "style=\"display:block;padding:24px;background:#ddd;margin-bottom:8px\""
            body = "<p><a href=\"reader-test://pages/two\" \(link)>Next page</a></p>"
                + "<p><a href=\"reader-test://pages/three\" \(link)>Third page</a></p>"
                + "<p><a href=\"reader-test://story/toc\" \(link)>A story to follow</a></p>"
                + "<p><a href=\"reader-test://pages/thin\" \(link)>Thin page</a></p>"
                + "<p><a href=\"reader-test://pages/untitled\" \(link)>A page with no title</a></p>"
                + "<p><a id=\"book\" href=\"#\" \(link)>Download a book</a></p>"
                + bookLink
        }
        return document(title: title, body: body)
    }

    /// The `story` page's HTML: the table of contents, a chapter, the author's note. An unknown
    /// name is page one.
    static func storyPage(_ name: String) -> String {
        let titles = ["The Lamp", "Low Water", "Author's Note", "The Keeper's Log", "Fog Bell", "Spring Tide",
                      "The Wreck", "Night Watch", "Harbour Lights", "The Relief Boat", "Storm Glass", "Last Light"]
        if name == "toc" {
            let menu = ["Home", "Rankings", "Forums", "Sign In"].map { "<li><a href=\"reader-test://story/\($0.lowercased())\">\($0)</a></li>" }
            var chapter = 0
            let items = (0..<min(LaunchOptions.current.testStoryChapters, titles.count)).map { index -> String in
                guard titles[index] != "Author's Note" else {
                    return "<li><a href=\"reader-test://story/note\">Author's Note</a></li>"
                }
                chapter += 1
                return "<li><a href=\"reader-test://story/chapter-\(chapter)\">Chapter \(chapter): \(titles[index])</a></li>"
            }
            let body = "<nav><ul>\(menu.joined())</ul></nav><p>by A. Keeper</p><ol>\(items.joined())</ol>"
            return document(title: "The Tide Keeper", body: body, meta: "<meta name=\"author\" content=\"A. Keeper\">")
        }
        if name == "note" {
            return document(title: "Author's Note", body: "<p>" + String(repeating: "A short note from the keeper of this story about the next chapter, which will come a little late this week while the lamp is mended. ", count: 6) + "</p>")
        }
        guard name.hasPrefix("chapter-"), let number = Int(name.dropFirst("chapter-".count)) else { return page(name) }
        let sentence = "On the \(number)th night the keeper climbed the stair and trimmed the wick while the tide turned below the rocks. "
        let body = (1...5).map { "<p>Part \($0). " + String(repeating: sentence, count: 3) + "</p>" }.joined()
        let next = "<nav><a href=\"reader-test://story/chapter-\(number + 1)\">Next chapter</a></nav>"
        return document(title: "Chapter \(number)", body: next + body)
    }

    /// Points page one's "Download a book" at the synthetic EPUB (`TestEPUB`) as a `blob:` URL
    /// served as `application/epub+zip`: WebKit downloads that as it would a book from the web
    /// (it makes no downloads from a custom scheme like this one).
    private static var bookLink: String {
        guard let book = try? TestEPUB.data() else { return "" }
        return """
        <script>
        const bytes = Uint8Array.from(atob("\(book.base64EncodedString())"), c => c.charCodeAt(0));
        document.getElementById("book").href = URL.createObjectURL(new Blob([bytes], { type: "application/epub+zip" }));
        </script>
        """
    }

    /// `title` nil: no `<title>` and no heading.
    private static func document(title: String?, body: String, meta: String = "") -> String {
        """
        <html><head><meta name="viewport" content="width=device-width">\(title.map { "<title>\($0)</title>" } ?? "")\(meta)</head>
        <body style="font: 20px -apple-system; padding: 24px">\(title.map { "<h1>\($0)</h1>" } ?? "")\(body)</body></html>
        """
    }
}
#endif
