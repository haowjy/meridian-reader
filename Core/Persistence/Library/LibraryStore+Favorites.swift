import Foundation
import SwiftData

/// What ☆ on a page leads to (`LibraryStore.favoriteRequest`).
enum FavoriteRequest {
    /// Not a favorite yet: one tap sets its independent flag.
    case add
    /// Already a favorite: ☆ clears its independent flag.
    case remove(Page)
}

/// Favorites are flags on pages and folders, independent of their location. A favorite page is
/// in the Library (`isFavorite(_:)`, `LibraryQueries.favoritePages`): starring a page that isn't
/// puts it there, and removing one from the Library clears its flag. Adding, removing and
/// renaming a favorite save at once; a save that fails is rolled back and throws
/// `LibraryStoreError.saveFailed`.
extension LibraryStore {
    /// Favorite pages anywhere in the tree (a predicate fetch: only they are read).
    func favoritePages() -> [Page] {
        (try? context.fetch(LibraryQueries.favoritePages)) ?? []
    }

    /// The page for `url` when it is a favorite.
    func favorite(for url: URL?) -> Page? {
        guard let url, Self.canFavorite(url), let page = page(url: url), Self.isFavorite(page) else { return nil }
        return page
    }

    /// Starred and in the Library: what the Favorites tab lists and ☆ shows filled.
    static func isFavorite(_ page: Page) -> Bool {
        page.isFavorite && page.isInLibrary
    }

    /// What ☆ on the page at `url` leads to. Its tree location never changes.
    func favoriteRequest(for url: URL) -> FavoriteRequest {
        guard let existing = page(url: url) else { return .add }
        if Self.isFavorite(existing) { return .remove(existing) }
        return .add
    }

    static func canFavorite(_ url: URL) -> Bool {
        url.isWebOrTestPage
    }

    /// ⋯ → Add / Remove from Favorites. A new favorite without a tile-sized icon then asks
    /// `betterIcon` for one.
    func toggleFavorite(url: URL, title: String?, artwork: Data?, betterIcon: () async -> Data?) async throws {
        guard Self.canFavorite(url) else { return }
        if let existing = favorite(for: url) {
            try removeFavorite(existing)
            return
        }
        let added = try addFavorite(url: url, title: title, artwork: artwork)
        guard !FaviconFetcher.isTileSized(added.artworkData), let icon = await betterIcon() else { return }
        offerArtwork(icon, for: added)
    }

    /// Makes the page for `url` a favorite without moving it: a new link page is loose, or the
    /// existing page retains its location. A page that isn't in the Library (played without
    /// saving) joins it where it is, at the end, with its played text: the Favorites tab lists
    /// it and the 7-day prune of unsaved pages leaves it alone. Its audio is marked saved once
    /// that is stored, as a Save does.
    @discardableResult
    func addFavorite(url: URL, title: String?, artwork: Data?) throws -> Page {
        guard let existing = page(url: url) else {
            let added = try addLink(url: url, title: title, artwork: artwork, in: nil)
            try edit("favorite page") { added.isFavorite = true }
            return added
        }
        try edit("favorite") {
            existing.isFavorite = true
            if existing.artworkData == nil { existing.artworkData = artwork }
            if existing.addedAt == nil {
                existing.sortKey = nextSortKey(in: existing.folder)
                existing.addedAt = now()
                if existing.isSaved, let key = existing.key { planSaved(key: key) }
            }
        }
        return existing
    }

    /// Removes only the favorite flag; location and content stay intact (a link ☆ made stays in
    /// the Library).
    func removeFavorite(_ page: Page) throws {
        guard page.isFavorite else { return }
        try edit("unfavorite page") { page.isFavorite = false }
    }

    func toggleFavorite(_ folder: Folder) throws {
        try edit("toggle favorite folder") { folder.isFavorite.toggle() }
    }

    /// Converts the old pinned Favorites folder once. Children keep their structure; direct
    /// pages become loose at the root. The folder is deleted only in the same saved edit.
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
                        markFavorite(folder)
                    }
                    context.delete(legacy)
                }
            }
        } catch {
            log("favorites migration failed; original folder remains: \(error)")
        }
    }

    private func markFavorite(_ folder: Folder) {
        folder.isFavorite = true
        for page in folder.pages ?? [] { page.isFavorite = true }
        for child in folder.children ?? [] { markFavorite(child) }
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
                guard let key = page.key else { continue }
                let host = page.byline
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
