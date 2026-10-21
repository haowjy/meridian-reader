import Foundation
import SwiftData

/// Favorites are flags on pages and folders, independent of their location and of the Library: a
/// starred page is in Favorites whether it is in the Library or not (`LibraryQueries.favoriteArticles`),
/// and the prune keeps it. Removing one from the Library keeps its flag and its place in
/// Favorites; only unstarring clears it. Adding, removing and renaming a favorite save at once; a
/// save that fails is rolled back and throws `LibraryStoreError.saveFailed`.
extension LibraryStore {
    /// Favorite pages anywhere in the tree (a predicate fetch: only they are read).
    func favoriteArticles() -> [Article] {
        (try? context.fetch(LibraryQueries.favoriteArticles)) ?? []
    }

    /// The page for `url` when it is a favorite.
    func favorite(for url: URL?) -> Article? {
        guard let url, Self.canFavorite(url), let article = article(url: url), article.isFavorite else { return nil }
        return article
    }

    /// A web page's address can be starred, whether a page for it exists yet or not.
    static func canFavorite(_ url: URL) -> Bool {
        url.isWebOrTestPage
    }

    /// A page's ☆ applies when it is in the Library (a book's chapter too, which has no web
    /// address), has a web address, or is starred already (a removed chapter can be unstarred).
    static func canFavorite(_ article: Article) -> Bool {
        article.isFavorite || article.isInLibrary || article.url.map(canFavorite) == true
    }

    /// Makes the page for `url` a favorite without moving it: the existing page as
    /// `addFavorite(_:artwork:)` does, or a new link page in no folder, made and starred in one
    /// save.
    @discardableResult
    func addFavorite(url: URL, title: String?, artwork: Data?) throws -> Article {
        if let existing = article(url: url) {
            try addFavorite(existing, artwork: artwork)
            return existing
        }
        let canonical = ArticleIdentity.canonicalURLString(from: url)
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return try edit("favorite link") {
            let article = Article(key: ArticleIdentity.articleKey(canonicalURL: canonical), title: trimmed,
                            byline: url.host ?? url.absoluteString, urlString: url.absoluteString, contentState: .link, addedAt: now(),
                            sortKey: nextSortKey(in: nil), artworkData: artwork)
            article.isFavorite = true
            context.insert(article)
            return article
        }
    }

    /// Stars `article`, taking `artwork` as its icon when it has none. Favorites shows only what is in
    /// the Library (C104), so a page played without saving is saved with it, at the top level.
    func addFavorite(_ article: Article, artwork: Data? = nil) throws {
        try edit("favorite") {
            fileIfUnsaved(article)
            article.isFavorite = true
            if article.artworkData == nil { article.artworkData = artwork }
        }
    }

    /// Saves a page played without saving into the Library's top level (starring or preparing
    /// it, C104); a page in the Library stays where it is. Inside an `edit`.
    func fileIfUnsaved(_ article: Article) {
        guard article.addedAt == nil else { return }
        article.addedAt = now()
        article.removedAt = nil
        article.sortKey = nextSortKey(in: nil)
    }

    /// *Save from Website…* and *Paste* of an address (C126): the page for `url` saved in `folder`
    /// (nil: the top level), at its end. One the library has already moves there and is saved;
    /// a new one is a link page, whose text is fetched when it first plays or prepared audio.
    @discardableResult
    func saveLink(_ url: URL, in folder: Folder?) throws -> Article {
        let existing = article(url: url)
        let saved = try edit("save link") { () -> Article in
            if let existing {
                if existing.addedAt == nil || existing.folder !== folder {
                    existing.addedAt = existing.addedAt ?? now()
                    existing.removedAt = nil
                    existing.sortKey = nextSortKey(in: folder)
                    existing.setFolder(folder)
                }
                return existing
            }
            let canonical = ArticleIdentity.canonicalURLString(from: url)
            let article = Article(key: ArticleIdentity.articleKey(canonicalURL: canonical), title: "",
                                  byline: url.host ?? url.absoluteString, urlString: url.absoluteString,
                                  contentState: .link, addedAt: now(), sortKey: nextSortKey(in: folder))
            context.insert(article)
            article.setFolder(folder)
            return article
        }
        if let key = saved.key { plan(.saved, key: key) }
        return saved
    }

    /// *Paste Text…* (C127): a new article holding `text`, saved at the end of `folder` (nil: the
    /// top level). It has no web address (`ArticleOrigin.book`, locator "text:<key>"), so nothing
    /// ever refetches it; it reads, plays and prepared audio like any saved article.
    @discardableResult
    func saveText(title: String, text: String, in folder: Folder?) throws -> Article {
        let plain = text.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let blocks = plain.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let html = blocks.map { "<p>" + Self.escapedHTML($0) + "</p>" }.joined(separator: "\n")
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Self.defaultTitle(for: plain) : title
        let paragraphs = Article.buildListenDocument(plainText: blocks.joined(separator: "\n\n"), cleanedHTML: html, title: nil).paragraphs
        let saved = try edit("paste text") { () -> Article in
            let key = UUID()
            let article = Article(key: key, title: name, byline: String(localized: "Pasted text"), urlString: nil,
                                  contentState: .saved, addedAt: now(), sortKey: nextSortKey(in: folder))
            article.givenTitle = name
            article.locator = "text:\(key.uuidString)"
            article.setText(html: html, plain: blocks.joined(separator: "\n\n"), excerpt: String(plain.prefix(140)),
                            paragraphs: paragraphs)
            context.insert(article)
            article.setFolder(folder)
            return article
        }
        if let key = saved.key { plan(.saved, key: key) }
        return saved
    }

    /// A pasted text's title when none is typed: its first line, cut at its first sentence's end,
    /// at most 80 characters.
    nonisolated static func defaultTitle(for text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        var sentence = line
        if let end = line.firstIndex(where: { ".!?".contains($0) }), line.index(after: end) < line.endIndex {
            sentence = String(line[...end])
        }
        if sentence.count > 80 { sentence = String(sentence.prefix(79)).trimmingCharacters(in: .whitespaces) + "…" }
        return sentence.isEmpty ? String(localized: "Pasted Text") : sentence
    }

    nonisolated static func escapedHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// `fileIfUnsaved` as its own change (*Prepare* on a page played without saving).
    func saveUnsaved(_ article: Article) throws {
        guard article.addedAt == nil else { return }
        try edit("save to download") { fileIfUnsaved(article) }
    }

    /// Removes only the favorite flag; location and content stay intact (a link ☆ made stays in
    /// the Library). A page out of the Library is then in no list, and the prune deletes it on
    /// its schedule.
    func removeFavorite(_ article: Article) throws {
        guard article.isFavorite else { return }
        try edit("unfavorite page") { article.isFavorite = false }
    }

    func toggleFavorite(_ folder: Folder) throws {
        try edit("toggle favorite folder") { folder.isFavorite.toggle() }
    }

    /// Converts the legacy Favorites folder an older build left in the store (any number of
    /// copies, wherever they are) into stars, at launch: its direct children are starred, its
    /// pages loose at the top level and its subfolders moved to the top level with their contents
    /// as they were. What sits deeper isn't starred: a book's chapters would flood Favorites. The
    /// folder is deleted in the same saved edit.
    func migrateFavoritesFolder() {
        let legacyFolders = (try? context.fetch(LibraryQueries.favorites)) ?? []
        guard !legacyFolders.isEmpty else { return }
        do {
            try edit("migrate favorites folder") {
                for legacy in legacyFolders {
                    for article in legacy.articles ?? [] {
                        article.isFavorite = true
                        article.sortKey = nextSortKey(in: nil)
                        article.setFolder(nil)
                    }
                    for folder in legacy.children ?? [] {
                        folder.parent = nil
                        folder.isFavorite = true
                    }
                    context.delete(legacy)
                }
            }
        } catch {
            log("favorites migration failed; original folder remains: \(error)")
        }
    }

    /// Takes `data` as the page's icon unless it would replace a usable icon with a smaller one
    /// (tiny 16 px favicons look smeared on a tile).
    func offerArtwork(_ data: Data, for article: Article) {
        guard article.artworkData == nil || FaviconFetcher.isTileSized(data) else { return }
        article.artworkData = data
        commit("artwork")
    }

    /// Favorites without a tile-sized icon: try the site's icon once per launch. Fetches run
    /// concurrently; a page only counts as tried once its fetch finished, so a cancelled pass
    /// retries next time.
    func backfillFavoriteIcons() async {
        let pending = favoriteArticles().filter {
            !FaviconFetcher.isTileSized($0.artworkData) && $0.key.map { !iconTried.contains($0) } == true
        }
        guard !pending.isEmpty else { return }
        await withTaskGroup(of: (UUID, Data?).self) { group in
            for article in pending {
                // A chapter (no web address) has no site to ask.
                guard let key = article.key, let host = article.url?.host else { continue }
                group.addTask { (key, await FaviconFetcher.fetch(forHost: host)) }
            }
            for await (key, icon) in group {
                guard !Task.isCancelled else { return }
                iconTried.insert(key)
                if let icon, let article = article(key: key) { offerArtwork(icon, for: article) }
            }
        }
    }
}
