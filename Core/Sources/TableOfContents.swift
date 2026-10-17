import Foundation

/// A page's links as the out-of-sight fetcher reads them (`URLPageFetcher.links(of:)`): every link
/// in document order with its text, and the list it sits in, so the chapter list can be told from
/// the site's menus.
struct LinkPage: Equatable, Sendable {
    struct Link: Equatable, Sendable {
        var url: URL
        var text: String
        /// The list it sits in (its nearest `ol`, `ul`, `table`, `nav` or `dl`, else its parent's
        /// parent), numbered in the page: links with the same number are one list.
        var list: Int
    }

    /// Where the page ended up, after redirects.
    var url: URL
    /// The document's title.
    var title: String?
    /// The first heading (`h1`).
    var heading: String?
    /// The author, when the page names one (a meta tag, a story's author link).
    var author: String?
    var links: [Link]
}

/// A story's table of contents: its title and author and its chapter links, in the story's order
/// (`read(_:)`). Royal Road's story pages are read by their own rule; any other site by the
/// generic one, which takes the page's longest list of chapter-like links.
struct TableOfContents: Equatable, Sendable {
    struct Chapter: Equatable, Hashable, Sendable {
        var title: String
        var url: URL

        /// The address one page per canonical URL goes by (`ArticleIdentity`).
        var canonicalURL: String { ArticleIdentity.canonicalURLString(from: url) }
    }

    /// The contents page.
    var url: URL
    var title: String
    var byline: String?
    var chapters: [Chapter]

    /// The page that lists a story's chapters, for an address on that story: a Royal Road
    /// chapter's story page (`/fiction/<id>`); any other address as it is.
    static func contentsURL(for url: URL) -> URL {
        guard RoyalRoad.isRoyalRoad(url), let id = RoyalRoad.storyID(in: url),
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        parts.path = "/fiction/\(id)"
        parts.query = nil
        parts.fragment = nil
        return parts.url ?? url
    }

    /// The story on `page`; nil when no list of chapters can be found on it.
    static func read(_ page: LinkPage) -> TableOfContents? {
        let chapters = RoyalRoad.isRoyalRoad(page.url) ? RoyalRoad.chapters(on: page) : Generic.chapters(on: page)
        guard !chapters.isEmpty else { return nil }
        let title = [page.heading, page.title.map(Self.siteNameRemoved)].compactMap { $0 }.first { !$0.isEmpty }
        let byline = page.author.map(Self.squeezed).flatMap { $0.isEmpty ? nil : $0 }
        return TableOfContents(url: page.url, title: title ?? page.url.host ?? page.url.absoluteString,
                               byline: byline, chapters: chapters)
    }

    /// "Mother of Learning | Royal Road" → "Mother of Learning".
    private static func siteNameRemoved(_ title: String) -> String {
        let parts = title.components(separatedBy: " | ")
        return squeezed(parts.count > 1 ? parts.dropLast().joined(separator: " | ") : title)
    }

    static func squeezed(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Chapters in page order, one per address (the first link's text names it), skipping links
    /// without text.
    fileprivate static func unique(_ links: [LinkPage.Link]) -> [Chapter] {
        var seen = Set<String>()
        var chapters: [Chapter] = []
        for link in links {
            let title = squeezed(link.text)
            guard !title.isEmpty else { continue }
            let chapter = Chapter(title: title, url: link.url)
            guard seen.insert(chapter.canonicalURL).inserted else { continue }
            chapters.append(chapter)
        }
        return chapters
    }

    // MARK: - Royal Road

    /// Royal Road's story page (`royalroad.com/fiction/<id>/<slug>`) lists every chapter in its
    /// chapters table, served whole (the site pages through it with scripts, which are off).
    /// Chapter links are `/fiction/<id>/<slug>/chapter/<chapter id>/<slug>`; the same chapter also
    /// links from the row's date and the *Start Reading* button, so the list holding the most
    /// chapter links is the table, and the first link of each row names it.
    private enum RoyalRoad {
        static func isRoyalRoad(_ url: URL) -> Bool {
            guard let host = url.host?.lowercased() else { return false }
            return host == "royalroad.com" || host.hasSuffix(".royalroad.com")
        }

        /// The story's number: the path's `/fiction/<id>`.
        static func storyID(in url: URL) -> String? {
            let parts = url.pathComponents
            guard let index = parts.firstIndex(of: "fiction"), index + 1 < parts.count,
                  Int(parts[index + 1]) != nil else { return nil }
            return parts[index + 1]
        }

        static func isChapter(_ url: URL, of story: String) -> Bool {
            guard isRoyalRoad(url) else { return false }
            let parts = url.pathComponents
            guard let index = parts.firstIndex(of: "fiction"), parts.count > index + 4,
                  parts[index + 1] == story, parts[index + 3] == "chapter" else { return false }
            return Int(parts[index + 4]) != nil
        }

        static func chapters(on page: LinkPage) -> [Chapter] {
            guard let story = storyID(in: page.url) else { return [] }
            let links = page.links.filter { isChapter($0.url, of: story) }
            let counts = Dictionary(grouping: links, by: \.list).mapValues(\.count)
            guard let table = counts.max(by: { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) })?.key
            else { return [] }
            return unique(links.filter { $0.list == table })
        }
    }

    // MARK: - Any other site

    /// The list on the page with the most chapter-like links on the page's own site: links whose
    /// text or address reads as a chapter ("Chapter 3", "Ch. 3", "Part Two", "Episode 4",
    /// "Prologue", a number) count three times, any other link once, so a long menu loses to a
    /// shorter chapter list. A list needs at least two chapter-like links. Links to the page
    /// itself are left out.
    private enum Generic {
        static func chapters(on page: LinkPage) -> [Chapter] {
            let here = ArticleIdentity.canonicalURLString(from: page.url)
            let candidates = page.links.filter { link in
                sameSite(link.url, page.url) && ArticleIdentity.canonicalURLString(from: link.url) != here
                    && !squeezed(link.text).isEmpty
            }
            var best: (list: Int, score: Int)?
            for (list, links) in Dictionary(grouping: candidates, by: \.list) {
                let chapterLike = links.filter(isChapterLike).count
                guard chapterLike >= 2 else { continue }
                let score = links.count + 2 * chapterLike
                if best == nil || score > best!.score || (score == best!.score && list < best!.list) {
                    best = (list, score)
                }
            }
            guard let best else { return [] }
            return unique(candidates.filter { $0.list == best.list })
        }

        static func sameSite(_ a: URL, _ b: URL) -> Bool {
            guard a.scheme == b.scheme || (a.scheme?.hasPrefix("http") == true && b.scheme?.hasPrefix("http") == true)
            else { return false }
            return site(a) == site(b)
        }

        /// The host without a leading "www.".
        static func site(_ url: URL) -> String {
            let host = url.host?.lowercased() ?? ""
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }

        static func isChapterLike(_ link: LinkPage.Link) -> Bool {
            let text = link.text.lowercased()
            let path = link.url.path.lowercased()
            let words = ["chapter", "ch.", "part ", "episode", "prologue", "epilogue", "interlude", "book "]
            if words.contains(where: text.contains) || path.contains("chapter") { return true }
            return text.split(whereSeparator: { !$0.isNumber }).contains { !$0.isEmpty }
        }
    }
}
