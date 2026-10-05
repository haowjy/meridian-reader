import Foundation
import SwiftData

/// Favorites: the top-level folder that holds what used to be site bookmarks. A favorite is a
/// page in it: a link, or a saved page (one page per address, so bookmarking a saved page files
/// it there). The start page shows its pages as the icon grid.
extension LibraryStore {
    /// Favorites' pages in their order.
    func favoritePages() -> [Page] {
        pages(in: favorites())
    }

    /// The page for `url` when it is a favorite.
    func favorite(for url: URL?) -> Page? {
        guard let url, Self.canFavorite(url), let page = page(url: url), page.folder?.kind == .favorites else { return nil }
        return page
    }

    static func canFavorite(_ url: URL) -> Bool {
        url.isWebOrTestPage
    }

    /// ⋯ → Bookmark / Remove Bookmark. A new favorite without a tile-sized icon then asks
    /// `betterIcon` for one.
    func toggleFavorite(url: URL, title: String?, artwork: Data?, betterIcon: () async -> Data?) async {
        guard Self.canFavorite(url) else { return }
        if let existing = favorite(for: url) {
            removeFavorite(existing)
            return
        }
        guard let added = addFavorite(url: url, title: title, artwork: artwork),
              !FaviconFetcher.isTileSized(added.artworkData), let icon = await betterIcon() else { return }
        offerArtwork(icon, for: added)
    }

    /// Makes the page for `url` a favorite, at the end of Favorites: a new link page, or the
    /// existing page filed there. A page played but not saved becomes a link (Favorites doesn't
    /// save). A chapter of a book or series stays where it is (nil).
    @discardableResult
    func addFavorite(url: URL, title: String?, artwork: Data?) -> Page? {
        let folder = favorites()
        guard let existing = page(url: url) else {
            return addLink(url: url, title: title, artwork: artwork, in: folder)
        }
        guard !existing.isInFixedFolder else { return nil }
        if existing.folder !== folder {
            if existing.addedAt == nil {
                existing.contentState = .link
                existing.addedAt = now()
            }
            existing.sortKey = nextSortKey(in: folder)
            existing.setFolder(folder)
        }
        if existing.artworkData == nil { existing.artworkData = artwork }
        commit("favorite")
        return existing
    }

    /// No longer a favorite: a saved page goes back to the pages in no folder, still saved; a
    /// link page is removed.
    func removeFavorite(_ page: Page) {
        guard page.folder?.kind == .favorites else { return }
        if page.isSaved {
            page.sortKey = nextSortKey(in: nil)
            page.setFolder(nil)
            commit("unfavorite saved page")
        } else {
            remove(page)
        }
    }

    func renameFavorite(_ page: Page, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        page.title = trimmed
        commit("rename favorite")
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
