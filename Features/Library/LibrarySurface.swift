import SwiftData
import SwiftUI

/// The Library surface: the folder tree as a stack of screens (the home, then folder → folder …,
/// `ShellState.libraryPath`), over the band it shares with the browser (`SurfaceBand`, D22).
///
/// ```
/// ┌ bar ────────────────────────────────────┐
/// │ [🌐] ╭ Now Playing bar ──────────────╮ │  ← 🌐 the browser; the bar always there
/// │ ( 🔍 Search Library                  ) │  ← filters the home's selected tab
/// │  [‹]  [›]  [＋]  [🕘]  [⋯]             │  ← ‹ up a level; › dimmed; ＋ Import Book…,
/// └──────────────────────────── home indicator ┘   New Folder; 🕘 History; ⋯ for the screen
/// ```
///
/// The search filters the home list in place; starting one on a folder screen goes back to the
/// home. While a folder is in Edit, the toolbar's slots are *Move to…*, *Mark as Finished*, *Remove*. Pages
/// open in the Reader sheet over the Library; 🌐 shows the browser as it was, and the Library
/// keeps its place.
struct LibrarySurface: View {
    @Environment(ShellState.self) private var shell
    @Environment(LibraryStore.self) private var library
    @Environment(\.speechController) private var speech
    @Environment(DownloadCenter.self) private var downloads
    @State private var screen = LibraryScreenState()
    @AppStorage(LibraryTopLevel.sortKey) private var topLevelSort = LibraryTopLevel.defaultSort.rawValue

    private var search: SearchSession { shell.librarySearch }

    var body: some View {
        @Bindable var shell = shell
        VStack(spacing: 0) {
            NavigationStack(path: $shell.libraryPath) {
                LibraryHomeView(pageSort: PageSort(rawValue: topLevelSort) ?? LibraryTopLevel.defaultSort,
                                favoritesOnly: shell.favoritesOnly, searchText: search.isActive ? search.text : "")
                    .navigationDestination(for: LibraryRoute.self) { LibraryRouteView(route: $0) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollDismissesKeyboard(.interactively)

            SurfaceBand(
                swap: .init(systemImage: Icons.browser, label: String(localized: "Browser"),
                            hint: String(localized: "Return to the browser"), identifier: "libraryBrowser",
                            action: shell.leaveLibrary),
                session: search,
                cancelID: "librarySearchCancel",
                onCancel: shell.endLibrarySearch,
                isBarCovered: shell.reader != nil
            ) { focus in
                SearchField(text: Binding(get: { search.text }, set: { search.text = $0 }), prompt: String(localized: "Search Library"), focus: focus,
                            fieldIdentifier: "librarySearchField", onSubmit: search.lowerKeyboard)
            } toolbar: {
                if screen.isEditing {
                    LibraryEditBar()
                } else {
                    toolbar
                }
            }
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
        .onChange(of: search.isActive) { _, active in
            if active { shell.librarySearchBegan() }
        }
    }

    // MARK: - Toolbar

    /// `[‹][›][＋][🕘][⋯]`, slot for slot the browser's `[‹][›][🔖][🕘][⋯]`: the Library has no
    /// forward, so › stays dimmed in its place.
    private var toolbar: some View {
        BottomToolbarLayout {
            BandToolbarButton(systemImage: Icons.back, label: String(localized: "Back"),
                              identifier: "libraryBack", action: shell.libraryBack)
                .disabled(shell.libraryPath.isEmpty)
                .toolbarSlot(0)
            BandToolbarButton(systemImage: Icons.forward, label: String(localized: "Forward"),
                              identifier: "libraryForward") {}
                .disabled(true)
                .toolbarSlot(1)
            Menu {
                Button("Import Book…", systemImage: Icons.book) {
                    BookImportActions(library: library, shell: shell).pickBook(into: screenMenu.topFolder)
                }
                .accessibilityIdentifier("libraryImportBook")
                Button("New Folder", systemImage: Icons.newFolder) { screen.makeFolder(in: screenMenu.topFolder) }
                    .accessibilityIdentifier("libraryNewFolder")
            } label: {
                Image(systemName: Icons.add).toolbarIconFrame()
            }
            .accessibilityLabel("Add")
            .accessibilityIdentifier("libraryAdd")
            .toolbarSlot(2)
            BandToolbarButton(systemImage: Icons.history, label: String(localized: "History"),
                              identifier: "libraryHistory") { shell.present(.history) }
                .toolbarSlot(3)
            MoreMenuButton(id: "libraryMore") {
                let screenMenu = screenMenu
                return .library(screenMenu.menu, perform: screenMenu.perform)
            }
            .toolbarSlot(BottomToolbarLayout.moreSlot)
        }
    }

    // MARK: - The screen on top

    private var screenMenu: LibraryScreenMenu {
        LibraryScreenMenu(library: library, speech: speech, shell: shell, downloads: downloads, screen: screen,
                          top: shell.libraryPath.last, topLevelSort: $topLevelSort,
                          showMoved: { shell.libraryPath = library.path(to: $0) }) { tile in
            switch tile {
            case .favorites: shell.showFavorites()
            case .history: shell.present(.history)
            default: shell.leaveLibrary()
            }
        }
    }
}
