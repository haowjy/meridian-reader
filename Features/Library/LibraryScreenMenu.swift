import SwiftUI

/// The ⋯ for the Library screen on top (the home or a folder): the screen's rows, the same on
/// both (`MenuRegistry`, C98): *Sort*, *Prepared Audio*, then the tiles (`MenuContext.tiles`). The surface's ＋ shows the same
/// creating rows (`createRows`), acting on the screen on top (`topFolder`). Nothing in it acts on
/// the browser's page.
@MainActor
struct LibraryScreenMenu {
    let library: LibraryStore
    let speech: SpeechController
    let shell: ShellState
    let preparedAudio: PrepareCenter
    let screen: LibraryScreenState
    /// The pushed screen on top (nil: the home).
    let top: LibraryRoute?
    /// The top level's page sort (`LibraryTopLevel.sortKey`), which the home's Sort sets.
    let topLevelSort: Binding<String>
    /// A folder moved from its own screen: show it where it went.
    let showMoved: (Folder) -> Void
    /// *Turn Off Prepare*: the surface asks `turnOffPrepareQuestion` by the ⋯.
    let onTurnOffPrepare: (Folder) -> Void

    /// The folder whose screen is on top (nil: the home). New folders and imported books go in
    /// it (a book or series too), or at the top level from the home.
    var topFolder: Folder? {
        switch top {
        case .folder(let id): library.folder(id: id)
        case nil: nil
        }
    }

    /// The screen's rows (C98, C100): *Sort ›* (not in a folder that keeps its own order),
    /// *Prepared Audio*; then `[Settings][Saved][Reader]` (`[Settings][Saved][History][Reader]` on compact width). Reader opens Now Playing when audio
    /// is playing, greyed otherwise.
    func menu(compact: Bool) -> MenuContext {
        let folder = topFolder
        var facts = MenuRegistry.Facts()
        facts.isFixedOrder = false
        let screenRows = MenuContext.screenRows(at: folder == nil ? .libraryHome : .folderScreen, facts: facts,
                                                shell: shell) { option in
            option == .sort ? sortRow(folder) : nil
        }
        let reader = MenuRow(id: "moreReader", title: Verbs.reader, icon: Icons.reader,
                             availability: MenuAvailability(when: speech.nowPlaying != nil),
                             accessibilityHint: String(localized: "Go to Now Playing")) { [shell] in
            shell.showNowPlaying()
        }
        return MenuContext(screen: screenRows, tiles: MenuContext.tiles(shell, compact: compact, last: reader))
    }

    /// ＋: the create group (`LibraryCreateMenu`) into the screen on top.
    var createRows: [MenuRow] {
        LibraryCreateMenu(library: library, shell: shell, screen: screen, folder: topFolder).rows
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

/// The one create group (C126): *New Folder…*, *Import from…*, *Paste Text…*, into `folder` (nil:
/// the top level). The Library's ＋ (home and folder), a folder header's *More* and Edit's bar all
/// show it (`MenuRegistry`, places `.add` and `.edit`); it is hidden whole in an imported EPUB or
/// followed story. In Edit (`filing`), *New Folder…* files the selection into the new folder.
@MainActor
struct LibraryCreateMenu {
    let library: LibraryStore
    let shell: ShellState
    let screen: LibraryScreenState
    let folder: Folder?
    var place: MenuRegistry.Place = .add
    /// Edit's selection: New Folder files it.
    var filing: () -> [LibraryItem] = { [] }

    static func facts(for folder: Folder?) -> MenuRegistry.Facts {
        var facts = MenuRegistry.Facts()
        facts.isFixedOrder = false
        return facts
    }

    var rows: [MenuRow] {
        let folder = folder
        return MenuRegistry.rows(.screen, at: place, Self.facts(for: folder)) { option in
            switch option {
            case .newFolder:
                return MenuRow(id: "moreNewFolder", title: Verbs.newFolder, icon: Icons.newFolder) { [screen, filing] in
                    screen.makeFolder(in: folder, with: filing())
                }
            case .importFile:
                return MenuRow(id: "moreImportBook", title: Verbs.importBook, icon: Icons.importFile) { [library, shell] in
                    BookImportActions(library: library, shell: shell).pickBook(into: folder)
                }
            default:
                return MenuRow(id: "morePasteText", title: Verbs.pasteText, icon: Icons.paste) { [screen] in
                    screen.pasteText(into: folder)
                }
            }
        }
    }
}
