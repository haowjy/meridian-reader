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

    /// Where the page ended up, after redirects.
    var url: URL
    /// The document's title.
    var title: String?
    /// The first heading (`h1`).
    var heading: String?
    /// The author, when the page names one (a meta tag, a story's author link).
    var author: String?
    /// The site's own name for itself (`og:site_name`).
    var siteName: String?
    /// The page is a feed document (RSS or Atom); its links are the entries, newest first or as
    /// the feed gives them.
    var isFeed = false
    /// The feeds the page advertises (`<link rel="alternate">`), comment feeds left out.
    var feeds: [URL] = []
    var links: [Link]
}

/// What a page lists to follow, read by `read(_:fetch:)` from the page's links. A site is read by
/// the first rule that finds a list, in this order (`readers`):
/// 1. **The page's list of links**: the list holding the most chapter-like and dated links.
/// 2. **The page it belongs to**, when it lists nothing itself (a chapter or a post): the link on
///    it whose path is the longest proper prefix of its own, read as 1 and 3 would. One more fetch.
/// 3. **A feed**, the page's own or one it advertises (RSS 2.0, Atom): titles, dates, order.
///
/// A feed comes last because it is a window of the latest entries (a serial's feed holds its last
/// ten chapters), where a page's list is whole; a page with no list is where a feed is best.
///
/// **Posts or chapters** (`Kind`): a feed, or a list whose dates run newest first, is *Posts*,
/// newest first. Any other list is *Chapters*, in the page's order.
struct TableOfContents: Equatable, Sendable {
    struct Chapter: Equatable, Hashable, Sendable {
        var title: String
        var url: URL
        /// When it was published, when the page or feed says.
        var date: Date?

        /// The address one page per canonical URL goes by (`ArticleIdentity`).
        var canonicalURL: String { ArticleIdentity.canonicalURLString(from: url) }
    }

    enum Kind: Equatable, Sendable {
        /// A blog or newsletter: dated, newest first.
        case posts
        /// A serial: in the page's order.
        case chapters
    }

    /// The page or feed the list was read from; a check reads it again.
    var url: URL
    var title: String
    var byline: String?
    /// The site's name in notices: `og:site_name`, else its host without "www.".
    var siteName: String
    var kind: Kind
    var chapters: [Chapter]

    /// Fetches another page's links, through the fetch queue.
    typealias Fetch = @MainActor (URL) async throws -> LinkPage

    private static let listReaders: [any ContentsReader] = [Generic(), Feed()]
    private static let readers: [any ContentsReader] = [Generic(), Parent(), Feed()]

    /// What `page` lists to follow; nil when nothing can be found on it.
    static func read(_ page: LinkPage, fetch: Fetch) async throws -> TableOfContents? {
        try await read(page, fetch: fetch, using: readers)
    }

    fileprivate static func read(_ page: LinkPage, fetch: Fetch, using readers: [any ContentsReader]) async throws -> TableOfContents? {
        for reader in readers {
            if let contents = try await reader.contents(on: page, fetch: fetch) { return contents }
        }
        return nil
    }

    /// The host without a leading "www.": a site's name when it gives none.
    static func siteName(of url: URL) -> String {
        let host = url.host?.lowercased() ?? ""
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// The contents `chapters` make, read from `page` (its heading or title names it); the site's
    /// name is `siteName`, else the page's.
    fileprivate static func make(_ page: LinkPage, siteName: String? = nil, chapters: [Chapter], kind: Kind) -> TableOfContents? {
        guard !chapters.isEmpty else { return nil }
        let title = [page.heading, page.title.map(Self.siteNameRemoved)].compactMap { $0 }.first { !$0.isEmpty }
        let byline = page.author.map(Self.squeezed).flatMap { $0.isEmpty ? nil : $0 }
        let site = [siteName, page.siteName].compactMap { $0 }.map(squeezed).first { !$0.isEmpty }
        return TableOfContents(url: page.url, title: title ?? page.url.host ?? page.url.absoluteString, byline: byline,
                               siteName: site ?? Self.siteName(of: page.url), kind: kind, chapters: chapters)
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
    fileprivate static func unique(_ links: [LinkPage.Link]) -> [Chapter] {
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

    fileprivate static func sameSite(_ a: URL, _ b: URL) -> Bool {
        guard a.scheme == b.scheme || (a.scheme?.hasPrefix("http") == true && b.scheme?.hasPrefix("http") == true)
        else { return false }
        return siteName(of: a) == siteName(of: b)
    }

    // MARK: - A feed

    /// The page's own feed document, else the first feed it advertises (one more fetch). Entries
    /// are *Posts*, newest first by date; a feed with no dates keeps its own order.
    private struct Feed: ContentsReader {
        func contents(on page: LinkPage, fetch: Fetch) async throws -> TableOfContents? {
            let feed: LinkPage
            if page.isFeed {
                feed = page
            } else if let url = page.feeds.first {
                feed = try await fetch(url)
                guard feed.isFeed else { return nil }
            } else {
                return nil
            }
            let entries = unique(feed.links).sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            return make(feed, siteName: page.siteName, chapters: entries, kind: .posts)
        }
    }

    // MARK: - The page's list

    /// The list on the page with the highest score, on the page's own site. A link counts for
    /// itself; one that reads as a chapter ("Chapter 3", "Ch. 3", "Part Two", "Episode 4",
    /// "Prologue", "12. Title") or has a date counts three times; links sharing one path shape
    /// (`shape`: `/story/#/*/chapter/#/*`) add the size of the largest such group. A list needs
    /// three links, at least half of them chapter-like or dated, so a chapter's previous and next
    /// links, a site's menu or a blog's archive with a "Part 2" here and there are not a list. Links to the page itself are left out.
    private struct Generic: ContentsReader {
        func contents(on page: LinkPage, fetch: Fetch) async -> TableOfContents? {
            let here = ArticleIdentity.canonicalURLString(from: page.url)
            let candidates = page.links.filter { link in
                sameSite(link.url, page.url) && ArticleIdentity.canonicalURLString(from: link.url) != here
                    && !squeezed(link.text).isEmpty
            }
            var best: (list: Int, score: Int)?
            for (list, links) in Dictionary(grouping: candidates, by: \.list) {
                let signalled = links.filter { isChapterLike($0) || $0.date != nil }.count
                guard links.count >= 3, signalled >= 2, 2 * signalled >= links.count else { continue }
                let sharedShape = Dictionary(grouping: links, by: { Self.shape(of: $0.url) }).values.map(\.count).max() ?? 0
                let score = links.count + 2 * signalled + sharedShape
                if best == nil || score > best!.score || (score == best!.score && list < best!.list) {
                    best = (list, score)
                }
            }
            guard let best else { return nil }
            let chapters = unique(candidates.filter { $0.list == best.list })
            let dates = chapters.compactMap(\.date)
            let newestFirst = dates.count >= 2 && dates.first! > dates.last!
            return make(page, chapters: chapters, kind: newestFirst ? .posts : .chapters)
        }

        /// The path with numbers as `#` and the last part as `*`: `/story/12/a-b/chapter/3/c-d`
        /// and `/story/12/a-b/chapter/4/e` are one shape.
        static func shape(of url: URL) -> String {
            let parts = url.pathComponents.filter { $0 != "/" }
            return parts.enumerated().map { index, part in
                index == parts.count - 1 ? "*" : (Int(part) != nil ? "#" : part)
            }.joined(separator: "/")
        }

        func isChapterLike(_ link: LinkPage.Link) -> Bool {
            let text = link.text.lowercased()
            let path = link.url.path.lowercased()
            if text.contains(/\b(chapter|part|episode|prologue|epilogue|interlude|book)\b|\bch\./) || path.contains("chapter") {
                return true
            }
            return text.wholeMatch(of: /\d+\s*[.:)\-–—].*/) != nil
        }
    }

    // MARK: - The page it belongs to

    /// A page with no list of its own (a chapter, a post) leads to its story or blog: the link on
    /// it whose path is the longest proper prefix of its own (`/fiction/12/a-b/chapter/3/c` →
    /// `/fiction/12/a-b`). The site's root is not one. That page is read by the feed and list
    /// readers; it is not followed further.
    private struct Parent: ContentsReader {
        func contents(on page: LinkPage, fetch: Fetch) async throws -> TableOfContents? {
            let own = page.url.pathComponents.filter { $0 != "/" }
            let parent = page.links
                .filter { sameSite($0.url, page.url) }
                .map { (url: $0.url, parts: $0.url.pathComponents.filter { $0 != "/" }) }
                .filter { !$0.parts.isEmpty && $0.parts.count < own.count && own.starts(with: $0.parts) }
                .max { $0.parts.count < $1.parts.count }
            guard let parent else { return nil }
            return try await TableOfContents.read(try await fetch(parent.url), fetch: fetch, using: listReaders)
        }
    }
}

/// One rule for reading a page (`TableOfContents.readers`): the contents it lists, nil when it
/// lists none.
private protocol ContentsReader: Sendable {
    func contents(on page: LinkPage, fetch: TableOfContents.Fetch) async throws -> TableOfContents?
}
