import Foundation

/// ☆ (*Add to Favorites* in the browser's, the Reader's and Now Playing's ⋯, and in a page's or a
/// folder's row menu in the Library) sets an independent favorite flag. It never changes where
/// the page or folder is. One page per address: ☆ on a favorite clears the flag. Every ☆ says what it did in a toast, and a new
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
        if let article = library.favorite(for: url) {
            remove(article)
        } else {
            add(betterIcon: betterIcon) { try library.addFavorite(url: url, title: title, artwork: artwork) }
        }
    }

    /// ☆ in a Library row's menu: a page in the Library (a chapter too) or with a web address
    /// (`LibraryStore.canFavorite(_:)`). A web page without a tile-sized icon gets its site's.
    func toggle(_ article: Article) {
        guard LibraryStore.canFavorite(article) else { return }
        if article.isFavorite {
            remove(article)
            return
        }
        let site = article.url.flatMap { LibraryStore.canFavorite($0) ? $0 : nil }
        add(betterIcon: site.map { url in { await FaviconFetcher.best(for: url, webView: nil) } }) { [library] in
            try library.addFavorite(article)
            return article
        }
    }

    /// ☆ in a folder row's menu (a book or series too).
    func toggle(_ folder: Folder) {
        let adding = !folder.isFavorite
        guard shell.attempt(failure(adding: adding), { try library.toggleFavorite(folder) }) != nil else { return }
        said(adding: adding)
    }

    private func remove(_ article: Article) {
        guard shell.attempt(failure(adding: false), { try library.removeFavorite(article) }) != nil else { return }
        said(adding: false)
    }

    private func add(betterIcon: (() async -> Data?)?, _ star: () throws -> Article) {
        guard let article = shell.attempt(failure(adding: true), star) else { return }
        said(adding: true)
        guard let betterIcon, !FaviconFetcher.isTileSized(article.artworkData) else { return }
        let library = library
        Task {
            if let icon = await betterIcon() { library.offerArtwork(icon, for: article) }
        }
    }

    private func failure(adding: Bool) -> String {
        adding ? String(localized: "Couldn’t add to Favorites") : String(localized: "Couldn’t remove from Favorites")
    }

    private func said(adding: Bool) {
        shell.showToast(adding
            ? ShellToast(message: String(localized: "Added to Favorites"), systemImage: Icons.favorited)
            : ShellToast(message: String(localized: "Removed from Favorites"), systemImage: Icons.unfavorite))
    }
}
