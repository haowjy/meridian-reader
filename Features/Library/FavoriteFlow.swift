import Foundation

/// ☆ (*Add to Favorites* in the browser's, the Reader's and Now Playing's ⋯, and in a Library
/// row's menu) sets an independent favorite flag. It never changes the page's location. One page
/// per address: ☆ on a favorite clears the flag. Every ☆ says what it did in a toast, and a new
/// favorite without a tile-sized icon then looks for one. A change that can't be saved changes
/// nothing, and its toast says so instead.
@MainActor
struct FavoriteFlow {
    let library: LibraryStore
    let shell: ShellState

    /// ☆ on the page at `url`, whether a page for it exists yet or not. A new favorite without a
    /// tile-sized icon then asks `betterIcon` for one.
    func toggle(url: URL, title: String?, artwork: Data?, betterIcon: @escaping () async -> Data?) {
        guard LibraryStore.canFavorite(url) else { return }
        if let page = library.favorite(for: url) {
            remove(page)
        } else {
            add(betterIcon: betterIcon) { try library.addFavorite(url: url, title: title, artwork: artwork) }
        }
    }

    /// ☆ in a Library row's menu: a page in the Library (a chapter too) or with a web address
    /// (`LibraryStore.canFavorite(_:)`). A web page without a tile-sized icon gets its site's.
    func toggle(_ page: Page) {
        guard LibraryStore.canFavorite(page) else { return }
        if LibraryStore.isFavorite(page) {
            remove(page)
            return
        }
        let site = page.url.flatMap { LibraryStore.canFavorite($0) ? $0 : nil }
        add(betterIcon: site.map { url in { await FaviconFetcher.best(for: url, webView: nil) } }) { [library] in
            try library.addFavorite(page)
            return page
        }
    }

    /// Saves `article` into a folder picked in the Move tree (*Save to Library…*, 🔖's *Save to
    /// Folder…*): a saved page moves there, an unsaved one is saved there. "Library (no
    /// folder)" (nil) files it in no folder, out of the one it was in; `save` passes it on as
    /// `SavePlacement.folder`, and returns false when that couldn't be saved (the tree stays up).
    func saveToFolder(title: String, current: MoveRequest.Place?, save: @escaping (Folder?) -> Bool) {
        shell.present(.moveTo(MoveRequest(title: title, current: current, onPick: save)))
    }

    private func remove(_ page: Page) {
        guard shell.attempt(String(localized: "Couldn’t remove from Favorites"), { try library.removeFavorite(page) }) != nil
        else { return }
        shell.showToast(ShellToast(message: String(localized: "Removed from Favorites"), systemImage: Icons.unfavorite))
    }

    private func add(betterIcon: (() async -> Data?)?, _ star: () throws -> Page) {
        guard let page = shell.attempt(String(localized: "Couldn’t add to Favorites"), star) else { return }
        shell.showToast(ShellToast(message: String(localized: "Added to Favorites"), systemImage: Icons.favorited))
        guard let betterIcon, !FaviconFetcher.isTileSized(page.artworkData) else { return }
        let library = library
        Task {
            if let icon = await betterIcon() { library.offerArtwork(icon, for: page) }
        }
    }
}
