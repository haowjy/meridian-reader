import Foundation

/// ☆ (*Add to Favorites* in the browser's and the Reader's ⋯) and filing pages into folders from
/// there. One tap adds a page at the end of Favorites, and a toast offers *Change Folder* (the
/// Move tree). One page per address: a page filed in another folder asks before it moves, and a
/// chapter of a book or series offers to move the book instead. ☆ on a favorite removes it.
@MainActor
struct FavoriteFlow {
    let library: LibraryStore
    let shell: ShellState

    /// ☆ on the page at `url`. A new favorite without a tile-sized icon then asks `betterIcon`
    /// for one.
    func toggle(url: URL, title: String?, artwork: Data?, betterIcon: @escaping () async -> Data?) {
        guard LibraryStore.canFavorite(url) else { return }
        switch library.favoriteRequest(for: url) {
        case .add:
            add(url: url, title: title, artwork: artwork, betterIcon: betterIcon)
        case .remove(let page):
            library.removeFavorite(page)
            shell.showToast(ShellToast(message: String(localized: "Removed from Favorites"), systemImage: "star.slash"))
        case .moveFromFolder(let page, let folder):
            shell.prompt = ShellPrompt(
                title: String(localized: "Move it to Favorites?"),
                message: "“\(page.title)” is in “\(folder.displayName)”. A page is kept in one folder.",
                confirmTitle: String(localized: "Move to Favorites")) {
                    add(url: url, title: title, artwork: artwork, betterIcon: betterIcon)
                }
        case .moveBook(let book):
            let isSeries = book.kind == .series
            shell.prompt = ShellPrompt(
                title: isSeries ? String(localized: "Move Series to Favorites?") : String(localized: "Move Book to Favorites?"),
                message: "This page is a chapter of “\(book.displayName)”, and chapters stay in their \(isSeries ? "series" : "book").",
                confirmTitle: isSeries ? String(localized: "Move Series") : String(localized: "Move Book")) {
                    try? library.move([.folder(book)], to: library.favorites())
                    shell.showToast(ShellToast(message: "“\(book.displayName)” is in Favorites", systemImage: "star.fill"))
                }
        }
    }

    /// Saves `article` into a folder picked in the Move tree (*Save to Library…*, 🔖's *Save to
    /// Folder…*): a saved page moves there, an unsaved one is saved there. "Library (no
    /// folder)" saves it, or takes it out of its folder.
    func saveToFolder(title: String, current: MoveRequest.Place?, save: @escaping (Folder?) -> Void) {
        shell.present(.moveTo(MoveRequest(title: title, current: current, onPick: save)))
    }

    private func add(url: URL, title: String?, artwork: Data?, betterIcon: @escaping () async -> Data?) {
        guard let page = library.addFavorite(url: url, title: title, artwork: artwork) else { return }
        let library = library
        let shell = shell
        shell.showToast(ShellToast(message: String(localized: "Added to Favorites"), systemImage: "star.fill",
                                   actionTitle: String(localized: "Change Folder")) {
            shell.present(.moveTo(MoveRequest(title: String(localized: "Change Folder"),
                                              current: page.folder.map { .folder($0.id) }) { destination in
                try? library.move([.page(page)], to: destination)
            }))
        })
        guard !FaviconFetcher.isTileSized(page.artworkData) else { return }
        Task {
            if let icon = await betterIcon() { library.offerArtwork(icon, for: page) }
        }
    }
}
