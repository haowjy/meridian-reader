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
        /// The date of the link's row (a `<time datetime>`), or of the feed entry.
        var date: Date?
    }

    /// A page's links, or a feed document's entries. The two are different documents with
    /// different rules, so they are different cases.
    enum Body: Equatable, Sendable {
        /// An HTML page: every link (asides and footers left out), the feeds it advertises
        /// (`<link rel="alternate">`, comment feeds left out) and its `rel=canonical` address.
        case page(links: [Link], feeds: [URL], canonical: URL?)
        /// An RSS or Atom document: its entries as given, and the address of the site it is the
        /// feed of (the channel's `<link>`; Atom's feed-level `rel=alternate`).
        case feed(entries: [Link], home: URL?)
    }

    /// Where the page ended up, after redirects.
    var url: URL
    /// The document's title.
    var title: String?
    /// The first heading (`h1`), or a feed's title.
    var heading: String?
    /// The author, when the page names one (a meta tag).
    var author: String?
    /// The site's own name for itself (`og:site_name`).
    var siteName: String?
    var body: Body
}

/// What a page lists to follow, found by `read(_:fetch:)` from the page's links, in this order:
/// 1. **The page's list of links**: the list holding the most chapter-like and dated links; or,
///    when the page is a feed, its entries.
/// 2. **The page it belongs to**, when it lists nothing itself (a chapter): the link on it whose
///    path is the longest proper prefix of its own, read as 1 would, and kept only when it lists
///    *Chapters*: a story's page, not a blog's index, so an article is never taken for its site.
///    One more fetch.
/// 3. **An advertised feed** (RSS 2.0, Atom), but only from its home: the feed's site address is
///    the page itself. An article on a site that has a feed is not that site's feed.
///
/// A feed comes last because it is a window of the latest entries (a serial's feed holds its last
/// ten chapters), where a page's list is whole.
///
/// What is followed is kept (`Source`, the page's or feed's address, and `Kind` in `FollowState`),
/// and a check reads that again (`again(_:as:)`): no climbing, no new fetches.
///
/// **Posts or chapters** (`Kind`): a feed, or a dated list running newest first, is *Posts*,
/// newest first. A list whose links mostly read as chapters is *Chapters*, in the story's order
/// (reversed when its dates run newest first). Any other list is *Chapters*, in the page's order.
struct TableOfContents: Equatable, Sendable {
    struct Chapter: Equatable, Hashable, Sendable {
        var title: String
        var url: URL
        /// When it was published, when the page or feed says.
        var date: Date?

        /// The address one page per canonical URL goes by (`ArticleIdentity`).
        var canonicalURL: String { ArticleIdentity.canonicalURLString(from: url) }
    }

    enum Kind: String, Codable, Equatable, Sendable {
        /// A blog or newsletter: dated, newest first.
        case posts
        /// A serial: in the story's order.
        case chapters
    }

    /// What the contents were read from.
    enum Source: String, Codable, Equatable, Sendable {
        /// A page's list of links.
        case list
        /// A feed document.
        case feed
    }

    /// The page or feed the list was read from; a check reads it again.
    var url: URL
    var title: String
    var byline: String?
    /// The site's name in notices: `og:site_name`, else its host without "www.".
    var siteName: String
    var source: Source
    var kind: Kind
    var chapters: [Chapter]

    /// Fetches another page's links, through the fetch queue.
    typealias Fetch = @MainActor (URL) async throws -> LinkPage

    /// What `page` lists to follow; nil when nothing can be found on it.
    static func read(_ page: LinkPage, fetch: Fetch) async throws -> TableOfContents? {
        if let found = again(page, as: nil) { return found }
        if let parent = parentURL(of: page) {
            let up = try await fetch(parent)
            if let found = again(up, as: .list), found.kind == .chapters { return found }
        }
        return try await advertisedFeed(of: page, fetch: fetch)
    }

    /// What `page`, a page already followed, lists now: its list of links or its feed, as it was
    /// read (`source`; nil from before it was kept: a feed document is a feed, else a list).
    static func again(_ page: LinkPage, as source: Source?) -> TableOfContents? {
        switch page.body {
        case .page where source != .feed: list(on: page)
        case .feed where source != .list: feed(page, siteName: nil)
        default: nil
        }
    }

    /// The host without a leading "www.": a site's identity, and its name when it gives none.
    static func host(of url: URL) -> String {
        let host = url.host?.lowercased() ?? ""
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// The contents `chapters` make, read from `page` (its heading or title names it); the site's
    /// name is `siteName`, else the page's.
    private static func make(_ page: LinkPage, siteName: String? = nil, source: Source, kind: Kind,
                             chapters: [Chapter]) -> TableOfContents? {
        guard !chapters.isEmpty else { return nil }
        let title = [page.heading, page.title.map(Self.siteNameRemoved)].compactMap { $0 }.first { !$0.isEmpty }
        let byline = page.author.map(Self.squeezed).flatMap { $0.isEmpty ? nil : $0 }
        let site = [siteName, page.siteName].compactMap { $0 }.map(squeezed).first { !$0.isEmpty }
        return TableOfContents(url: page.url, title: title ?? page.url.host ?? page.url.absoluteString, byline: byline,
                               siteName: site ?? host(of: page.url), source: source, kind: kind, chapters: chapters)
    }

    /// "The Copper Orchard | Example Press" → "The Copper Orchard".
    private static func siteNameRemoved(_ title: String) -> String {
        let parts = title.components(separatedBy: " | ")
        return squeezed(parts.count > 1 ? parts.dropLast().joined(separator: " | ") : title)
    }

    static func squeezed(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Chapters in page order, one per address (the first link's text names it), skipping links
    /// without text.
    private static func unique(_ links: [LinkPage.Link]) -> [Chapter] {
        var seen = Set<String>()
        var chapters: [Chapter] = []
        for link in links {
            let title = squeezed(link.text)
            guard !title.isEmpty else { continue }
            let chapter = Chapter(title: title, url: link.url, date: link.date)
            guard seen.insert(chapter.canonicalURL).inserted else { continue }
            chapters.append(chapter)
        }
        return chapters
    }

    private static func sameSite(_ a: URL, _ b: URL) -> Bool {
        guard a.scheme == b.scheme || (a.scheme?.hasPrefix("http") == true && b.scheme?.hasPrefix("http") == true)
        else { return false }
        return host(of: a) == host(of: b)
    }

    // MARK: - A feed

    /// The first feed `page` advertises (one more fetch), when `page` is its home: the feed's
    /// site address is the page's own (or its canonical one). Entries are *Posts*, newest first by
    /// date; a feed with no dates keeps its own order.
    private static func advertisedFeed(of page: LinkPage, fetch: Fetch) async throws -> TableOfContents? {
        guard case .page(_, let feeds, let canonical) = page.body, let url = feeds.first else { return nil }
        let document = try await fetch(url)
        guard case .feed(_, let home?) = document.body else { return nil }
        guard [page.url, canonical].compactMap({ $0 }).contains(where: { sameHome($0, home) }) else { return nil }
        return feed(document, siteName: page.siteName)
    }

    /// The same address, tolerating "www." and a trailing "/" (a WordPress feed names its home
    /// `https://example.com`, the page is `https://example.com/`). The port and the query must
    /// match: a post at `/?p=123` is not the home.
    private static func sameHome(_ a: URL, _ b: URL) -> Bool {
        func key(_ url: URL) -> [String?] {
            [url.port.map(String.init), url.query, pathParts(url).joined(separator: "/")]
        }
        return host(of: a) == host(of: b) && key(a) == key(b)
    }

    private static func feed(_ document: LinkPage, siteName: String?) -> TableOfContents? {
        guard case .feed(let entries, _) = document.body else { return nil }
        let posts = unique(entries).sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        return make(document, siteName: siteName, source: .feed, kind: .posts, chapters: posts)
    }

    // MARK: - The page's list

    /// The list on the page with the highest score, on the page's own site. A link counts for
    /// itself; one that reads as a chapter ("Chapter 3", "Ch. 3", "Part Two", "Episode 4",
    /// "Prologue", "12. Title") or has a date counts three times; links sharing one path shape
    /// (`shape`: `/story/#/*/chapter/#/*`) add the size of the largest such group. A list needs
    /// three links, at least half of them chapter-like or dated, so a chapter's previous and next
    /// links, a site's menu or a blog's archive with a "Part 2" here and there are not a list.
    /// Links to the page itself and to its ancestors are left out.
    private static func list(on page: LinkPage) -> TableOfContents? {
        guard case .page(let links, _, _) = page.body else { return nil }
        let here = ArticleIdentity.canonicalURLString(from: page.url)
        let candidates = links.filter { link in
            sameSite(link.url, page.url) && ArticleIdentity.canonicalURLString(from: link.url) != here
                && !squeezed(link.text).isEmpty
                // A link up to the page's own parent is never one of its chapters; a chapter's
                // navigation (← Contents, ← Previous, Next →) shrinks below three links.
                && !isAncestor(link.url, of: page.url)
        }
        var best: (list: Int, score: Int)?
        for (list, links) in Dictionary(grouping: candidates, by: \.list) {
            let signalled = links.filter { isChapterLike($0) || $0.date != nil }.count
            guard links.count >= 3, 2 * signalled >= links.count else { continue }
            let sharedShape = Dictionary(grouping: links, by: { shape(of: $0.url) }).values.map(\.count).max() ?? 0
            let score = links.count + 2 * signalled + sharedShape
            if best == nil || score > best!.score || (score == best!.score && list < best!.list) {
                best = (list, score)
            }
        }
        guard let best else { return nil }
        let members = candidates.filter { $0.list == best.list }
        let newestFirst = runsNewestFirst(members.compactMap(\.date))
        let chapterLike = members.filter(isChapterLike).count * 2 > members.count
        var chapters = unique(members)
        if chapterLike, newestFirst { chapters.reverse() }
        return make(page, source: .list, kind: chapterLike || !newestFirst ? .chapters : .posts, chapters: chapters)
    }

    /// More of the neighbouring pairs of dates fall than rise, so one pinned item or an odd date
    /// doesn't turn a list.
    private static func runsNewestFirst(_ dates: [Date]) -> Bool {
        let pairs = zip(dates, dates.dropFirst())
        return pairs.filter { $0 > $1 }.count > pairs.filter { $0 < $1 }.count
    }

    /// The path with numbers as `#` and the last part as `*`: `/story/12/a-b/chapter/3/c-d`
    /// and `/story/12/a-b/chapter/4/e` are one shape.
    private static func shape(of url: URL) -> String {
        let parts = url.pathComponents.filter { $0 != "/" }
        return parts.enumerated().map { index, part in
            index == parts.count - 1 ? "*" : (Int(part) != nil ? "#" : part)
        }.joined(separator: "/")
    }

    private static func isChapterLike(_ link: LinkPage.Link) -> Bool {
        let text = link.text.lowercased()
        let path = link.url.path.lowercased()
        if text.contains(/\b(chapter|part|episode|prologue|epilogue|interlude|book)\b|\bch\./) || path.contains("chapter") {
            return true
        }
        // Not a version or a decimal ("6.5 release notes").
        return text.wholeMatch(of: /\d+\s*[.:)\-–—](?!\d).*/) != nil
    }

    // MARK: - The page it belongs to

    /// A page with no list of its own (a chapter) leads to its story: the link on it whose path is
    /// the longest proper prefix of its own (`/story/12/a-b/chapter/3/c` →
    /// `/story/12/a-b`). The site's root is not one. That page is not followed further.
    private static func parentURL(of page: LinkPage) -> URL? {
        guard case .page(let links, _, _) = page.body else { return nil }
        return links
            .filter { isAncestor($0.url, of: page.url) }
            .max { pathParts($0.url).count < pathParts($1.url).count }?.url
    }

    private static func pathParts(_ url: URL) -> [String] { url.pathComponents.filter { $0 != "/" } }

    /// `url` is on `page`'s site and its path is a non-empty proper prefix of the page's.
    private static func isAncestor(_ url: URL, of page: URL) -> Bool {
        let parts = pathParts(url), own = pathParts(page)
        return sameSite(url, page) && !parts.isEmpty && parts.count < own.count && own.starts(with: parts)
    }
}
