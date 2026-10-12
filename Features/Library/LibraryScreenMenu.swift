import SwiftUI

/// The ⋯ and ＋ (*New Folder*, *Import Book…*) for the Library screen on top, shared by the Library surface and the
/// Favorites sheet: which rows the panel shows (`LibraryMenu`) and what each does there. The host
/// says which screen is on top and what the panel's big buttons do.
@MainActor
struct LibraryScreenMenu {
    /// The screen under every push: the Library home, or Favorites (the sheet).
    enum Root {
        case home
        case favorites
    }

    let library: LibraryStore
    let speech: SpeechController
    let shell: ShellState
    let downloads: DownloadCenter
    let screen: LibraryScreenState
    let root: Root
    /// The pushed screen on top (nil: the root).
    let top: LibraryRoute?
    /// The top level's page sort (`LibraryTopLevel.sortKey`).
    let topLevelSort: Binding<String>
    /// A folder moved from its own screen: show it where it went.
    let showMoved: (Folder) -> Void
    /// The big buttons: *Favorites*, *History*, *Browser*.
    let tile: (LibraryMenu.Action) -> Void

    /// The folder whose screen is on top (nil: the home, or the pages in no folder).
    var topFolder: Folder? {
        switch top {
        case .folder(let id): library.folder(id: id)
        case .pages: nil
        case nil: root == .favorites ? library.favorites() : nil
        }
    }

    /// New Folder and an imported book go in the folder on screen (a book or series too).
    var newFolderParent: Folder? { topFolder }

    private var pagesSort: PageSort { PageSort(rawValue: topLevelSort.wrappedValue) ?? LibraryTopLevel.defaultSort }

    var menu: LibraryMenu {
        var menu = screenMenu
        menu.showsDebug = speech.developerOptionsEnabled
        menu.canImportBook = root == .home && topFolder?.kind != .favorites
        if let folder = topFolder, !downloads.isQueued(.folder(folder.id)) {
            menu.downloadTitle = String(localized: "Download Folder")
        }
        return menu
    }

    private var screenMenu: LibraryMenu {
        if top == .pages { return LibraryMenu(screen: .pages, sort: pagesSort) }
        guard let folder = topFolder else { return LibraryMenu(screen: .home) }
        return LibraryMenu(screen: .folder(isFavorites: folder.kind == .favorites), sort: folder.pageSort)
    }

    /// Nothing here touches the browser's page.
    func perform(_ action: LibraryMenu.Action) {
        let folder = topFolder
        switch action {
        case .voiceSettings: shell.present(.voiceSettings)
        case .newFolder: screen.makeFolder(in: newFolderParent)
        case .importBook: BookImportActions(library: library, shell: shell).pickBook(into: newFolderParent)
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
