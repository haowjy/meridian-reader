import SwiftData
import SwiftUI

/// The Library surface: the folder tree as a stack of screens (the home, then folder → folder …,
/// `ShellState.libraryPath`), over the same bottom chrome as the browser.
///
/// ```
/// ┌ bar ────────────────────────────────────┐
/// │ ╭ Now Playing bar ────────────────────╮ │  ← what you hear (once something has played)
/// │ ( 🔍 Search Library                  ) │  ← same field capsule as the address bar
/// │  [＋]  [ ]   [Search]  [🌐]  [⋯]       │  ← ＋ New Folder; 🌐 the browser; ⋯ for the screen
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
            .overlay(alignment: .top) { ShellToastLayer() }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("libraryChrome")
        }
        .background(Palette.paper.ignoresSafeArea())
        .environment(screen)
        .libraryDialogs(screen) {
            shell.pruneLibraryPath { library.folder(id: $0) != nil }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        BottomToolbarLayout {
            Menu {
                Button("New Folder", systemImage: "folder.badge.plus") { screen.makeFolder(in: newFolderParent) }
                    .accessibilityIdentifier("libraryNewFolder")
            } label: {
                Image(systemName: "plus").toolbarIconFrame()
            }
            .accessibilityLabel("Add")
            .accessibilityIdentifier("libraryAdd")

            Color.clear.frame(minHeight: BottomChrome.rowHeight)

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

            MoreMenuButton(id: "libraryMore") { .library(menu, perform: perform) }
        }
        // Same as the browser toolbar: tint keeps disabled buttons dimmed.
        .tint(Palette.ink)
    }

    // MARK: - The screen on top

    /// The folder whose screen is on top (nil: the home or the pages in no folder).
    private var topFolder: Folder? {
        guard case .folder(let id)? = shell.libraryPath.last else { return nil }
        return library.folder(id: id)
    }

    /// ＋ → New Folder goes in the folder on screen; on a book's screen, beside the book.
    private var newFolderParent: Folder? {
        guard let folder = topFolder else { return nil }
        return folder.kind.isFixed ? folder.parent : folder
    }

    private var menu: LibraryMenu {
        if shell.libraryPath.last == .pages {
            return LibraryMenu(screen: .pages, sort: PageSort(rawValue: topLevelSort) ?? LibraryTopLevel.defaultSort)
        }
        guard let folder = topFolder else { return LibraryMenu(screen: .home) }
        if folder.kind.isFixed { return LibraryMenu(screen: .book(isSeries: folder.kind == .series)) }
        return LibraryMenu(screen: .folder(isFavorites: folder.kind == .favorites), sort: folder.pageSort)
    }

    /// The Library's ⋯: nothing in it touches the browser's page.
    private func perform(_ action: LibraryMenu.Action) {
        let folder = topFolder
        switch action {
        case .voiceSettings: shell.present(.voiceSettings)
        case .newFolder: screen.makeFolder(in: newFolderParent)
        case .sort(let sort):
            if let folder { library.setSort(sort, for: folder) } else { topLevelSort = sort.rawValue }
        case .rename: if let folder { screen.rename(folder) }
        case .move:
            guard let folder else { return }
            LibraryActions(library: library, speech: speech, shell: shell).move([.folder(folder)]) {
                shell.libraryPath = library.path(to: folder)
            }
        case .deleteFolder: if let folder { screen.confirmDelete([folder]) }
        case .deleteDownloads: if let folder { library.deleteDownloads(of: folder) }
        case .favorites: shell.present(.favorites())
        case .history: shell.present(.history)
        case .browser: shell.leaveLibrary()
        }
    }
}
