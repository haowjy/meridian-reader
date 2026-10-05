import SwiftUI

/// The screen for a pushed `LibraryRoute`: a book or series, any other folder, or the pages in
/// no folder.
struct LibraryRouteView: View {
    let route: LibraryRoute

    @Environment(LibraryStore.self) private var library

    var body: some View {
        switch route {
        case .folder(let id):
            if let folder = library.folder(id: id) {
                if folder.kind.isFixed {
                    BookScreen(folder: folder)
                } else {
                    FolderScreen(folder: folder)
                }
            } else {
                ContentUnavailableView("This folder is gone", systemImage: "folder")
            }
        case .pages:
            FolderScreen(folder: nil)
        }
    }
}

/// The Favorites sheet: the Favorites folder screen, with its own pushes, over the same bottom
/// row as the Library (＋ New Folder in slot 1, ⋯ for the screen on top in slot 5, the same ⋯
/// as the Library's: `LibraryScreenMenu`). Its links open in the browser and its saved pages in
/// the Reader, closing the sheet first.
struct FavoritesSheet: View {
    @Environment(LibraryStore.self) private var library
    @Environment(ShellState.self) private var shell
    @Environment(\.speechController) private var speech
    @State private var path: [LibraryRoute]
    @State private var screen = LibraryScreenState()
    @AppStorage(LibraryTopLevel.sortKey) private var topLevelSort = LibraryTopLevel.defaultSort.rawValue

    /// `folderID`: open pushed into that subfolder of Favorites.
    init(folderID: UUID? = nil) {
        _path = State(initialValue: folderID.map { [.folder($0)] } ?? [])
    }

    var body: some View {
        VStack(spacing: 0) {
            NavigationStack(path: $path) {
                FolderScreen(folder: library.favorites())
                    .navigationDestination(for: LibraryRoute.self) { LibraryRouteView(route: $0) }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { shell.sheet = nil }
                                .accessibilityIdentifier("favoritesDone")
                        }
                    }
            }
            Group {
                if screen.isEditing {
                    LibraryEditBar()
                } else {
                    toolbar
                }
            }
            .bottomChromeBand()
            .overlay(alignment: .top) { ShellToastLayer() }
        }
        .environment(screen)
        .moreMenuHost()
        .listenDebugSheet(speech)
        .libraryDialogs(screen) {
            path = Array(path.prefix { route in
                if case .folder(let id) = route { return library.folder(id: id) != nil }
                return true
            })
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("favoritesSheet")
    }

    private var toolbar: some View {
        BottomToolbarLayout {
            Button { screen.makeFolder(in: screenMenu.newFolderParent) } label: {
                Image(systemName: "folder.badge.plus").toolbarIconFrame()
            }
            .accessibilityLabel("New Folder")
            .accessibilityIdentifier("favoritesNewFolder")

            MoreMenuButton(id: "favoritesMore") {
                let screenMenu = screenMenu
                return .library(screenMenu.menu, perform: screenMenu.perform)
            }
        }
        .tint(Palette.ink)
    }

    private var screenMenu: LibraryScreenMenu {
        LibraryScreenMenu(library: library, speech: speech, shell: shell, screen: screen, root: .favorites,
                          top: path.last, topLevelSort: $topLevelSort,
                          showMoved: { _ in path = [] }) { tile in
            switch tile {
            case .favorites: path = []
            case .history: shell.present(.history)
            default:
                shell.sheet = nil
                shell.showBrowser()
            }
        }
    }
}

/// The bottom bar while a folder screen is in Edit: *Move…*, *Mark Finished*, *Remove*, acting on
/// the selection (Remove asks before deleting folders; `LibraryActions.removeSelection`). The
/// selection clears once an action is saved and stays when it can't be.
struct LibraryEditBar: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.speechController) private var speech
    @Environment(ShellState.self) private var shell
    @Environment(LibraryScreenState.self) private var screen

    private var actions: LibraryActions { LibraryActions(library: library, speech: speech, shell: shell) }

    var body: some View {
        let nothing = screen.selection.isEmpty
        BottomToolbarSpanLayout {
            Button("Move…") {
                let selected = actions.selected(in: screen)
                actions.move(selected.folders.map(LibraryItem.folder) + selected.pages.map(LibraryItem.page)) {
                    screen.selection = []
                }
            }
            .toolbarTextFrame()
            .disabled(nothing)
            .accessibilityIdentifier("editMove")
            Button("Mark Finished") {
                if actions.setFinished(actions.selected(in: screen).pages.filter(\.isSaved), true) { screen.selection = [] }
            }
            .toolbarTextFrame()
            .disabled(actions.selected(in: screen).pages.allSatisfy { !$0.isSaved })
            .accessibilityIdentifier("editMarkFinished")
            Button("Remove") { actions.removeSelection(of: screen) }
            .toolbarTextFrame()
            .disabled(nothing)
            .accessibilityIdentifier("editRemove")
        }
        .tint(Palette.ink)
    }
}
