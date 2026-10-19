import SwiftUI

/// The ⋯ for the Library screen on top (the home or a folder): which rows the panel shows
/// (`LibraryMenu`) and what each does there. The surface's ＋ (*New Folder*, *Import Book…*) acts
/// on the same screen through `topFolder`, and so does *Follow…*, whose story's folder goes there.
@MainActor
struct LibraryScreenMenu {
    let library: LibraryStore
    let speech: SpeechController
    let shell: ShellState
    let downloads: DownloadCenter
    let follow: FollowCenter
    let screen: LibraryScreenState
    /// The pushed screen on top (nil: the home).
    let top: LibraryRoute?
    /// The top level's page sort (`LibraryTopLevel.sortKey`), which the home's Sort sets.
    let topLevelSort: Binding<String>
    /// A folder moved from its own screen: show it where it went.
    let showMoved: (Folder) -> Void
    /// *Turn Off Download*: the surface asks `turnOffDownloadQuestion` by the ⋯.
    let onTurnOffDownload: (Folder) -> Void
    /// The big buttons: *Favorites*, *History* (the browser's, pages visited), *Browser*.
    let tile: (LibraryMenu.Action) -> Void

    /// The folder whose screen is on top (nil: the home). New folders and imported books go in
    /// it (a book or series too), or at the top level from the home.
    var topFolder: Folder? {
        switch top {
        case .folder(let id): library.folder(id: id)
        case nil: nil
        }
    }

    var menu: LibraryMenu {
        guard let folder = topFolder else {
            return LibraryMenu(screen: .home, sort: PageSort(rawValue: topLevelSort.wrappedValue) ?? LibraryTopLevel.defaultSort)
        }
        let isQueued = downloads.isQueued(.folder(folder.id))
        let pages = library.pages(in: folder)
        let isOn = downloads.isOn(folder)
        let rows = LibraryMenu.FolderRows(
            isBook: folder.kind == .book,
            downloadIsOn: isOn,
            download: MenuAvailability(when: isOn || !pages.isEmpty),
            deleteDownloads: MenuAvailability(when: isQueued || pages.contains(where: library.hasDownloads))
        )
        return LibraryMenu(screen: .folder(rows), sort: folder.pageSort)
    }

    /// Nothing here touches the browser's page.
    func perform(_ action: LibraryMenu.Action) {
        let folder = topFolder
        switch action {
        case .settings: shell.present(.settings)
        case .newFolder: screen.makeFolder(in: folder)
        case .importBook: BookImportActions(library: library, shell: shell).pickBook(into: folder)
        case .follow: shell.present(.follow(FollowFlow(url: nil, parentID: folder?.id, center: follow)))
        case .sort(let sort):
            if let folder {
                shell.attempt(String(localized: "Couldn’t change the sort")) { try library.setSort(sort, for: folder) }
            } else {
                topLevelSort.wrappedValue = sort.rawValue
            }
        case .rename: if let folder { screen.rename(folder) }
        case .editDetails: if let folder { shell.present(.folderDetails(folder.id)) }
        case .move:
            guard let folder else { return }
            LibraryActions(library: library, speech: speech, shell: shell, follow: follow).move([.folder(folder)]) { showMoved(folder) }
        case .deleteFolder: if let folder { screen.confirmDelete([folder]) }
        case .deleteDownloads: if let folder { downloads.deleteDownloads(of: folder) }
        case .download:
            guard let folder else { return }
            if downloads.isOn(folder) {
                onTurnOffDownload(folder)
            } else {
                DownloadActions(downloads: downloads, shell: shell).download(folder)
            }
        case .downloads: shell.present(.downloads)
        case .favorites, .history, .browser: tile(action)
        }
    }
}
