import Foundation

/// ☆ (*Add to Favorites* in the browser's and the Reader's ⋯) and filing pages into folders from
/// there. One tap adds a page at the end of Favorites, and a toast offers *Change Folder* (the
/// Move tree). One page per address: a page filed in another folder (a series' chapter too) asks
/// before it moves. ☆ on a favorite removes it. A change that can't be saved changes
/// nothing, and its toast says so instead.
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
            guard shell.attempt(String(localized: "Couldn’t remove from Favorites"), { try library.removeFavorite(page) }) != nil
            else { return }
            shell.showToast(ShellToast(message: String(localized: "Removed from Favorites"), systemImage: "star.slash"))
        case .moveFromFolder(let page, let folder):
            shell.prompt = ShellPrompt(
                title: String(localized: "Move it to Favorites?"),
                message: "“\(page.title)” is in “\(folder.displayName)”. A page is kept in one folder.",
                confirmTitle: String(localized: "Move to Favorites")) {
                    add(url: url, title: title, artwork: artwork, betterIcon: betterIcon)
                }
        }
    }

    /// Saves `article` into a folder picked in the Move tree (*Save to Library…*, 🔖's *Save to
    /// Folder…*): a saved page moves there, an unsaved one is saved there. "Library (no
    /// folder)" (nil) files it in no folder, out of the one it was in (a link in Favorites
    /// leaves it); `save` passes it on as `SavePlacement.folder`, and returns false when that
    /// couldn't be saved (the tree stays up).
    func saveToFolder(title: String, current: MoveRequest.Place?, save: @escaping (Folder?) -> Bool) {
        shell.present(.moveTo(MoveRequest(title: title, current: current, onPick: save)))
    }

    private func add(url: URL, title: String?, artwork: Data?, betterIcon: @escaping () async -> Data?) {
        let library = library
        let shell = shell
        guard let page = shell.attempt(String(localized: "Couldn’t add to Favorites"), {
            try library.addFavorite(url: url, title: title, artwork: artwork)
        }) else { return }
        shell.showToast(ShellToast(message: String(localized: "Added to Favorites"), systemImage: "star.fill",
                                   actionTitle: String(localized: "Change Folder")) {
            shell.present(.moveTo(MoveRequest(title: String(localized: "Change Folder"),
                                              current: page.folder.map { .folder($0.id) }) { destination in
                shell.attempt(String(localized: "Couldn’t move")) { try library.move([.page(page)], to: destination) } != nil
            }))
        })
        guard !FaviconFetcher.isTileSized(page.artworkData) else { return }
        Task {
            if let icon = await betterIcon() { library.offerArtwork(icon, for: page) }
        }
    }
}
