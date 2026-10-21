import SwiftUI

/// A folder's menu (a book or series as any other): the one definition its row's ⋯ and long press,
/// its header's *More* and its Favorites tile render (decisions C4, C98). Which options show
/// where, in what order and greyed or not is `MenuRegistry`'s (docs/MENUS.md); this gives each its
/// title, symbol and action. Built only when the menu opens: a row passes this view, never its
/// `rows`, so nothing here runs on a row's redraw.
///
/// The row's one download option: *Download* (the toggle off, nothing downloaded), *Turn Off
/// Download* (toggle on, still to finish), *Remove Downloads* (all downloaded, red). *Turn Off
/// Download* asks first (`onTurnOffDownload`, by the control the menu opened from), then turns it
/// off and keeps what is downloaded. *Remove Downloads* deletes its pages' audio and keeps them
/// out of its download (P8). *Edit Details…* holds the name too (no *Rename…*). Delete asks
/// through `LibraryScreenState`'s dialogs, which the screen hosts.
struct FolderMenu: View {
    enum Place {
        case row, tile, header
        var registryPlace: MenuRegistry.Place {
            switch self {
            case .row: .row
            case .tile: .tile
            case .header: .header
            }
        }
    }

    let folder: Folder
    /// Its pages in play order (what its row or screen already holds).
    let articles: [Article]
    let actions: LibraryActions
    let downloads: DownloadCenter
    let screen: LibraryScreenState
    var place: Place = .row
    /// What its row or header already computed; nil: computed here.
    var progress: FolderProgress?
    /// *Turn Off Download*: its host asks `turnOffDownloadQuestion` by the control the menu
    /// opened from (a row's ⋯, the header's *More*).
    let onTurnOffDownload: () -> Void
    /// After *Move to…* is saved (the folder's own screen shows it where it went).
    var onMoved: () -> Void = {}

    var body: some View {
        if place == .header {
            // More ends with the create group, into this folder (C126).
            MenuRows(blocks: [rows, LibraryCreateMenu(library: actions.library, shell: actions.shell, follow: actions.follow,
                                                      screen: screen, folder: folder).rows])
        } else {
            MenuRows(rows)
        }
    }

    /// The folder's state as the registry reads it.
    var facts: MenuRegistry.Facts {
        var facts = MenuRegistry.Facts()
        facts.hasArticlesToPlay = (progress ?? actions.progress(of: folder, articles: articles)).hasArticlesToPlay
        facts.hasArticles = !articles.isEmpty
        facts.downloadIsOn = downloads.isOn(folder)
        facts.hasDownloads = downloads.hasDownloads(folder, articles: articles)
        facts.isFixedOrder = folder.kind.isBookOrSeries
        return facts
    }

    var rows: [MenuRow] {
        let facts = facts
        return MenuRegistry.rows(.folder, at: place.registryPlace, facts) { row($0, facts) }
    }

    private func row(_ option: MenuRegistry.Option, _ facts: MenuRegistry.Facts) -> MenuRow {
        let shell = actions.shell
        switch option {
        case .continueFolder:
            return MenuRow(id: "menuContinue", title: Verbs.continue, icon: Icons.play) { actions.playFolder(folder) }
        case .playFromStart:
            return MenuRow(id: "menuPlayFromStart", title: Verbs.playFromStart, icon: Icons.previous) {
                actions.playFolderFromStart(folder)
            }
        case .folderDownload:
            let state = downloads.state(of: folder, articles: articles)
            if facts.downloadIsOn && state != .downloaded {
                return MenuRow(id: "menuDownload", title: Verbs.turnOffDownload, icon: Icons.turnOffDownload,
                               action: onTurnOffDownload)
            }
            if state == .downloaded || (!facts.downloadIsOn && facts.hasDownloads) {
                return removeDownloads
            }
            return MenuRow(id: "menuDownload", title: Verbs.download, icon: Icons.download) {
                DownloadActions(downloads: downloads, shell: shell).download(folder)
            }
        case .removeDownloads:
            return removeDownloads
        case .folderFavorite:
            let isFavorite = folder.isFavorite
            return MenuRow(id: "menuFavorite", title: isFavorite ? Verbs.removeFromFavorites : Verbs.addToFavorites,
                           icon: isFavorite ? Icons.unfavorite : Icons.favorite) {
                FavoriteFlow(library: actions.library, shell: shell).toggle(folder)
            }
        case .folderMove:
            return MenuRow(id: "menuMove", title: Verbs.moveTo, icon: Icons.move) {
                actions.move([.folder(folder)], onMoved: onMoved)
            }
        case .editDetails:
            return MenuRow(id: "menuEditDetails", title: Verbs.editDetails, icon: Icons.editDetails) {
                shell.present(.folderDetails(folder.id))
            }
        default:
            return MenuRow(id: "menuDeleteFolder", title: Verbs.deleteFolder(isBook: folder.kind == .book),
                           icon: Icons.delete, isDestructive: true) { screen.confirmDelete([folder]) }
        }
    }

    private var removeDownloads: MenuRow {
        MenuRow(id: "menuRemoveDownloads", title: Verbs.removeDownloads, icon: Icons.removeDownload,
                isDestructive: true) { downloads.deleteDownloads(of: folder) }
    }

    /// A row's swipe, without building the menu: the menu's *Delete Folder…* (it asks first).
    static func swipe(for folder: Folder, screen: LibraryScreenState) -> MenuRow {
        MenuRow(id: "menuDeleteFolder", title: Verbs.deleteFolder(isBook: folder.kind == .book), icon: Icons.delete,
                isDestructive: true) { screen.confirmDelete([folder]) }
    }
}
