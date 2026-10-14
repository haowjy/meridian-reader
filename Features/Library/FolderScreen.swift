import SwiftData
import SwiftUI

/// One screen for every folder at every depth, Favorites, books and series included (decision
/// D19), and for the top level's pages route (`folder == nil`, with pages played
/// without saving on top): the header, subfolders first (by their order), then pages by the
/// folder's sort (`LibraryPageRow` everywhere, including imported chapters). A folder whose pages play
/// has header actions: *Continue*, *From Start* and *Download*.
/// A folder with details (a book's from its file, or any folder's from *Edit Details*: a cover or
/// an author) has the detailed header top: the cover beside the title, the author before the
/// counts. *Edit*, or *Select* in a row's
/// long-press menu, puts check circles on the rows (and drag handles when the sort is *Manual*);
/// the surface's bottom bar then acts on the selection. Out of
/// Edit, a long press lifts a row to drop on a folder or between rows (`LibraryDrag`); placing a
/// page between pages makes the sort *Manual*.
///
/// ```
/// ‹ Library                Finance                    Edit
/// Finance
/// 2 folders   7 pages
/// ━━━━━━━━━━━━━━━━━━░░░░░░░░░░░░░░░░░░░░░░░░░░░
/// 38%   52 min left
/// ( ▶ Continue  3 of 7       ) ( ⏮ Start ) (⬇)   one line, always (`ActionButtonRow`)
///  📁 Bonds                             4  ›
///  ▣ Coupon Basics                      ✓   ▶
///  ▣ ✓ Finished
///  ▣ Seven-Day Yield                    ⬇   ⏸   ← playing: tinted, with bars
///  ▣ ▂▅▇ Playing
///  🔗  investing.example.com                     (link: lighter, no ▶)
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
        if let folder, !folder.isLive {
            // Deleted: its screen draws once more as the surface leaves it (`isLive`).
            FolderGoneView()
        } else {
            contents
        }
    }

    private var contents: some View {
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

    /// The sort, outside a view (views read it through `@AppStorage(sortKey)`).
    static var sort: PageSort {
        get { UserDefaults.standard.string(forKey: sortKey).flatMap(PageSort.init(rawValue:)) ?? defaultSort }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: sortKey) }
    }
}

/// The folder's list, made with its sort (a query is fixed when its view is made).
private struct FolderContentsList: View {
    let folder: Folder?
    let sort: PageSort

    @Environment(LibraryStore.self) private var library
    @Environment(ShellState.self) private var shell
    @Environment(\.speechController) private var speech
    @Environment(LibraryScreenState.self) private var screen
    @Query private var queriedPages: [Page]
    /// The top level's pages only: pages played without saving, shown above the rest and out of
    /// Edit (they aren't in the Library to move, mark or remove).
    @Query(LibraryQueries.playedNotSaved) private var playedNotSaved: [Page]

    init(folder: Folder?, sort: PageSort) {
        self.folder = folder
        self.sort = sort
        if let folder {
            _queriedPages = Query(LibraryQueries.pages(inFolder: folder.id, sort: sort))
        } else {
            _queriedPages = Query(LibraryQueries.loosePages(sort: sort))
        }
    }

    // Only models still in the store: a saved delete can reach this list before its query or
    // relationship drops them, and the header reads every page (`isLive`).
    private var pages: [Page] { queriedPages.filter(\.isLive) }
    private var subfolders: [Folder] { folder.map { LibraryStore.ordered(($0.children ?? []).filter(\.isLive)) } ?? [] }
    private var isEditing: Bool { screen.isEditing(folderID: folder?.id) }
    private var actions: LibraryActions { LibraryActions(library: library, speech: speech, shell: shell) }
    private var notSaved: [Page] { folder == nil && !isEditing ? playedNotSaved.filter(\.isLive) : [] }

    /// *Select* on a row: Edit, with that row selected.
    private func select(_ item: LibraryItemID) -> () -> Void {
        { [screen, folder] in
            withAnimation(Motion.snappy) {
                screen.beginEditing(folderID: folder?.id)
                screen.selection = [item]
            }
        }
    }

    var body: some View {
        @Bindable var screen = screen
        List(selection: $screen.selection) {
            Section {
                EmptyView()
            } header: {
                header
                    .libraryHeader()
            }
            // One mixed list of compact rows (D23): subfolders, then pages, in one card.
            if !subfolders.isEmpty || !pages.isEmpty || !notSaved.isEmpty {
                Section {
                    ForEach(subfolders, id: \.id) { child in
                        LibraryFolderRow(folder: child, onSelect: select(.folder(child.id)))
                            .tag(LibraryItemID.folder(child.id))
                    }
                    .onMove(perform: isEditing ? moveFolders : nil)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Palette.chrome)
                    ForEach(notSaved, id: \.listenKey) { page in
                        LibraryPageRow(page: page)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Palette.chrome)
                    ForEach(pages, id: \.listenKey) { page in
                        LibraryPageRow(page: page, onSelect: select(.page(page.listenKey)))
                            .tag(LibraryItemID.page(page.listenKey))
                    }
                    .onMove(perform: isEditing && sort == .manual ? movePages : nil)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Palette.chrome)
                }
            }
            if subfolders.isEmpty && pages.isEmpty && notSaved.isEmpty {
                Text("Move pages here, or save them here from the Reader’s 🔖.")
                    .typeStyle(.row)
                    .foregroundStyle(Palette.secondaryInk)
                    .listRowBackground(Color.clear)
            }
        }
        .libraryListStyle()
        .animation(Motion.standard, value: notSaved.map(\.listenKey))
        .environment(\.editMode, .constant(isEditing ? .active : .inactive))
        .accessibilityIdentifier("folderScreen")
    }

    // MARK: - Header

    /// A folder with details (a cover or an author) has a book's header: the cover beside the
    /// title, the author before the counts. Without them, the title and counts.
    @ViewBuilder
    private var header: some View {
        let title = folder?.displayName ?? String(localized: "Pages")
        let style: FolderHeaderStyle = folder?.hasDetails == true ? .detailed(cover: folder?.coverImage) : .folder
        let detail = [folder?.byline].compactMap { $0 } + counts
        Group {
            if let folder, case let playback = progress(of: folder), playback.hasPagesToPlay {
                let bar = playback.header
                FolderHeader(style: style, title: title, detail: detail, progress: bar.fraction, progressLabel: bar.label) {
                    FolderPlayButtons(folder: folder, title: continueTitle(folder, playback), actions: actions)
                }
            } else {
                FolderHeader(style: style, title: title, detail: detail) { EmptyView() }
            }
        }
        .overlay { headerLookMarker(style) }
    }

    #if DEBUG
    /// UI tests: which header shows ("detailed", "detailed with cover", "plain"); the cover tile
    /// itself is hidden from accessibility.
    @ViewBuilder
    private func headerLookMarker(_ style: FolderHeaderStyle) -> some View {
        if LaunchOptions.current.uiTesting {
            let look = switch style {
            case .folder: "plain"
            case .detailed(let cover): cover == nil ? "detailed" : "detailed with cover"
            }
            Color.clear
                .frame(width: 2, height: 2)
                .allowsHitTesting(false)
                .accessibilityElement()
                .accessibilityLabel("Header look")
                .accessibilityValue(look)
                .accessibilityIdentifier("folderHeaderLook")
        }
    }
    #else
    private func headerLookMarker(_ style: FolderHeaderStyle) -> some View { EmptyView() }
    #endif

    /// Where the folder is in its pages (the ones on screen, in this order).
    private func progress(of folder: Folder) -> FolderProgress {
        let playing = actions.playState(of: folder).isCurrent ? speech.activeSessionID : nil
        return FolderProgress(folder: folder, pages: pages, playingKey: playing, library: library)
    }

    /// The round button's title and the lighter place after it: "Continue" "3 of 7", "Playing"
    /// "3 of 7"; "Play" before anything in it has played.
    private func continueTitle(_ folder: Folder, _ progress: FolderProgress) -> (title: String, detail: String?) {
        let place = progress.number.map { "\($0) of \(progress.playingCount)" }
        if actions.playState(of: folder).isCurrent { return (String(localized: "Playing"), place) }
        if folder.currentPageKey == nil { return (String(localized: "Play"), nil) }
        return (String(localized: "Continue"), place)
    }

    /// ["2 folders", "7 pages"].
    private var counts: [String] {
        var parts: [String] = []
        if !subfolders.isEmpty { parts.append("\(subfolders.count) folder\(subfolders.count == 1 ? "" : "s")") }
        parts.append("\(pages.count) page\(pages.count == 1 ? "" : "s")")
        return parts
    }

    private func movePages(from source: IndexSet, to destination: Int) {
        let moving = source.map { pages[$0] }
        shell.attempt(String(localized: "Couldn’t change the order")) {
            try library.arrange(moving, in: folder, before: destination < pages.count ? pages[destination] : nil, shownIn: .manual)
        }
    }

    private func moveFolders(from source: IndexSet, to destination: Int) {
        let all = subfolders
        let moving = source.map { all[$0] }
        shell.attempt(String(localized: "Couldn’t change the order")) {
            try library.arrange(moving, in: folder, before: destination < all.count ? all[destination] : nil)
        }
    }
}
