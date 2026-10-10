import SwiftData
import SwiftUI

/// One screen for every folder at every depth, Favorites included, and for the top level's pages
/// (*Pages · Show All*, `folder == nil`): the header, subfolders first (by their order), then
/// pages by the folder's sort. Edit puts check circles on the rows (and drag handles when the
/// sort is *Manual*); the surface's bottom bar then acts on the selection.
///
/// ```
/// ‹ Library                Finance                    Edit
/// Finance
/// 2 folders · 7 pages
///  📁 Bonds                               4
///  [i] Coupon Basics        ✓ Finished       ▶
///  [i] Seven-Day Yield  ▂▅▇ 9 min left       ⏸   ← playing: tinted, with bars
///  [i] investing.example.com  🔗                  (link: lighter, no ▶)
/// ```
struct FolderScreen: View {
    /// nil: the pages in no folder.
    let folder: Folder?

    @Environment(LibraryScreenState.self) private var screen
    @AppStorage(LibraryTopLevel.sortKey) private var topLevelSort = LibraryTopLevel.defaultSort.rawValue

    private var sort: PageSort {
        folder?.pageSort ?? PageSort(rawValue: topLevelSort) ?? LibraryTopLevel.defaultSort
    }

    var body: some View {
        FolderContentsList(folder: folder, sort: sort)
            .navigationTitle(folder?.displayName ?? String(localized: "Pages"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    let editing = screen.isEditing(folderID: folder?.id)
                    Button(editing ? "Done" : "Edit") {
                        withAnimation(Motion.snappy) {
                            if editing { screen.endEditing() } else { screen.beginEditing(folderID: folder?.id) }
                        }
                    }
                    .fontWeight(editing ? .semibold : .regular)
                    .accessibilityIdentifier("folderEdit")
                }
            }
            .onDisappear { if screen.isEditing(folderID: folder?.id) { screen.endEditing() } }
    }
}

/// The top level's page sort, kept on the device (`library.topLevel.sort`; the key is persisted).
enum LibraryTopLevel {
    static let sortKey = "library.topLevel.sort"
    static let defaultSort = PageSort.newest
}

/// The folder's list, made with its sort (a query is fixed when its view is made).
private struct FolderContentsList: View {
    let folder: Folder?
    let sort: PageSort

    @Environment(LibraryStore.self) private var library
    @Environment(ShellState.self) private var shell
    @Environment(LibraryScreenState.self) private var screen
    @Query private var pages: [Page]

    init(folder: Folder?, sort: PageSort) {
        self.folder = folder
        self.sort = sort
        if let folder {
            _pages = Query(LibraryQueries.pages(inFolder: folder.id, sort: sort))
        } else {
            _pages = Query(LibraryQueries.loosePages(sort: sort))
        }
    }

    private var subfolders: [Folder] { folder.map { LibraryStore.ordered($0.children ?? []) } ?? [] }
    private var isEditing: Bool { screen.isEditing(folderID: folder?.id) }

    var body: some View {
        @Bindable var screen = screen
        List(selection: $screen.selection) {
            Section {
                EmptyView()
            } header: {
                FolderHeader(title: folder?.displayName ?? String(localized: "Pages"), detail: counts)
                    .libraryHeader()
                    .padding(.horizontal, -Spacing.pageMargin)
            }
            if !subfolders.isEmpty {
                Section {
                    ForEach(subfolders, id: \.id) { child in
                        LibraryFolderRow(folder: child)
                            .tag(LibraryItemID.folder(child.id))
                    }
                    .onMove(perform: isEditing ? moveFolders : nil)
                    .listRowInsets(.folderRow)
                    .listRowBackground(Palette.chrome)
                }
            }
            if !pages.isEmpty {
                Section {
                    ForEach(pages, id: \.listenKey) { page in
                        LibraryPageRow(page: page)
                            .tag(LibraryItemID.page(page.listenKey))
                    }
                    .onMove(perform: isEditing && sort == .manual ? movePages : nil)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Palette.chrome)
                }
            }
            if subfolders.isEmpty && pages.isEmpty {
                Text(folder?.kind == .favorites
                     ? "Add pages with ☆ in the browser or the Reader."
                     : "Move pages here, or save them here from the Reader’s 🔖.")
                    .typeStyle(.row)
                    .foregroundStyle(Palette.secondaryInk)
                    .listRowBackground(Color.clear)
            }
        }
        .libraryListStyle()
        .environment(\.editMode, .constant(isEditing ? .active : .inactive))
        .accessibilityIdentifier("folderScreen")
    }

    /// "2 folders · 7 pages".
    private var counts: String {
        var parts: [String] = []
        if !subfolders.isEmpty { parts.append("\(subfolders.count) folder\(subfolders.count == 1 ? "" : "s")") }
        parts.append("\(pages.count) page\(pages.count == 1 ? "" : "s")")
        return parts.joined(separator: " · ")
    }

    private func movePages(from source: IndexSet, to destination: Int) {
        let moving = source.map { pages[$0] }
        shell.attempt(String(localized: "Couldn’t change the order")) {
            try library.reorder(moving, in: folder, before: destination < pages.count ? pages[destination] : nil)
        }
    }

    private func moveFolders(from source: IndexSet, to destination: Int) {
        let all = subfolders
        let moving = source.map { all[$0] }
        shell.attempt(String(localized: "Couldn’t change the order")) {
            try library.reorderFolders(moving, in: folder, before: destination < all.count ? all[destination] : nil)
        }
    }
}
