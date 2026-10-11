import SwiftData
import SwiftUI

/// The Library surface: the folder tree as a stack of screens (the home, then folder → folder …,
/// `ShellState.libraryPath`), over the same bottom chrome as the browser.
///
/// ```
/// ┌ bar ────────────────────────────────────┐
/// │ ╭ Now Playing bar ────────────────────╮ │  ← what you hear (once something has played)
/// │ ( 🔍 Search Library                  ) │  ← same field capsule as the address bar
/// │  [＋]  [★]   [Search]  [🌐]  [⋯]       │  ← ＋ Import Book…, New Folder; ★ pushes Favorites;
///                                                  🌐 the browser; ⋯ for the screen
/// └──────────────────────────── home indicator ┘
/// ```
///
/// While searching, the results cover the screens and the toolbar steps aside (the same session
/// as the browser's address field). While a folder is in Edit, the toolbar is *Move…*, *Mark
/// Finished*, *Remove*. Pages open in the Reader sheet over the Library; 🌐 shows the browser as
/// it was, and the Library keeps its place.
struct LibrarySurface: View {
    @Environment(ShellState.self) private var shell
    @Environment(LibraryStore.self) private var library
    @Environment(\.speechController) private var speech
    @Environment(DownloadCenter.self) private var downloads
    @State private var search = SearchSession()
    @State private var screen = LibraryScreenState()
    @AppStorage(LibraryTopLevel.sortKey) private var topLevelSort = LibraryTopLevel.defaultSort.rawValue

    var body: some View {
        @Bindable var shell = shell
        VStack(spacing: 0) {
            NavigationStack(path: $shell.libraryPath) {
                LibraryHomeView(pageSort: PageSort(rawValue: topLevelSort) ?? LibraryTopLevel.defaultSort)
                    .navigationDestination(for: LibraryRoute.self) { LibraryRouteView(route: $0) }
            }
            .overlay {
                if search.isActive, !search.text.trimmingCharacters(in: .whitespaces).isEmpty {
                    LibrarySearchResults(text: search.text.trimmingCharacters(in: .whitespaces)) {
                        search.end(showing: "")
                    }
                    .environment(\.libraryScreenKey, .search)
                    .background(Palette.paper.ignoresSafeArea())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollDismissesKeyboard(.interactively)

            SearchSessionChrome(session: search, cancelID: "librarySearchCancel",
                                onCancel: { search.end(showing: "") }) {
                NowPlayingBarView(speech: speech, isCovered: shell.reader != nil)
                    .padding(.bottom, Spacing.xxs)
            } field: { focus in
                SearchField(text: Bindable(search).text, prompt: String(localized: "Search Library"), focus: focus,
                            fieldIdentifier: "librarySearchField")
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

            Button(action: showFavorites) {
                Image(systemName: "star").toolbarIconFrame()
            }
            .accessibilityLabel("Favorites")
            .accessibilityIdentifier("libraryFavorites")

            Button { search.begin() } label: {
                Image(systemName: "magnifyingglass").toolbarIconFrame()
            }
            .accessibilityLabel("Search")
            .accessibilityIdentifier("librarySearch")

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

    /// ★: pushes the Favorites folder over the screen you're on (nothing when it is already on
    /// top), so ‹ comes back to where you were.
    private func showFavorites() {
        let route = LibraryRoute.folder(library.favorites().id)
        guard shell.libraryPath.last != route else { return }
        shell.libraryPath.append(route)
    }

    // MARK: - The screen on top

    private var screenMenu: LibraryScreenMenu {
        LibraryScreenMenu(library: library, speech: speech, shell: shell, downloads: downloads, screen: screen, root: .home,
                          top: shell.libraryPath.last, topLevelSort: $topLevelSort,
                          showMoved: { shell.libraryPath = library.path(to: $0) }) { tile in
            switch tile {
            case .favorites: shell.present(.favorites())
            case .history: shell.present(.history)
            default: shell.leaveLibrary()
            }
        }
    }
}
