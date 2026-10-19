import SwiftUI

/// A folder's menu (a book or series as any other): the one definition its row's ⋯ and long press,
/// its header's *More*, its screen's ⋯ (the item block of the panel) and its Favorites tile all
/// render (decision C4):
///
/// | Row | Shows |
/// |---|---|
/// | Continue, Play from Start | dimmed while none of its pages play |
/// | Download / Turn Off Download | its face the Download toggle (`DownloadCenter.isOn`); *Download* dimmed with no pages |
/// | Remove Downloads (red) | dimmed while nothing of it is downloaded or downloading |
/// | Add to / Remove from Favorites | |
/// | Rename…, Edit Details… | |
/// | Select | a list with Edit |
/// | Move to… | |
/// | Delete Folder… / Delete Book… (red) | |
///
/// *Download* turns the toggle on (`DownloadCenter.download`); *Turn Off Download* asks first
/// (`onTurnOffDownload`, by the control the menu opened from), then turns it off and keeps what
/// is downloaded. *Remove Downloads* deletes its pages' audio and keeps them out of its download
/// (P8). Rename and Delete ask through `LibraryScreenState`'s dialogs, which the screen hosts.
struct FolderMenu: View {
    let folder: Folder
    /// Its pages in play order (what its row or screen already holds).
    let pages: [Page]
    let actions: LibraryActions
    let downloads: DownloadCenter
    let screen: LibraryScreenState
    /// *Turn Off Download*: its host asks `turnOffDownloadQuestion` by the control the menu
    /// opened from (a row's ⋯, the header's *More*, the screen's ⋯).
    let onTurnOffDownload: () -> Void
    /// *Select*: enters Edit with this row selected (folder screens only).
    var onSelect: (() -> Void)?
    /// After *Move to…* is saved (the folder's own screen shows it where it went).
    var onMoved: () -> Void = {}

    var body: some View {
        MenuRows(rows)
    }

    var rows: [MenuRow] {
        let progress = actions.progress(of: folder, pages: pages)
        let isOn = downloads.isOn(folder)
        let hasDownloads = downloads.isQueued(.folder(folder.id)) || pages.contains(where: actions.library.hasDownloads)
        let isFavorite = folder.isFavorite
        let isBook = folder.kind == .book
        let shell = actions.shell
        return [
            MenuRow(id: "menuContinue", title: Verbs.continue, icon: Icons.play,
                    availability: MenuAvailability(when: progress.hasPagesToPlay)) { actions.playFolder(folder) },
            MenuRow(id: "menuPlayFromStart", title: Verbs.playFromStart, icon: Icons.previous,
                    availability: MenuAvailability(when: progress.hasPagesToPlay)) { actions.playFolderFromStart(folder) },
            MenuRow(id: "menuDownload", title: isOn ? Verbs.turnOffDownload : Verbs.download,
                    icon: isOn ? Icons.turnOffDownload : Icons.download,
                    availability: MenuAvailability(when: isOn || !pages.isEmpty)) {
                if isOn {
                    onTurnOffDownload()
                } else {
                    DownloadActions(downloads: downloads, shell: shell).download(folder)
                }
            },
            MenuRow(id: "menuRemoveDownloads", title: Verbs.removeDownloads, icon: Icons.removeDownload,
                    isDestructive: true, availability: MenuAvailability(when: hasDownloads)) {
                downloads.deleteDownloads(of: folder)
            },
            MenuRow(id: "menuFavorite", title: isFavorite ? Verbs.removeFromFavorites : Verbs.addToFavorites,
                    icon: isFavorite ? Icons.unfavorite : Icons.favorite) {
                FavoriteFlow(library: actions.library, shell: shell).toggle(folder)
            },
            MenuRow(id: "menuRename", title: Verbs.rename, icon: Icons.rename) { screen.rename(folder) },
            MenuRow(id: "menuEditDetails", title: Verbs.editDetails, icon: Icons.editDetails) {
                shell.present(.folderDetails(folder.id))
            },
            MenuRow(id: "menuSelect", title: Verbs.select, icon: Icons.select,
                    availability: MenuAvailability(applies: onSelect != nil)) { onSelect?() },
            MenuRow(id: "menuMove", title: Verbs.moveTo, icon: Icons.move) { actions.move([.folder(folder)], onMoved: onMoved) },
            MenuRow(id: "menuDeleteFolder", title: Verbs.deleteFolder(isBook: isBook), icon: Icons.delete,
                    isDestructive: true) { screen.confirmDelete([folder]) },
        ]
    }
}
