import Foundation
import SwiftData

/// What ☆ on a page leads to (`LibraryStore.favoriteRequest`).
enum FavoriteRequest {
    /// Not a favorite yet: one tap adds it at the end of Favorites.
    case add
    /// Already a favorite: ☆ takes it out.
    case remove(Page)
    /// Filed in another folder (a series' chapter too): ask *Move it to Favorites?*
    case moveFromFolder(Page, Folder)
}

/// Favorites are flags on pages and folders, independent of their location. Adding, removing and
/// renaming a favorite save at once; a save that fails is rolled back and throws
/// `LibraryStoreError.saveFailed`.
extension LibraryStore {
    /// Favorite pages anywhere in the tree.
    func favoritePages() -> [Page] {
        ((try? context.fetch(FetchDescriptor<Page>())) ?? []).filter(\.isFavorite)
    }

    /// The page for `url` when it is a favorite: in Favorites or one of its subfolders.
    func favorite(for url: URL?) -> Page? {
        guard let url, Self.canFavorite(url), let page = page(url: url), Self.isFavorite(page) else { return nil }
        return page
    }

    /// In Favorites or one of its subfolders.
    static func isFavorite(_ page: Page) -> Bool {
        return page.isFavorite
    }

    /// What ☆ on the page at `url` leads to. One page per address: a page filed in another folder
    /// moves to Favorites only once you agree.
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
    /// existing page retains its location.
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
        }
        return existing
    }

    /// Removes only the favorite flag; location and content stay intact.
    func removeFavorite(_ page: Page) throws {
        guard Self.isFavorite(page) else { return }
        try edit("unfavorite page") { page.isFavorite = false }
    }

    func toggleFavorite(_ folder: Folder) throws {
        try edit("toggle favorite folder") { folder.isFavorite.toggle() }
    }

    /// Converts the old pinned Favorites folder once. Children keep their structure; direct
    /// pages become loose at the root. The folder is deleted only in the same saved edit.
    func migrateFavoritesFolder() {
        guard let legacy = (try? context.fetch(LibraryQueries.favorites).first) else { return }
        do {
            try edit("migrate favorites folder") {
                legacy.isFavorite = false
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
