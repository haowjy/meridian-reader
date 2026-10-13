import SwiftData
import SwiftUI

/// The Library surface: the folder tree as a stack of screens (the home, then folder → folder …,
/// `ShellState.libraryPath`), over the same bottom chrome as the browser.
///
/// ```
/// ┌ bar ────────────────────────────────────┐
/// │ ╭ Now Playing bar ────────────────────╮ │  ← what you hear (once something has played)
/// │ ( 🔍 Search Library                  ) │  ← inline, filters the selected tab
/// │  [＋]         [🌐]  [⋯]               │  ← ＋ Import Book…, New Folder
///                                                  🌐 the browser; ⋯ for the screen
/// └──────────────────────────── home indicator ┘
/// ```
///
/// The search filters the home list in place. While a folder is in Edit, the toolbar is *Move…*, *Mark
/// Finished*, *Remove*. Pages open in the Reader sheet over the Library; 🌐 shows the browser as
/// it was, and the Library keeps its place.
struct LibrarySurface: View {
    @Environment(ShellState.self) private var shell
    @Environment(LibraryStore.self) private var library
    @Environment(\.speechController) private var speech
    @Environment(DownloadCenter.self) private var downloads
    @State private var searchText = ""
    @AppStorage("library.favoritesTab") private var favoritesOnly = false
    @State private var screen = LibraryScreenState()
    @AppStorage(LibraryTopLevel.sortKey) private var topLevelSort = LibraryTopLevel.defaultSort.rawValue

    var body: some View {
        @Bindable var shell = shell
        VStack(spacing: 0) {
            NavigationStack(path: $shell.libraryPath) {
                LibraryHomeView(pageSort: PageSort(rawValue: topLevelSort) ?? LibraryTopLevel.defaultSort,
                                favoritesOnly: $favoritesOnly, searchText: $searchText)
                    .navigationDestination(for: LibraryRoute.self) { LibraryRouteView(route: $0) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollDismissesKeyboard(.interactively)

            VStack(spacing: BottomChrome.rowSpacing) {
                NowPlayingBarView(speech: speech, isCovered: shell.reader != nil)
                    .padding(.bottom, Spacing.xxs)
                if screen.isEditing {
                    LibraryEditBar()
                } else {
                    toolbar
                }
            }
            .bottomChromeBand()
            .overlay(alignment: .top) { DownloadProgressEdge() }
            .overlay(alignment: .top) { ShellToastLayer() }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("libraryChrome")
        }
        .background(Palette.paper.ignoresSafeArea())
        .libraryDropZone(screen, top: shell.libraryPath.last.map(LibraryScreenKey.route) ?? .home,
                         actions: LibraryActions(library: library, speech: speech, shell: shell))
        .environment(screen)
        .libraryDialogs(screen) {
            shell.pruneLibraryPath { library.folder(id: $0) != nil }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        BottomToolbarLayout {
            Menu {
                Button("Import Book…", systemImage: "book.closed") {
                    BookImportActions(library: library, shell: shell).pickBook(into: screenMenu.newFolderParent)
                }
                .accessibilityIdentifier("libraryImportBook")
                Button("New Folder", systemImage: "folder.badge.plus") { screen.makeFolder(in: screenMenu.newFolderParent) }
                    .accessibilityIdentifier("libraryNewFolder")
            } label: {
                Image(systemName: "plus").toolbarIconFrame()
            }
            .accessibilityLabel("Add")
            .accessibilityIdentifier("libraryAdd")

            Button(action: shell.leaveLibrary) {
                Image(systemName: "globe").toolbarIconFrame()
            }
            .accessibilityLabel("Browser")
            .accessibilityIdentifier("libraryBrowser")
            .accessibilityHint("Return to the browser")

            MoreMenuButton(id: "libraryMore") {
                let screenMenu = screenMenu
                return .library(screenMenu.menu, perform: screenMenu.perform)
            }
        }
        // Same as the browser toolbar: tint keeps disabled buttons dimmed.
        .tint(Palette.ink)
    }

    // MARK: - The screen on top

    private var screenMenu: LibraryScreenMenu {
        LibraryScreenMenu(library: library, speech: speech, shell: shell, downloads: downloads, screen: screen,
                          top: shell.libraryPath.last, topLevelSort: $topLevelSort,
                          showMoved: { shell.libraryPath = library.path(to: $0) }) { tile in
            switch tile {
            case .favorites:
                favoritesOnly = true
                shell.showLibrary(at: [])
            case .history: shell.present(.history)
            default: shell.leaveLibrary()
            }
        }
    }
}
