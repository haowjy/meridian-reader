import Foundation

/// ☆ (*Add to Favorites* in the browser's and the Reader's ⋯) and filing pages into folders from
/// there. One tap adds a page at the end of Favorites, and a toast offers *Change Folder* (the
/// Move tree). One page per address: a page filed in another folder asks before it moves, and a
/// chapter of a book or series offers to move the book instead (into Favorites, or out of it
/// when the book is there). ☆ on a favorite removes it. A change that can't be saved changes
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
        case .moveBook(let book):
            let isSeries = book.kind == .series
            shell.prompt = ShellPrompt(
                title: isSeries ? String(localized: "Move Series to Favorites?") : String(localized: "Move Book to Favorites?"),
                message: "This page is a chapter of “\(book.displayName)”, and chapters stay in their \(isSeries ? "series" : "book").",
                confirmTitle: isSeries ? String(localized: "Move Series") : String(localized: "Move Book")) {
                    guard shell.attempt(String(localized: "Couldn’t move"), {
                        try library.move([.folder(book)], to: library.favorites())
                    }) != nil else { return }
                    shell.showToast(ShellToast(message: "“\(book.displayName)” is in Favorites", systemImage: "star.fill"))
                }
        case .moveBookOut(let book):
            let isSeries = book.kind == .series
            shell.prompt = ShellPrompt(
                title: isSeries ? String(localized: "Take Series out of Favorites?") : String(localized: "Take Book out of Favorites?"),
                message: "This page is a chapter of “\(book.displayName)”, which is in Favorites. Chapters stay in their \(isSeries ? "series" : "book"), so the whole \(isSeries ? "series" : "book") moves to the Library’s top level.",
                confirmTitle: isSeries ? String(localized: "Move Series Out") : String(localized: "Move Book Out")) {
                    guard shell.attempt(String(localized: "Couldn’t move"), { try library.move([.folder(book)], to: nil) }) != nil
                    else { return }
                    shell.showToast(ShellToast(message: "“\(book.displayName)” is out of Favorites", systemImage: "star.slash"))
                }
        }
    }

    /// Saves `article` into a folder picked in the Move tree (*Save to Library…*, 🔖's *Save to
    /// Folder…*): a saved page moves there, an unsaved one is saved there. "Library (no
    /// folder)" (nil) files it in no folder, out of the one it was in (a link in Favorites
    /// leaves it); `save` passes it on as `SavePlacement.folder`.
    func saveToFolder(title: String, current: MoveRequest.Place?, save: @escaping (Folder?) -> Void) {
        shell.present(.moveTo(MoveRequest(title: title, current: current, onPick: save)))
    }

    private func add(url: URL, title: String?, artwork: Data?, betterIcon: @escaping () async -> Data?) {
        let library = library
        let shell = shell
        guard let added = shell.attempt(String(localized: "Couldn’t add to Favorites"), {
            try library.addFavorite(url: url, title: title, artwork: artwork)
        }), let page = added else { return }
        shell.showToast(ShellToast(message: String(localized: "Added to Favorites"), systemImage: "star.fill",
                                   actionTitle: String(localized: "Change Folder")) {
            shell.present(.moveTo(MoveRequest(title: String(localized: "Change Folder"),
                                              current: page.folder.map { .folder($0.id) }) { destination in
                shell.attempt(String(localized: "Couldn’t move")) { try library.move([.page(page)], to: destination) }
            }))
        })
        guard !FaviconFetcher.isTileSized(page.artworkData) else { return }
        Task {
            if let icon = await betterIcon() { library.offerArtwork(icon, for: page) }
        }
    }
}
