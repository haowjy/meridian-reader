import SwiftData
import SwiftUI

/// The top of the tree: the title (in the list, so it scrolls away; no navigation bar), the
/// top-level folders (Favorites first), then *Pages*: pages played without saving, marked "Not
/// saved", then the pages in no folder (first five in all, newest first; *Show All* pushes the
/// rest). Nothing here appears or goes away because playback starts or ends: rows carry their own
/// place and ▶, and the Now Playing bar resumes the last thing you heard. A long press lifts a row
/// to drop on a folder or between rows (`LibraryDrag`); placing a page between pages makes the
/// top level's sort *Manual*.
///
/// ```
/// Library                                   title, scrolls away
/// ★  Favorites                        2  ›  folders first, no header
/// ▣  Pride and Prejudice                 ▶  a book: its place and its own ▶
///    Chapter 24   ◐ 6 h 10 min left
/// Pages  3                       Show All ›  the count: a lighter label after the title
/// [i] Notes on Tides                     ▶  played, not saved (D5)
///     example.org   Not saved   ◐ 4 min left
/// [i] Seven-Day Yield                    ▶
/// ```
struct LibraryHomeView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(ShellState.self) private var shell

    @Query(LibraryQueries.playedNotSaved) private var notSaved: [Page]
    @Query private var folders: [Folder]
    @Query private var loosePages: [Page]

    /// How many pages the home shows before *Show All*.
    static let pagesShown = 5

    init(pageSort: PageSort) {
        _loosePages = Query(LibraryQueries.loosePages(sort: pageSort))
    }

    /// Only folders and pages still in the store: a saved delete can reach the home before its
    /// queries drop them (`isLive`).
    private var topLevelFolders: [Folder] {
        LibraryStore.ordered(folders.filter { $0.isLive && $0.parent == nil })
    }

    /// *Pages*: played without saving first, then the pages in no folder.
    private var pages: [Page] { (notSaved + loosePages).filter(\.isLive) }

    /// Nothing to show but an empty Favorites.
    private var isEmpty: Bool {
        pages.isEmpty && topLevelFolders.allSatisfy { $0.kind == .favorites && $0.itemCount == 0 }
    }

    var body: some View {
        let pages = pages
        List {
            Section {
                ForEach(topLevelFolders, id: \.id) { folder in
                    LibraryFolderRow(folder: folder)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Palette.chrome)
            } header: {
                Text("Library")
                    .typeStyle(.title, design: .default)
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("libraryTitle")
                    .libraryHeader()
            }
            if isEmpty {
                Section { emptyCard }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            if !pages.isEmpty {
                Section {
                    ForEach(pages.prefix(Self.pagesShown), id: \.listenKey) { page in
                        LibraryPageRow(page: page)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Palette.chrome)
                } header: {
                    SectionHeader(title: String(localized: "Pages"), count: pages.count,
                                  actionTitle: pages.count > Self.pagesShown ? String(localized: "Show All") : nil,
                                  actionNavigates: true, actionIdentifier: "libraryPagesShowAll") {
                        shell.libraryPath.append(.pages)
                    }
                    .libraryHeader()
                    .accessibilityIdentifier("libraryPagesHeader")
                }
            }
        }
        .libraryListStyle()
        .animation(Motion.standard, value: pages.map(\.listenKey))
        .navigationTitle("Library")
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("libraryHome")
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
            HStack(spacing: Spacing.s) {
                PillButton("Browse the web", style: .filled) { shell.leaveLibrary() }
                    .accessibilityIdentifier("libraryEmptyBrowse")
                PillButton("Import a book", style: .neutral) {
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
