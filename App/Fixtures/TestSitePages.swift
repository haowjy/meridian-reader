#if DEBUG
import Foundation

/// Offline sites for Follow's generic rules (Debug builds only), served by `TestPageSchemeHandler`
/// with `-browseTestPages` and to Follow's fetch queue:
///
/// - **`serial`** ("The Copper Orchard", shaped like a serial site): the story page
///   `reader-test://serial/story/40512/the-copper-orchard` has a site menu, a *Start Reading*
///   button and a chapters table (numbered titles, each row's date linking to the same chapter,
///   dates oldest first). Chapter pages `…/chapter/<n>/<slug>` have a link back to the story
///   page, previous and next links, and no list of their own: *Follow…* from one finds the story.
/// - **`blog`** ("Harbour Notes"): the index `reader-test://blog/` advertises an RSS feed
///   (`/feed.xml`, newest first, in RFC 822 dates) and a comments feed, which is left out. Posts
///   are `/post/<slug>`.
enum TestSitePages {
    private static let chapterTitles = ["First Frost", "The Orchard Gate", "Windfall", "Cider Season", "Grafting",
                                        "The Blight", "Hard Winter", "Thaw"]
    private static let postTitles = ["Mending the Slipway", "Notes on a Neap Tide", "The Gull Census", "A Quiet Week"]

    /// The reply for `url` on `serial` or `blog`: its HTML or XML and the MIME type.
    static func reply(for url: URL) -> (body: String, mime: String)? {
        switch url.host {
        case "serial": (serialPage(url.pathComponents.filter { $0 != "/" }), "text/html")
        case "blog" where url.path == "/feed.xml": (feed, "application/rss+xml")
        case "blog": (blogPage(url.pathComponents.filter { $0 != "/" }), "text/html")
        default: nil
        }
    }

    // MARK: - Serial

    private static func chapterURL(_ number: Int) -> String {
        "reader-test://serial/story/40512/the-copper-orchard/chapter/\(900000 + number)/\(slug(chapterTitles[number - 1]))"
    }

    private static func slug(_ title: String) -> String {
        title.lowercased().replacingOccurrences(of: " ", with: "-")
    }

    private static func serialPage(_ path: [String]) -> String {
        let menu = ["Home", "Browse", "Sign In"].map { "<li><a href=\"reader-test://serial/\($0.lowercased())\">\($0)</a></li>" }
        let site = "<meta property=\"og:site_name\" content=\"Example Serials\">"
        if path.count >= 5, path[3] == "chapter", let id = Int(path[4]), (900001...900008).contains(id) {
            let number = id - 900000
            let story = "<p><a href=\"reader-test://serial/story/40512/the-copper-orchard\">The Copper Orchard</a></p>"
            let previous = number > 1 ? "<a href=\"\(chapterURL(number - 1))\">Previous Chapter</a>" : ""
            let next = number < chapterTitles.count ? "<a href=\"\(chapterURL(number + 1))\">Next Chapter</a>" : ""
            let text = "On the \(number)th morning the pickers came up the hill with their ladders and their baskets, and the frost was still on the grass. "
            return TestPageSchemeHandler.document(
                title: "Chapter \(number): \(chapterTitles[number - 1])",
                body: "<nav><ul>\(menu.joined())</ul></nav>\(story)<nav>\(previous) \(next)</nav>"
                    + (1...5).map { "<p>Part \($0). " + String(repeating: text, count: 3) + "</p>" }.joined(),
                meta: site)
        }
        guard path.count == 3, path[0] == "story" else { return TestPageSchemeHandler.page("one") }
        let rows = chapterTitles.indices.map { index -> String in
            let number = index + 1
            let day = String(format: "2024-03-%02d", number)
            return "<tr><td><a href=\"\(chapterURL(number))\">Chapter \(number): \(chapterTitles[index])</a></td>"
                + "<td><a href=\"\(chapterURL(number))\"><time datetime=\"\(day)T08:00:00Z\">\(day)</time></a></td></tr>"
        }
        let body = "<nav><ul>\(menu.joined())</ul></nav><p>by A. Orchardist</p>"
            + "<p><a href=\"\(chapterURL(1))\">Start Reading</a></p><table>\(rows.joined())</table>"
        return TestPageSchemeHandler.document(title: "The Copper Orchard", body: body,
                                              meta: site + "<meta name=\"author\" content=\"A. Orchardist\">")
    }

    // MARK: - Blog

    private static func blogPage(_ path: [String]) -> String {
        let meta = "<meta property=\"og:site_name\" content=\"Harbour Notes\">"
            + "<link rel=\"alternate\" type=\"application/rss+xml\" title=\"Comments\" href=\"reader-test://blog/comments.xml\">"
            + "<link rel=\"alternate\" type=\"application/rss+xml\" title=\"Harbour Notes\" href=\"reader-test://blog/feed.xml\">"
        if path.count == 2, path[0] == "post", let index = postTitles.firstIndex(where: { slug($0) == path[1] }) {
            let text = "The slipway had gone soft at the seaward end, and it took three of us and a borrowed jack to lift the cradle clear. "
            return TestPageSchemeHandler.document(
                title: postTitles[index],
                body: "<p><a href=\"reader-test://blog/\">Harbour Notes</a></p>"
                    + (1...5).map { "<p>Paragraph \($0). " + String(repeating: text, count: 3) + "</p>" }.joined(),
                meta: meta)
        }
        let list = postTitles.map { "<li><a href=\"reader-test://blog/post/\(slug($0))\">\($0)</a></li>" }
        return TestPageSchemeHandler.document(title: "Harbour Notes", body: "<p>A blog about a small harbour.</p><ul>\(list.joined())</ul>", meta: meta)
    }

    /// The feed, newest first.
    private static var feed: String {
        let days = ["Mon, 04 Nov 2024", "Mon, 28 Oct 2024", "Mon, 21 Oct 2024", "Mon, 14 Oct 2024"]
        let items = postTitles.indices.map { index in
            "<item><title>\(postTitles[index])</title><link>reader-test://blog/post/\(slug(postTitles[index]))</link>"
                + "<pubDate>\(days[index]) 09:00:00 GMT</pubDate></item>"
        }
        return "<?xml version=\"1.0\"?><rss version=\"2.0\"><channel><title>Harbour Notes</title>"
            + "<link>reader-test://blog/</link>\(items.joined())</channel></rss>"
    }
}
#endif
