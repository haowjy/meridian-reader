import SwiftData
import SwiftUI

/// The Library surface: the folder tree as a stack of screens (the home, then folder → folder …,
/// `ShellState.libraryPath`), over the band it shares with the browser (`SurfaceBand`, D22).
///
/// ```
/// ┌ bar ────────────────────────────────────┐
/// │ [🌐] ╭ Now Playing bar ──────────────╮ │  ← 🌐 the browser; the bar always there
/// │ ( 🔍 Search Library                  ) │  ← filters the home's tab or the folder, and names it
/// │  [‹]  [›]  [＋]  [🕘]  [⋯]             │  ← ‹ up a level; › dimmed; ＋ New Folder…,
/// └──────────────────────────── home indicator ┘   Import Book…; 🕘 History; ⋯ for the screen
/// ```
///
/// The search filters the screen it began on in place: the home's tab, or a folder (everything
/// under it, `FolderSearchResults`); it ends when that folder is left. While a folder is in Edit,
/// the toolbar's slots are *Move to…*, *Mark as Finished*, *Remove*. Pages open in the Reader
/// sheet over the Library; 🌐 shows the browser as it was, and the Library
/// keeps its place.
struct LibrarySurface: View {
    @Environment(ShellState.self) private var shell
    @Environment(LibraryStore.self) private var library
    @Environment(\.speechController) private var speech
    @Environment(PrepareCenter.self) private var preparedAudio
    @Environment(FollowCenter.self) private var follow
    @State private var screen = LibraryScreenState()
    /// The ⋯'s *Turn Off Prepare* asked: the question shows by the ⋯.
    @State private var turningOff: Folder?
    @AppStorage(LibraryTopLevel.sortKey) private var topLevelSort = LibraryTopLevel.defaultSort.rawValue

    private var search: SearchSession { shell.librarySearch }

    var body: some View {
        @Bindable var shell = shell
        VStack(spacing: 0) {
            NavigationStack(path: $shell.libraryPath) {
                LibraryHomeView(articleSort: ArticleSort(rawValue: topLevelSort) ?? LibraryTopLevel.defaultSort,
                                tab: shell.homeTab,
                                searchText: search.isActive && shell.librarySearchFolder == nil ? search.text : "")
                    .navigationDestination(for: LibraryRoute.self) { LibraryRouteView(route: $0) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollDismissesKeyboard(.interactively)

            SurfaceBand(
                swap: .init(systemImage: Icons.browser, label: Verbs.browser,
                            hint: String(localized: "Return to the browser"), identifier: "libraryBrowser",
                            action: shell.leaveLibrary),
                session: search,
                cancelID: "librarySearchCancel",
                onCancel: shell.endLibrarySearch,
                begin: shell.beginLibrarySearch,
                isBarCovered: shell.reader != nil
            ) { focus in
                SearchField(text: Binding(get: { search.text }, set: { search.text = $0 }), prompt: searchPrompt, focus: focus,
                            fieldIdentifier: "librarySearchField", onSubmit: search.lowerKeyboard)
            } toolbar: {
                if screen.isEditing {
                    LibraryEditBar()
                } else {
                    toolbar
                }
            }
            .overlay(alignment: .top) { PrepareProgressEdge() }
            .overlay(alignment: .top) { ShellToastLayer() }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("libraryChrome")
        }
        .background(Palette.paper.ignoresSafeArea())
        .libraryDropZone(screen, top: shell.libraryPath.last.map(LibraryScreenKey.route) ?? .home,
                         actions: LibraryActions(library: library, speech: speech, shell: shell, follow: follow))
        .environment(screen)
        .libraryDialogs(screen) {
            shell.pruneLibraryPath { library.folder(id: $0) != nil }
        }
    }

    /// The field names what it searches, or would: the folder its search began on, else the
    /// folder screen on top, else the home's tab.
    private var searchPrompt: String {
        let folder = search.isActive ? shell.librarySearchFolder.flatMap(library.folder(id:)) : screenMenu.topFolder
        return folder.map { LibraryHomeTab.searchPrompt(naming: $0.name) } ?? shell.homeTab.searchPrompt
    }

    // MARK: - Toolbar

    /// `[‹][›][＋][🕘][⋯]`, slot for slot the browser's `[‹][›][🔖][🕘][⋯]`: the Library has no
    /// forward, so › stays dimmed in its place.
    private var toolbar: some View {
        BottomToolbarLayout {
            BandToolbarButton(systemImage: Icons.back, label: Verbs.back,
                              identifier: "libraryBack", action: shell.libraryBack)
                .disabled(shell.libraryPath.isEmpty)
                .toolbarSlot(0)
            BandToolbarButton(systemImage: Icons.forward, label: Verbs.forward,
                              identifier: "libraryForward") {}
                .disabled(true)
                .toolbarSlot(1)
            let createRows = screenMenu.createRows
            if !createRows.isEmpty {
                Menu {
                    MenuRows(createRows)
                } label: {
                    Image(systemName: Icons.add).toolbarIconFrame()
                }
                .accessibilityLabel("Add")
                .accessibilityIdentifier("libraryAdd")
                .toolbarSlot(2)
            }
            BandToolbarButton(systemImage: Icons.history, label: Verbs.history,
                              identifier: "libraryHistory") { shell.present(.history) }
                .toolbarSlot(3)
            MoreMenuButton(id: "libraryMore") { screenMenu.menu }
            .turnOffPrepareQuestion($turningOff)
            .toolbarSlot(BottomToolbarLayout.moreSlot)
        }
    }

    // MARK: - The screen on top

    private var screenMenu: LibraryScreenMenu {
        LibraryScreenMenu(library: library, speech: speech, shell: shell, preparedAudio: preparedAudio, screen: screen,
                          top: shell.libraryPath.last, topLevelSort: $topLevelSort,
                          showMoved: { shell.libraryPath = library.path(to: $0) },
                          onTurnOffPrepare: { turningOff = $0 })
    }
}
