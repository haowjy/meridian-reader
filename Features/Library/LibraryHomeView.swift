import SwiftData
import SwiftUI

/// The Library home: the Everything/Favorites filter above one mixed list of folders and pages.
/// The band's search (`ShellState.librarySearch`) applies to the selected tab across the tree; a result outside its
/// usual place shows its path. A favorite keeps its location. Items carry their playback and
/// download state, and folder rows open their normal folder screen.
struct LibraryHomeView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(ShellState.self) private var shell

    @Query(LibraryQueries.playedNotSaved) private var notSaved: [Page]
    @Query private var folders: [Folder]
    @Query private var loosePages: [Page]
    @Query(LibraryQueries.inLibrary) private var allPages: [Page]
    @Query(LibraryQueries.favoritePages) private var favoritePages: [Page]
    @Binding var favoritesOnly: Bool
    /// The band's search text ("" when not searching).
    let searchText: String

    init(pageSort: PageSort, favoritesOnly: Binding<Bool>, searchText: String) {
        _favoritesOnly = favoritesOnly
        self.searchText = searchText
        _loosePages = Query(LibraryQueries.loosePages(sort: pageSort))
    }

    /// Only folders and pages still in the store: a saved delete can reach the home before its
    /// queries drop them (`isLive`).
    private var topLevelFolders: [Folder] {
        LibraryStore.ordered(folders.filter {
            $0.isLive && (favoritesOnly ? $0.isFavorite : $0.parent == nil || !searchText.isEmpty)
                && (searchText.isEmpty || $0.displayName.localizedStandardContains(searchText)
                    || ($0.byline?.localizedStandardContains(searchText) ?? false))
        })
    }

    /// *Pages*: played without saving first, then the pages in no folder.
    private var pages: [Page] {
        let values = favoritesOnly ? favoritePages : searchText.isEmpty ? notSaved + loosePages : notSaved + allPages
        return values.filter { $0.isLive && (searchText.isEmpty || $0.title.localizedStandardContains(searchText)
            || $0.byline.localizedStandardContains(searchText) || $0.excerpt.localizedStandardContains(searchText)) }
    }

    /// Nothing to show but an empty Favorites.
    private var isEmpty: Bool {
        pages.isEmpty && topLevelFolders.isEmpty
    }

    var body: some View {
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
                Picker("Library view", selection: $favoritesOnly) {
                    Text("Everything").tag(false)
                    Text("Favorites").tag(true)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("libraryTabs")
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            Section {
                ForEach(topLevelFolders, id: \.id) { folder in
                    LibraryFolderRow(folder: folder, subtitleOverride: (favoritesOnly || !searchText.isEmpty) ? location(of: folder.parent) : nil)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Palette.chrome)
                ForEach(pages, id: \.listenKey) { page in
                    LibraryPageRow(page: page, subtitleOverride: (favoritesOnly || !searchText.isEmpty) ? location(of: page.folder) : nil)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Palette.chrome)
            }
            if isEmpty {
                Section { emptyState }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
        .libraryListStyle()
        .animation(Motion.standard, value: pages.map(\.listenKey))
        .navigationTitle("Library")
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("libraryHome")
    }

    private func location(of folder: Folder?) -> String? {
        guard let folder else { return String(localized: "Library") }
        return (folder.ancestors.reversed() + [folder]).map(\.displayName).joined(separator: " › ")
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

    /// Below Favorites, low in the list: what the toolbar does, with the two first-run actions.
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
