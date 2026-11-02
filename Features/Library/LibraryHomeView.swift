import SwiftData
import SwiftUI

/// The Library home: the title line (with ⋯ on compact width, `LibraryTitleMenu`), then the Library /
/// History tab (`ShellState.homeTab`; History is the `recent` case) above one mixed list of folders
/// and pages. Library (`everything`) is the top level: its folders, then the pages in no folder in
/// the top level's sort. History is the pages played without saving, most recent first (no
/// folders). The band's search (`ShellState.librarySearch`), begun on the home, searches the
/// selected tab, folders then pages, each by title. Which items each shows is `LibraryQueries`'.
/// Filtered (History, or a search) a row shows where it is (`LibraryScreenKey.filtered`).
struct LibraryHomeView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(ShellState.self) private var shell
    @Environment(LibraryScreenState.self) private var screen

    @Query private var queriedFolders: [Folder]
    @Query private var queriedArticles: [Article]
    let tab: LibraryHomeTab
    /// The band's search text ("" when not searching).
    let searchText: String

    private var isFiltered: Bool { tab != .everything || !searchText.isEmpty }

    init(articleSort: ArticleSort, tab: LibraryHomeTab, searchText: String) {
        self.tab = tab
        self.searchText = searchText
        if !searchText.isEmpty {
            _queriedFolders = Query(LibraryQueries.searchFolders(searchText, in: tab))
            _queriedArticles = Query(LibraryQueries.searchArticles(searchText, in: tab))
            return
        }
        switch tab {
        case .everything:
            _queriedFolders = Query(LibraryQueries.folders)
            _queriedArticles = Query(LibraryQueries.looseArticles(sort: articleSort))
        case .recent:
            _queriedFolders = Query(LibraryQueries.noFolders)
            _queriedArticles = Query(LibraryQueries.recent)
        }
    }

    /// Only folders and pages still in the store: a saved delete can reach the home before its
    /// queries drop them (`isLive`).
    private var folders: [Folder] {
        let live = queriedFolders.filter(\.isLive)
        if !searchText.isEmpty { return live }
        return LibraryStore.ordered(tab == .everything ? LibraryQueries.topLevel(live) : live)
    }

    private var articles: [Article] {
        queriedArticles.filter(\.isLive)
    }

    var body: some View {
        @Bindable var shell = shell
        let folders = folders
        let articles = articles
        List {
            Section {
                EmptyView()
            } header: {
                // The tabs sit under the title in its header, not as a row: a row would take the
                // card list's minimum row height.
                VStack(spacing: Spacing.belowTopBar) {
                    TitleLine(title: Verbs.library) { LibraryTitleMenu() }
                        .accessibilityIdentifier("libraryTitle")
                    SegmentedTabs(label: String(localized: "Library view"),
                                  options: LibraryHomeTab.allCases.map { ($0, $0.title) },
                                  selection: $shell.homeTab)
                    .accessibilityIdentifier("libraryTabs")
                }
                .listHeader()
            }
            .headerOnlySection()
            Section {
                ForEach(folders, id: \.id) { folder in
                    LibraryFolderRow(folder: folder)
                }
                .listRowInsets(EdgeInsets())
                .listCard()
                ForEach(articles, id: \.listenKey) { article in
                    LibraryArticleRow(article: article)
                }
                .listRowInsets(EdgeInsets())
                .listCard()
            }
            if folders.isEmpty && articles.isEmpty {
                Section { emptyState }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
        .cardListStyle(underTitleLine: true)
        .statusBarBacking()
        .environment(\.libraryScreenKey, isFiltered ? .filtered(under: nil) : .home)
        .animation(Motion.standard, value: articles.map(\.listenKey))
        .navigationTitle(Verbs.library)
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("libraryHome")
    }

    @ViewBuilder
    private var emptyState: some View {
        if !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
                .listRowBackground(Color.clear)
        } else {
            EmptyState(tab == .recent ? String(localized: "No History") : String(localized: "Start Your Library"),
                       description: tab == .recent
                           ? Text("Articles you listen to show up here.")
                           : Text("Save articles from the web, a file, text or a link.")) {
                AddToLibraryTiles(folder: nil)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .accessibilityIdentifier("libraryEmpty")
        }
    }
}

/// The top level's page sort: the order of the home's pages in no folder, kept on the device
/// (`library.topLevel.sort`; the key is persisted). The home's ⋯ → Sort sets it, and placing a
/// page among them by a drag makes it *Manual*.
enum LibraryTopLevel {
    static let sortKey = "library.topLevel.sort"
    static let storedKeys = [sortKey]
    static let defaultSort = ArticleSort.newest

    /// The sort, outside a view (views read it through `@AppStorage(sortKey)`).
    static var sort: ArticleSort {
        get { UserDefaults.standard.string(forKey: sortKey).flatMap(ArticleSort.init(rawValue:)) ?? defaultSort }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: sortKey) }
    }
}

extension LibraryHomeTab {
    /// Its name in the tabs.
    var title: String {
        switch self {
        case .everything: Verbs.library
        case .recent: Verbs.history
        }
    }

    /// The band's search field: it searches the tab on screen only (Y11), so it names it.
    var searchPrompt: String {
        Self.searchPrompt(naming: self == .everything ? Verbs.library : title)
    }

    /// "Search History", "Search Demo Finance": the band's field names what it searches, the
    /// home's tab or a folder.
    static func searchPrompt(naming place: String) -> String {
        String(localized: "Search \(place)")
    }
}
