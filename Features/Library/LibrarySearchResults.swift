import SwiftData
import SwiftUI

/// The Library's search: folders (by name, or a book's author) and pages (titles, sites and
/// excerpts) across the whole tree, then *Search the web for "…"*, which opens the browser.
/// Shown over the Library's screens while the search field has text.
struct LibrarySearchResults: View {
    let text: String
    /// A folder or *Search the web* was picked: the search ends. (A page opens over the results,
    /// which stay underneath.)
    let onPick: () -> Void

    @Environment(LibraryStore.self) private var library
    @Environment(ShellState.self) private var shell
    @Query private var pages: [Page]
    @Query private var folders: [Folder]

    init(text: String, onPick: @escaping () -> Void) {
        self.text = text
        self.onPick = onPick
        _pages = Query(LibraryQueries.search(text))
    }

    private var matchedFolders: [Folder] {
        folders.filter {
            $0.displayName.localizedStandardContains(text) || ($0.byline?.localizedStandardContains(text) ?? false)
        }
        .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    var body: some View {
        List {
            let found = matchedFolders
            if !found.isEmpty {
                Section {
                    ForEach(found, id: \.id) { folder in
                        Button { open(folder) } label: {
                            ListRow(kind: .folder(symbol: folder.rowSymbol, count: folder.itemCount, cover: folder.coverImage),
                                    title: folder.displayName, subtitle: location(of: folder.parent))
                        }
                        .buttonStyle(.plain)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Palette.chrome)
                } header: {
                    SectionHeader(title: String(localized: "Folders")).libraryHeader()
                }
            }
            if !pages.isEmpty {
                Section {
                    ForEach(pages, id: \.listenKey) { page in
                        LibraryPageRow(page: page)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Palette.chrome)
                } header: {
                    SectionHeader(title: String(localized: "Pages")).libraryHeader()
                }
            }
            Section {
                Button(action: searchTheWeb) {
                    Label("Search the web for “\(text)”", systemImage: "globe")
                        .typeStyle(.row)
                        .foregroundStyle(Palette.accent)
                        .frame(maxWidth: .infinity, minHeight: BottomChrome.minTapTarget, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("librarySearchWeb")
                .listRowBackground(Palette.chrome)
            }
        }
        .libraryListStyle()
        .accessibilityIdentifier("librarySearchResults")
    }

    /// "in Fiction › Short stories"; nil at the top level.
    private func location(of folder: Folder?) -> String? {
        guard let folder else { return nil }
        let names = (folder.ancestors.reversed() + [folder]).map(\.displayName)
        return "in " + names.joined(separator: " › ")
    }

    private func open(_ folder: Folder) {
        onPick()
        shell.showLibrary(at: library.path(to: folder))
    }

    private func searchTheWeb() {
        guard let url = BrowseURLParser.destination(from: text) else { return }
        onPick()
        shell.navigate(to: url)
    }
}

extension LibraryStore {
    /// The Library's path to `folder`: the folders above it, then it.
    func path(to folder: Folder) -> [LibraryRoute] {
        (folder.ancestors.reversed() + [folder]).map { .folder($0.id) }
    }
}
