import SwiftUI

/// The ⋯ for the Library screen on top (the home or a folder). On a folder's screen its first
/// block is the folder's own menu (`FolderMenu`, the rows its row's ⋯ and its header's *More*
/// show); then the screen's rows, the same on both: *Sort*, *New Folder…* (*New Folder Inside…* in
/// a folder), *Import Book…*, *Follow…*, *Downloads*, *Settings*. The surface's ＋ shows the same
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

    var menu: MenuContext {
        let folder = topFolder
        let item = folder.map { folder in
            FolderMenu(folder: folder, pages: library.pages(in: folder),
                       actions: LibraryActions(library: library, speech: speech, shell: shell, follow: follow),
                       downloads: downloads, screen: screen, onTurnOffDownload: { onTurnOffDownload(folder) },
                       onMoved: { showMoved(folder) }).rows
        } ?? []
        let screenRows = [sortRow(folder)] + createRows + [
            MenuRow(id: "moreFollow", title: Verbs.follow, icon: Icons.follow) { [shell, follow] in
                shell.present(.follow(FollowFlow(url: nil, parentID: folder?.id, center: follow)))
            },
        ] + MenuContext.tail(shell)
        let browser = MenuRow(id: "moreBrowser", title: Verbs.browser, icon: Icons.browser,
                              accessibilityHint: String(localized: "Return to the browser"), action: shell.leaveLibrary)
        return MenuContext(item: item, screen: screenRows, tiles: MenuContext.tiles(shell, last: browser))
    }

    /// *New Folder…* (*New Folder Inside…* in a folder) and *Import Book…*, into the screen on top:
    /// the ⋯ panel's and ＋'s.
    var createRows: [MenuRow] {
        let folder = topFolder
        return [
            MenuRow(id: "moreNewFolder", title: folder == nil ? Verbs.newFolder : Verbs.newFolderInside,
                    icon: Icons.newFolder) { [screen] in screen.makeFolder(in: folder) },
            MenuRow(id: "moreImportBook", title: Verbs.importBook, icon: Icons.book) { [library, shell] in
                BookImportActions(library: library, shell: shell).pickBook(into: folder)
            },
        ]
    }

    /// *Sort*: the folder's page sort, or on the home the top level's.
    private func sortRow(_ folder: Folder?) -> MenuRow {
        let current = folder?.pageSort ?? PageSort(rawValue: topLevelSort.wrappedValue) ?? LibraryTopLevel.defaultSort
        let choices = PageSort.allCases.map { sort in
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
