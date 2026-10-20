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

    /// Saves a page played without saving into the Library's top level (starring or downloading
    /// it, C104); a page in the Library stays where it is. Inside an `edit`.
    func fileIfUnsaved(_ article: Article) {
        guard article.addedAt == nil else { return }
        article.addedAt = now()
        article.removedAt = nil
        article.sortKey = nextSortKey(in: nil)
    }

    /// `fileIfUnsaved` as its own change (*Download* on a page played without saving).
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
