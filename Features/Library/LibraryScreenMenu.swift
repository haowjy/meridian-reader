import SwiftUI

/// The ⋯ and ＋ → New Folder for the Library screen on top, shared by the Library surface and the
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

    /// New Folder goes in the folder on screen; on a book's screen, beside the book.
    var newFolderParent: Folder? {
        guard let folder = topFolder else { return nil }
        return folder.kind.isFixed ? folder.parent : folder
    }

    private var pagesSort: PageSort { PageSort(rawValue: topLevelSort.wrappedValue) ?? LibraryTopLevel.defaultSort }

    var menu: LibraryMenu {
        var menu = screenMenu
        menu.showsDebug = speech.developerOptionsEnabled
        return menu
    }

    private var screenMenu: LibraryMenu {
        if top == .pages { return LibraryMenu(screen: .pages, sort: pagesSort) }
        guard let folder = topFolder else { return LibraryMenu(screen: .home) }
        if folder.kind.isFixed { return LibraryMenu(screen: .book(isSeries: folder.kind == .series)) }
        return LibraryMenu(screen: .folder(isFavorites: folder.kind == .favorites), sort: folder.pageSort)
    }

    /// Nothing here touches the browser's page.
    func perform(_ action: LibraryMenu.Action) {
        let folder = topFolder
        switch action {
        case .voiceSettings: shell.present(.voiceSettings)
        case .newFolder: screen.makeFolder(in: newFolderParent)
        case .sort(let sort):
            if let folder { library.setSort(sort, for: folder) } else { topLevelSort.wrappedValue = sort.rawValue }
        case .rename: if let folder { screen.rename(folder) }
        case .move:
            guard let folder else { return }
            LibraryActions(library: library, speech: speech, shell: shell).move([.folder(folder)]) { showMoved(folder) }
        case .deleteFolder: if let folder { screen.confirmDelete([folder]) }
        case .deleteDownloads: if let folder { library.deleteDownloads(of: folder) }
        case .listenDebug: speech.showListenDebug = true
        case .favorites, .history, .browser: tile(action)
        }
    }
}
