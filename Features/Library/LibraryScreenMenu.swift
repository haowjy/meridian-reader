import SwiftUI

/// The ⋯ for the Library screen on top (the home or a folder): which rows the panel shows
/// (`LibraryMenu`) and what each does there. The surface's ＋ (*New Folder*, *Import Book…*) acts
/// on the same screen through `topFolder`.
@MainActor
struct LibraryScreenMenu {
    let library: LibraryStore
    let speech: SpeechController
    let shell: ShellState
    let downloads: DownloadCenter
    let screen: LibraryScreenState
    /// The pushed screen on top (nil: the home).
    let top: LibraryRoute?
    /// The top level's page sort (`LibraryTopLevel.sortKey`), which the home's Sort sets.
    let topLevelSort: Binding<String>
    /// A folder moved from its own screen: show it where it went.
    let showMoved: (Folder) -> Void
    /// The big buttons: *Favorites*, *History*, *Browser*.
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
        var menu = screenMenu
        menu.showsDebug = speech.developerOptionsEnabled
        if let folder = topFolder {
            menu.isBook = folder.kind == .book
            if !downloads.isQueued(.folder(folder.id)) {
                menu.downloadTitle = Verbs.downloadFolder(isBook: menu.isBook)
            }
        }
        return menu
    }

    private var screenMenu: LibraryMenu {
        guard let folder = topFolder else {
            return LibraryMenu(screen: .home, sort: PageSort(rawValue: topLevelSort.wrappedValue) ?? LibraryTopLevel.defaultSort)
        }
        return LibraryMenu(screen: .folder, sort: folder.pageSort)
    }

    /// Nothing here touches the browser's page.
    func perform(_ action: LibraryMenu.Action) {
        let folder = topFolder
        switch action {
        case .voiceSettings: shell.present(.voiceSettings)
        case .newFolder: screen.makeFolder(in: folder)
        case .importBook: BookImportActions(library: library, shell: shell).pickBook(into: folder)
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
            LibraryActions(library: library, speech: speech, shell: shell).move([.folder(folder)]) { showMoved(folder) }
        case .deleteFolder: if let folder { screen.confirmDelete([folder]) }
        case .deleteDownloads: if let folder { downloads.deleteDownloads(of: folder) }
        case .download: if let folder { DownloadActions(downloads: downloads, shell: shell).download(folder) }
        case .downloads: shell.present(.downloads)
        case .listenDebug: speech.showListenDebug = true
        case .favorites, .history, .browser: tile(action)
        }
    }
}
