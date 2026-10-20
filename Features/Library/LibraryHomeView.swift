import SwiftData
import SwiftUI

/// The Library home: the Everything / Favorites / Recent tab (`ShellState.homeTab`) above one
/// mixed list of folders and pages. Everything is the top level of the Library: its folders, then
/// the pages in no folder in the top level's sort. Favorites is the starred folders and pages from
/// anywhere in the tree, in the Library or not. Recent is the pages played without saving, most
/// recent first (no folders). The band's search (`ShellState.librarySearch`), begun on the home,
/// searches the selected tab, folders then pages, each by title. Which items each shows is `LibraryQueries`'. A favorite
/// keeps its location; filtered (a tab other than Everything, or a search) a row shows where it
/// is (`LibraryScreenKey.filtered`).
struct LibraryHomeView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(ShellState.self) private var shell

    @Query private var queriedFolders: [Folder]
    @Query private var queriedPages: [Page]
    let tab: LibraryHomeTab
    /// The band's search text ("" when not searching).
    let searchText: String

    private var isFiltered: Bool { tab != .everything || !searchText.isEmpty }

    init(pageSort: PageSort, tab: LibraryHomeTab, searchText: String) {
        self.tab = tab
        self.searchText = searchText
        if !searchText.isEmpty {
            _queriedFolders = Query(LibraryQueries.searchFolders(searchText, in: tab))
            _queriedPages = Query(LibraryQueries.searchPages(searchText, in: tab))
            return
        }
        switch tab {
        case .everything:
            _queriedFolders = Query(LibraryQueries.folders)
            _queriedPages = Query(LibraryQueries.loosePages(sort: pageSort))
        case .favorites:
            _queriedFolders = Query(LibraryQueries.favoriteFolders)
            _queriedPages = Query(LibraryQueries.favoritePages)
        case .recent:
            _queriedFolders = Query(LibraryQueries.noFolders)
            _queriedPages = Query(LibraryQueries.recent)
        }
    }

    /// Only folders and pages still in the store: a saved delete can reach the home before its
    /// queries drop them (`isLive`).
    private var folders: [Folder] {
        let live = queriedFolders.filter(\.isLive)
        if !searchText.isEmpty { return live }
        return LibraryStore.ordered(tab == .everything ? LibraryQueries.topLevel(live) : live)
    }

    private var pages: [Page] {
        queriedPages.filter(\.isLive)
    }

    var body: some View {
        @Bindable var shell = shell
        let folders = folders
        let pages = pages
        List {
            Section {
                EmptyView()
            } header: {
                ScreenTitle(Verbs.library)
                    .accessibilityIdentifier("libraryTitle")
                    .listHeader()
            }
            Section {
                Picker("Library view", selection: $shell.homeTab) {
                    ForEach(LibraryHomeTab.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("libraryTabs")
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            Section {
                ForEach(folders, id: \.id) { folder in
                    LibraryFolderRow(folder: folder)
                }
                .listRowInsets(EdgeInsets())
                .listCard()
                ForEach(pages, id: \.listenKey) { page in
                    LibraryPageRow(page: page)
                }
                .listRowInsets(EdgeInsets())
                .listCard()
            }
            if folders.isEmpty && pages.isEmpty {
                Section { emptyState }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
        .cardListStyle()
        .statusBarBacking()
        .environment(\.libraryScreenKey, isFiltered ? .filtered(under: nil) : .home)
        .animation(Motion.standard, value: pages.map(\.listenKey))
        .navigationTitle(Verbs.library)
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("libraryHome")
    }

    @ViewBuilder
    private var emptyState: some View {
        if !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
                .listRowBackground(Color.clear)
        } else if tab == .favorites {
            EmptyState(String(localized: "No Favorites Yet"), symbol: Icons.favorite,
                       description: String(localized: "Star a folder or page to find it here."))
                .listRowBackground(Color.clear)
        } else if tab == .recent {
            EmptyState(String(localized: "No Recent Pages Yet"), symbol: Icons.recent,
                       description: String(localized: "Listen to a page without saving it to find it here."))
                .listRowBackground(Color.clear)
        } else {
            emptyCard
        }
    }

    // MARK: - Empty

    /// An empty Everything: what the toolbar does, with the two first-run actions.
    private var emptyCard: some View {
        EmptyState(String(localized: "Find Something to Listen To"), symbol: Icons.library,
                   description: Text("Tap \(Text.symbol(Icons.browser)) to find a page, or \(Text.symbol(Icons.add)) to import an EPUB. Pages you save, EPUBs you import and folders you make show up here.")) {
            ActionButtonRow { fit in
                PillButton(String(localized: "Browse the Web"), shortTitle: String(localized: "Browse"),
                           systemImage: Icons.browser, style: .filled, fit: fit) { shell.leaveLibrary() }
                    .accessibilityIdentifier("libraryEmptyBrowse")
                PillButton(Verbs.importBook, shortTitle: Verbs.import,
                           systemImage: Icons.importFile, style: .neutral, fit: fit) {
                    BookImportActions(library: library, shell: shell).pickBook(into: nil)
                }
                .accessibilityIdentifier("libraryEmptyImport")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("libraryEmpty")
    }
}

/// The top level's page sort: the order of the home's pages in no folder, kept on the device
/// (`library.topLevel.sort`; the key is persisted). The home's ⋯ → Sort sets it, and placing a
/// page among them by a drag makes it *Manual*.
enum LibraryTopLevel {
    static let sortKey = "library.topLevel.sort"
    static let storedKeys = [sortKey]
    static let defaultSort = PageSort.newest

    /// The sort, outside a view (views read it through `@AppStorage(sortKey)`).
    static var sort: PageSort {
        get { UserDefaults.standard.string(forKey: sortKey).flatMap(PageSort.init(rawValue:)) ?? defaultSort }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: sortKey) }
    }
}

extension View {
    /// A screen with no navigation bar (the Library home): paper behind the status bar, so rows
    /// scrolled up pass under it rather than under the clock.
    func statusBarBacking() -> some View {
        // A line with no height at the safe area's top; its paper reaches up through the status
        // bar. (The list itself runs edge to edge, so an overlay of it starts above the clock.)
        safeAreaInset(edge: .top, spacing: 0) {
            Color.clear
                .frame(height: 0)
                .background(Palette.paper.ignoresSafeArea(edges: .top))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

extension LibraryHomeTab {
    /// Its name in the tabs.
    var title: String {
        switch self {
        case .everything: Verbs.library
        case .favorites: Verbs.favorites
        case .recent: String(localized: "Recent")
        }
    }

    /// The band's search field: it searches the tab on screen only (Y11), so it names it.
    var searchPrompt: String {
        Self.searchPrompt(naming: self == .everything ? Verbs.library : title)
    }

    /// "Search Favorites", "Search Demo Finance": the band's field names what it searches, the
    /// home's tab or a folder.
    static func searchPrompt(naming place: String) -> String {
        String(localized: "Search \(place)")
    }
}
