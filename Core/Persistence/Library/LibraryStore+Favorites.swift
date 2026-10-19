import Foundation
import SwiftData

/// Favorites are flags on pages and folders, independent of their location and of the Library: a
/// starred page is in Favorites whether it is in the Library or not (`LibraryQueries.favoritePages`),
/// and the prune keeps it. Removing one from the Library keeps its flag and its place in
/// Favorites; only unstarring clears it. Adding, removing and renaming a favorite save at once; a
/// save that fails is rolled back and throws `LibraryStoreError.saveFailed`.
extension LibraryStore {
    /// Favorite pages anywhere in the tree (a predicate fetch: only they are read).
    func favoritePages() -> [Page] {
        (try? context.fetch(LibraryQueries.favoritePages)) ?? []
    }

    /// The page for `url` when it is a favorite.
    func favorite(for url: URL?) -> Page? {
        guard let url, Self.canFavorite(url), let page = page(url: url), page.isFavorite else { return nil }
        return page
    }

    /// A web page's address can be starred, whether a page for it exists yet or not.
    static func canFavorite(_ url: URL) -> Bool {
        url.isWebOrTestPage
    }

    /// A page's ☆ applies when it is in the Library (a book's chapter too, which has no web
    /// address), has a web address, or is starred already (a removed chapter can be unstarred).
    static func canFavorite(_ page: Page) -> Bool {
        page.isFavorite || page.isInLibrary || page.url.map(canFavorite) == true
    }

    /// Makes the page for `url` a favorite without moving it: the existing page as
    /// `addFavorite(_:artwork:)` does, or a new link page in no folder, made and starred in one
    /// save.
    @discardableResult
    func addFavorite(url: URL, title: String?, artwork: Data?) throws -> Page {
        if let existing = page(url: url) {
            try addFavorite(existing, artwork: artwork)
            return existing
        }
        let canonical = ArticleIdentity.canonicalURLString(from: url)
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return try edit("favorite link") {
            let page = Page(key: ArticleIdentity.articleKey(canonicalURL: canonical), title: trimmed,
                            byline: url.host ?? url.absoluteString, urlString: url.absoluteString, contentState: .link, addedAt: now(),
                            sortKey: nextSortKey(in: nil), artworkData: artwork)
            page.isFavorite = true
            context.insert(page)
            return page
        }
    }

    /// Stars `page` where it is, in the Library or not, taking `artwork` as its icon when it has
    /// none. Starring never files it: a page played without saving stays *Not saved* and joins
    /// Favorites, which keeps it from the prune.
    func addFavorite(_ page: Page, artwork: Data? = nil) throws {
        try edit("favorite") {
            page.isFavorite = true
            if page.artworkData == nil { page.artworkData = artwork }
        }
    }

    /// Removes only the favorite flag; location and content stay intact (a link ☆ made stays in
    /// the Library). A page out of the Library is then in no list, and the prune deletes it on
    /// its schedule.
    func removeFavorite(_ page: Page) throws {
        guard page.isFavorite else { return }
        try edit("unfavorite page") { page.isFavorite = false }
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
                    for page in legacy.pages ?? [] {
                        page.isFavorite = true
                        page.sortKey = nextSortKey(in: nil)
                        page.setFolder(nil)
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

    func renameFavorite(_ page: Page, to title: String) throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try edit("rename favorite") { page.title = trimmed }
    }

    /// Takes `data` as the page's icon unless it would replace a usable icon with a smaller one
    /// (tiny 16 px favicons look smeared on a tile).
    func offerArtwork(_ data: Data, for page: Page) {
        guard page.artworkData == nil || FaviconFetcher.isTileSized(data) else { return }
        page.artworkData = data
        commit("artwork")
    }

    /// Favorites without a tile-sized icon: try the site's icon once per launch. Fetches run
    /// concurrently; a page only counts as tried once its fetch finished, so a cancelled pass
    /// retries next time.
    func backfillFavoriteIcons() async {
        let pending = favoritePages().filter {
            !FaviconFetcher.isTileSized($0.artworkData) && $0.key.map { !iconTried.contains($0) } == true
        }
        guard !pending.isEmpty else { return }
        await withTaskGroup(of: (UUID, Data?).self) { group in
            for page in pending {
                // A chapter (no web address) has no site to ask.
                guard let key = page.key, let host = page.url?.host else { continue }
                group.addTask { (key, await FaviconFetcher.fetch(forHost: host)) }
            }
            for await (key, icon) in group {
                guard !Task.isCancelled else { return }
                iconTried.insert(key)
                if let icon, let page = page(key: key) { offerArtwork(icon, for: page) }
            }
        }
    }
}
