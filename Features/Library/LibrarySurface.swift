import SwiftData
import SwiftUI

/// The Library surface: the folder tree as a stack of screens (the home, then folder → folder …,
/// `ShellState.libraryPath`). Compact width: the shell's bottom chrome (`ChromeHost`, built from
/// `LibraryChrome`) floats over it, so the screens scroll under it and reserve its footprint at
/// the bottom. Regular width keeps the dock and the sidebar (`SurfaceBand`, `ClusteredPlayerDock`).
///
/// The search filters the screen it began on in place: the home's tab, or a folder (everything
/// under it, `FolderSearchResults`); it ends when that folder is left. While a folder is in Edit,
/// the chrome's second row is *Move to…*, *Mark as Finished*, *Remove*. Pages open in the Reader
/// sheet over the Library; the pill's Browser segment shows the browser as it was, and the Library
/// keeps its place.
struct LibrarySurface: View {
    @Environment(ShellState.self) private var shell
    @Environment(LibraryStore.self) private var library
    @Environment(\.speechController) private var speech
    @Environment(PrepareCenter.self) private var preparedAudio
    @Environment(FollowCenter.self) private var follow
    /// The Library's screen state, menu and search prompt, shared with the shell's bottom chrome.
    let chrome: LibraryChrome
    @AppStorage(LibraryTopLevel.sortKey) private var topLevelSort = LibraryTopLevel.defaultSort.rawValue
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var screen: LibraryScreenState { chrome.screen }
    private var screenMenu: LibraryScreenMenu { chrome.screenMenu }
    private var turningOff: Binding<Folder?> { chrome.turningOff }
    private var searchPrompt: String { chrome.searchPrompt }

    private var isRegular: Bool { sizeClass == .regular }
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
            .modifier(CompactChromeInsets(isCompact: !isRegular))

            if isRegular {
                // Regular: sidebar owns surface swap / Settings; clustered dock owns Now Playing.
                // Keep search field when active; otherwise a slim clustered dock with library tools.
                if search.isActive {
                    SurfaceBand(
                        swap: nil,
                        session: search,
                        cancelID: "librarySearchCancel",
                        onCancel: shell.endLibrarySearch,
                        begin: shell.beginLibrarySearch,
                        isBarCovered: shell.reader != nil,
                        showsNowPlayingBar: false,
                        showsToolbar: false
                    ) { focus in
                        SearchField(text: Binding(get: { search.text }, set: { search.text = $0 }), prompt: searchPrompt, focus: focus,
                                    fieldIdentifier: "librarySearchField", onSubmit: search.lowerKeyboard)
                    } toolbar: { EmptyView() }
                }
                ClusteredPlayerDock(speech: speech, isCovered: shell.reader != nil, trailingTools: AnyView(libraryRegularTools))
                    .overlay(alignment: .top) { PrepareProgressEdge() }
                    .overlay(alignment: .top) { ShellToastLayer() }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("libraryChrome")
            }
        }
        .background(Palette.paper.ignoresSafeArea())
        .libraryDropZone(screen, top: shell.libraryPath.last.map(LibraryScreenKey.route) ?? .home,
                         actions: LibraryActions(library: library, speech: speech, shell: shell, follow: follow))
        .environment(screen)
        .libraryDialogs(screen) {
            shell.pruneLibraryPath { library.folder(id: $0) != nil }
        }
    }

    // MARK: - Regular trailing tools

    @ViewBuilder
    private var libraryRegularTools: some View {
        if screen.isEditing {
            LibraryEditBar()
        } else {
            HStack(spacing: Spacing.s) {
                BandToolbarButton(systemImage: Icons.back, label: Verbs.back,
                                  identifier: "libraryBack", action: shell.libraryBack)
                    .disabled(shell.libraryPath.isEmpty)
                let createRows = screenMenu.createRows
                if !createRows.isEmpty {
                    Menu {
                        MenuRows(createRows)
                    } label: {
                        Image(systemName: Icons.add).toolbarIconFrame()
                    }
                    .accessibilityLabel("Add")
                    .accessibilityIdentifier("libraryAdd")
                    .disabled(shell.libraryPath.isEmpty && shell.homeTab == .favorites)
                }
                BandToolbarButton(systemImage: Icons.history, label: Verbs.history,
                                  identifier: "libraryHistory") { shell.present(.history) }
                MoreMenuButton(id: "libraryMore") { screenMenu.menu }
                    .turnOffPrepareQuestion(turningOff)
            }
            .tint(Palette.ink)
        }
    }
}
