import SwiftData
import SwiftUI

/// The Library home: the Everything/Favorites tab (`ShellState.favoritesOnly`) above one mixed
/// list of folders and pages. Everything is the top level: its folders, the pages played without
/// saving, then the pages in no folder in the top level's sort. Favorites is the starred folders
/// and pages from anywhere in the tree. The band's search (`ShellState.librarySearch`) searches
/// the selected tab across the tree, folders then pages, each by title. Which items each shows is
/// `LibraryQueries`'. A favorite keeps its location; filtered (Favorites or a search) a row shows
/// where it is (`LibraryScreenKey.filtered`).
struct LibraryHomeView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(ShellState.self) private var shell

    @Query(LibraryQueries.playedNotSaved) private var notSaved: [Page]
    @Query private var queriedFolders: [Folder]
    @Query private var queriedPages: [Page]
    let favoritesOnly: Bool
    /// The band's search text ("" when not searching).
    let searchText: String

    private var isFiltered: Bool { favoritesOnly || !searchText.isEmpty }

    init(pageSort: PageSort, favoritesOnly: Bool, searchText: String) {
        self.favoritesOnly = favoritesOnly
        self.searchText = searchText
        if !searchText.isEmpty {
            _queriedFolders = Query(LibraryQueries.searchFolders(searchText, favoritesOnly: favoritesOnly))
            _queriedPages = Query(LibraryQueries.searchPages(searchText, favoritesOnly: favoritesOnly))
        } else if favoritesOnly {
            _queriedFolders = Query(LibraryQueries.favoriteFolders)
            _queriedPages = Query(LibraryQueries.favoritePages)
        } else {
            _queriedFolders = Query(LibraryQueries.folders)
            _queriedPages = Query(LibraryQueries.loosePages(sort: pageSort))
        }
    }

    /// Only folders and pages still in the store: a saved delete can reach the home before its
    /// queries drop them (`isLive`).
    private var folders: [Folder] {
        let live = queriedFolders.filter(\.isLive)
        if !searchText.isEmpty { return live }
        return LibraryStore.ordered(favoritesOnly ? live : LibraryQueries.topLevel(live))
    }

    /// Everything's pages played without saving come first; a search finds them itself.
    private var pages: [Page] {
        (isFiltered ? queriedPages : notSaved + queriedPages).filter(\.isLive)
    }

    var body: some View {
        @Bindable var shell = shell
        let folders = folders
        let pages = pages
        List {
            Section {
                EmptyView()
            } header: {
                Text("Library")
                    .typeStyle(.title, design: .default)
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("libraryTitle")
                    .libraryHeader()
            }
            Section {
                Picker("Library view", selection: $shell.favoritesOnly) {
                    Text("Everything").tag(false)
                    Text("Favorites").tag(true)
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
                .listRowBackground(Palette.chrome)
                ForEach(pages, id: \.listenKey) { page in
                    LibraryPageRow(page: page)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Palette.chrome)
            }
            if folders.isEmpty && pages.isEmpty {
                Section { emptyState }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
        .libraryListStyle()
        .environment(\.libraryScreenKey, isFiltered ? .filtered : .home)
        .animation(Motion.standard, value: pages.map(\.listenKey))
        .navigationTitle("Library")
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("libraryHome")
    }

    @ViewBuilder
    private var emptyState: some View {
        if !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
                .listRowBackground(Color.clear)
        } else if favoritesOnly {
            ContentUnavailableView("No Favorites Yet", systemImage: Icons.favorite,
                                  description: Text("Star a folder or page to find it here."))
                .listRowBackground(Color.clear)
        } else {
            emptyCard
        }
    }

    // MARK: - Empty

    /// An empty Everything: what the toolbar does, with the two first-run actions.
    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Find something to listen to")
                .typeStyle(.row, weight: .semibold)
                .foregroundStyle(Palette.ink)
            Text("Tap 🌐 to find a page, or ＋ to import a book. Pages you save or listen to, books you import and folders you make show up here.")
                .typeStyle(.row)
                .foregroundStyle(Palette.secondaryInk)
            ActionButtonRow { fit in
                PillButton(String(localized: "Browse the web"), shortTitle: String(localized: "Browse"),
                           systemImage: Icons.browser, style: .filled, fit: fit) { shell.leaveLibrary() }
                    .accessibilityIdentifier("libraryEmptyBrowse")
                PillButton(String(localized: "Import a book"), shortTitle: String(localized: "Import"),
                           systemImage: Icons.book, style: .neutral, fit: fit) {
                    BookImportActions(library: library, shell: shell).pickBook(into: nil)
                }
                .accessibilityIdentifier("libraryEmptyImport")
            }
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.chrome, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("libraryEmpty")
    }
}

/// The top level's page sort: the order of the home's pages in no folder, kept on the device
/// (`library.topLevel.sort`; the key is persisted). The home's ⋯ → Sort sets it, and placing a
/// page among them by a drag makes it *Manual*.
enum LibraryTopLevel {
    static let sortKey = "library.topLevel.sort"
    static let defaultSort = PageSort.newest

    /// The sort, outside a view (views read it through `@AppStorage(sortKey)`).
    static var sort: PageSort {
        get { UserDefaults.standard.string(forKey: sortKey).flatMap(PageSort.init(rawValue:)) ?? defaultSort }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: sortKey) }
    }
}

extension View {
    /// A section header in the Library's lists: in line with the cards (no extra header inset).
    func libraryHeader() -> some View {
        textCase(nil)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: Spacing.xs, trailing: 0))
    }

    /// The Library's lists: grouped cards on paper, at the page margin, `Spacing.l` between
    /// sections.
    func libraryListStyle() -> some View {
        listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Palette.paper)
            .contentMargins(.horizontal, Spacing.pageMargin, for: .scrollContent)
            .listSectionSpacing(Spacing.l)
            .environment(\.defaultMinListRowHeight, 0)
    }
}
