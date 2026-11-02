import SwiftUI

/// The Library screen's menu: the create group followed by Sort on compact width;
/// regular width keeps its separate ＋ and navigation tiles (`MenuRegistry.Place.libraryPanel`).
@MainActor
struct LibraryScreenMenu {
    let library: LibraryStore
    let speech: SpeechController
    let shell: ShellState
    let follow: FollowCenter
    let screen: LibraryScreenState
    /// The pushed screen on top (nil: the home).
    let top: LibraryRoute?
    /// The top level's page sort (`LibraryTopLevel.sortKey`), which the home's Sort sets.
    let topLevelSort: Binding<String>

    /// The folder whose screen is on top (nil: the home). New folders and imported books go in
    /// it (a book or series too), or at the top level from the home.
    var topFolder: Folder? {
        switch top {
        case .folder(let id): library.folder(id: id)
        case nil: nil
        }
    }

    /// The title ⋯ (compact width: the create group, then Sort, no ＋ beside it) or the ⋯ panel
    /// (regular width: Sort and the navigation tiles; the create group is its ＋). Which rows each
    /// place has is the registry's.
    func menu(compact: Bool) -> MenuContext {
        let folder = topFolder
        let place: MenuRegistry.Place = compact ? (folder == nil ? .libraryHome : .folderScreen) : .libraryPanel
        let create = createMenu
        let screenRows = MenuContext.screenRows(at: place, shell: shell) { option in
            option == .sort ? sortRow(folder) : create.row(option)
        }
        let reader = MenuRow(id: "moreListen", title: Verbs.listen, icon: Icons.listen,
                             availability: MenuAvailability(when: speech.nowPlaying != nil)) { [shell] in
            shell.showNowPlaying()
        }
        return MenuContext(screen: screenRows,
                           tiles: compact ? [] : MenuContext.tiles(shell, compact: false, last: reader))
    }

    /// ＋: the create group (`LibraryCreateMenu`) into the screen on top.
    var createRows: [MenuRow] { createMenu.rows }

    private var createMenu: LibraryCreateMenu {
        LibraryCreateMenu(library: library, shell: shell, follow: follow, screen: screen, folder: topFolder)
    }

    /// *Sort*: the folder's page sort, or on the home the top level's.
    private func sortRow(_ folder: Folder?) -> MenuRow {
        let current = folder?.articleSort ?? ArticleSort(rawValue: topLevelSort.wrappedValue) ?? LibraryTopLevel.defaultSort
        let choices = ArticleSort.allCases.map { sort in
            MenuRow(id: "moreSort-\(sort.rawValue)", title: sort.title, icon: sort == current ? Icons.checkmark : nil) {
                [library, shell, topLevelSort] in
                if let folder {
                    shell.attempt(String(localized: "Couldn’t change the sort")) { try library.setSort(sort, for: folder) }
                } else {
                    topLevelSort.wrappedValue = sort.rawValue
                }
            }
        }
        return MenuRow(id: "moreSort", title: Verbs.sort, icon: Icons.sort, submenu: choices)
    }
}

/// The shared create group: Add a Link, Import a File, Paste Text, then New Folder.
/// In Edit, New Folder files the selected items into it.
@MainActor
struct LibraryCreateMenu {
    let library: LibraryStore
    let shell: ShellState
    let follow: FollowCenter
    let screen: LibraryScreenState
    let folder: Folder?
    var place: MenuRegistry.Place = .add
    /// Edit's selection: New Folder files it.
    var filing: () -> [LibraryItem] = { [] }

    var rows: [MenuRow] {
        MenuContext.screenRows(at: place, shell: shell, custom: row)
    }

    /// A create option's row (nil: not one of the create group's).
    func row(_ option: MenuRegistry.Option) -> MenuRow? {
        let folder = folder
        switch option {
        case .addLink:
            return MenuRow(id: "moreAddLink", title: Verbs.addLink, icon: Icons.link) { [screen, shell, follow] in
                screen.addLink(into: folder, shell: shell, follow: follow)
            }
        case .importFile:
            return MenuRow(id: "moreImportBook", title: Verbs.importBook, icon: Icons.importFile) { [library, shell] in
                BookImportActions(library: library, shell: shell).pickBook(into: folder)
            }
        case .pasteText:
            return MenuRow(id: "morePasteText", title: Verbs.pasteText, icon: Icons.paste) { [screen, shell] in
                screen.pasteText(into: folder, shell: shell)
            }
        case .newFolder:
            return MenuRow(id: "moreNewFolder", title: Verbs.newFolder, icon: Icons.newFolder) { [screen, filing] in
                screen.makeFolder(in: folder, with: filing())
            }
        default:
            return nil
        }
    }
}
