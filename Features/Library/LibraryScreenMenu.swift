import SwiftUI

/// The ⋯ for the Library screen on top (the home or a folder): the screen's rows, the same on
/// both (`MenuRegistry`, C98): *Sort*, *Follow…*, *Downloads*, *Settings*. The surface's ＋ shows the same
/// two creating rows (`createRows`), so both act on the screen on top (`topFolder`), and so does
/// *Follow…*, whose story's folder goes there. Nothing in it acts on the browser's page.
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

    /// The folder whose screen is on top (nil: the home). New folders and imported books go in
    /// it (a book or series too), or at the top level from the home.
    var topFolder: Folder? {
        switch top {
        case .folder(let id): library.folder(id: id)
        case nil: nil
        }
    }

    /// The screen's rows only (C98, C100): *Sort ›* (not in a folder that keeps its own order),
    /// *Downloads*, *Settings*; then the big buttons, on the home only *Browser* (its tabs are
    /// Favorites and Recent).
    var menu: MenuContext {
        let folder = topFolder
        var facts = MenuRegistry.Facts()
        facts.isFixedOrder = folder?.kind.isBookOrSeries == true
        let screenRows = MenuContext.screenRows(at: folder == nil ? .libraryHome : .folderScreen, facts: facts,
                                                shell: shell) { option in
            option == .sort ? sortRow(folder) : nil
        }
        let browser = MenuRow(id: "moreBrowser", title: Verbs.browser, icon: Icons.browser,
                              accessibilityHint: String(localized: "Return to the browser"), action: shell.leaveLibrary)
        return MenuContext(screen: screenRows, tiles: folder == nil ? [browser] : MenuContext.tiles(shell, last: browser))
    }

    /// ＋: *New Folder…* (*New Folder…* in a folder), *Import EPUB…* and *Follow…*, into the
    /// screen on top (`MenuRegistry`, place `.add`).
    var createRows: [MenuRow] {
        let folder = topFolder
        var facts = MenuRegistry.Facts()
        facts.isFixedOrder = folder?.kind.isBookOrSeries == true
        return MenuRegistry.rows(.screen, at: .add, facts) { option in
            switch option {
            case .newFolder:
                return MenuRow(id: "moreNewFolder", title: Verbs.newFolder,
                               icon: Icons.newFolder) { [screen] in screen.makeFolder(in: folder) }
            case .importFile:
                return MenuRow(id: "moreImportBook", title: Verbs.importBook, icon: Icons.importFile) { [library, shell] in
                    BookImportActions(library: library, shell: shell).pickBook(into: folder)
                }
            default:
                return MenuRow(id: "moreFollow", title: Verbs.follow, icon: Icons.follow) { [shell, follow] in
                    shell.present(.follow(FollowFlow(url: nil, parentID: folder?.id, center: follow)))
                }
            }
        }
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
