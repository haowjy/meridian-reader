import SwiftData
import SwiftUI

/// One screen for every folder at every depth, books and followed stories included (decision
/// D19): the header, subfolders first (by their order), then pages by the folder's sort
/// (`LibraryPageRow` everywhere, including imported chapters). The header is centred
/// (`FolderHeader`): a folder with details (a book's from its file, or any folder's from *Edit
/// Details*: a cover or an author) has its cover above the title, the author before the counts.
/// A followed story has its status line (Follow). A folder whose pages play has the action row:
/// its Download control (the folder's Download toggle, F7), the big ▶ (Continue) and *More* (the
/// folder's menu, as its row's ⋯). *Edit*, or *Select* in a row's menu, puts check circles on the
/// rows (and drag handles when the sort is *Manual*); the surface's bottom bar then acts on the
/// selection. Out of Edit, a long press lifts a row to drop on a folder or between rows
/// (`LibraryDrag`); placing a page between pages makes the sort *Manual*.
///
/// The name shows once, in the header; the navigation bar's title stays blank until the
/// header's title scrolls under it.
///
/// ```
/// ‹                                                   Edit
///                         Finance
///                    2 folders   7 pages
///                  3 of 7   38%   52 min left
///                ◯↓         ( ▶ )         ⋯
///             Download                   More
///  📁 Bonds                                ⋯
///     4 pages
///  ▣ Coupon Basics                         ⋯
///  ▣ ✓ ✓ Finished                               ← downloaded, finished
///  ▣ Seven-Day Yield                       ⋯   ← playing: tinted, with bars
///  ▣ ▂▅▇ Playing
///  🔗  investing.example.com                ⋯   (link: lighter)
/// ```
struct FolderScreen: View {
    let folder: Folder

    @Environment(LibraryScreenState.self) private var screen
    /// The header's title has scrolled under the navigation bar: the bar shows the name.
    @State private var headerTitleHidden = false

    var body: some View {
        if !folder.isLive {
            // Deleted: its screen draws once more as the surface leaves it (`isLive`).
            FolderGoneView()
        } else {
            contents
        }
    }

    private var contents: some View {
        FolderContentsList(folder: folder, sort: folder.pageSort, headerTitleHidden: $headerTitleHidden)
            // The title names the screen for VoiceOver, the back button and tests; drawn only
            // once the header's own title has scrolled away.
            .navigationTitle(folder.name)
            .navigationBarTitleDisplayMode(.inline)
            .modifier(BarTitleRemoved())
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(folder.name)
                        .typeStyle(.row, weight: .semibold)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .opacity(headerTitleHidden ? 1 : 0)
                        .animation(Motion.snappy, value: headerTitleHidden)
                        .accessibilityHidden(!headerTitleHidden)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    let editing = screen.isEditing(folderID: folder.id)
                    Button(editing ? Verbs.done : Verbs.edit) {
                        withAnimation(Motion.snappy) {
                            if editing { screen.endEditing() } else { screen.beginEditing(folderID: folder.id) }
                        }
                    }
                    .fontWeight(editing ? .semibold : .regular)
                    .accessibilityIdentifier("folderEdit")
                }
            }
            .onDisappear { if screen.isEditing(folderID: folder.id) { screen.endEditing() } }
    }
}

/// The navigation bar draws no title of its own (the principal item stands in for it); the
/// screen keeps its `navigationTitle` for VoiceOver and the back button. Before iOS 18 the bar
/// shows its title as well.
private struct BarTitleRemoved: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.toolbar(removing: .title)
        } else {
            content
        }
    }
}

/// The folder's list, made with its sort (a query is fixed when its view is made).
private struct FolderContentsList: View {
    let folder: Folder
    let sort: PageSort

    @Environment(LibraryStore.self) private var library
    @Environment(ShellState.self) private var shell
    @Environment(FollowCenter.self) private var follow
    @Environment(\.speechController) private var speech
    @Environment(LibraryScreenState.self) private var screen
    @Environment(DownloadCenter.self) private var downloads
    @Query private var queriedPages: [Page]

    @Binding var headerTitleHidden: Bool
    /// *Turn Off Download* asked from the header's Download control, or from *More*: the question
    /// shows by the control that asked.
    @State private var turningOffFromControl: Folder?
    @State private var turningOffFromMore: Folder?
    /// Where the list's visible content starts (under the navigation bar), in global coordinates.
    @State private var contentTop: CGFloat = 0
    @ScaledMetric(relativeTo: TypeStyle.title.relativeTo) private var titleLineHeight = TypeStyle.title.lineHeight

    init(folder: Folder, sort: PageSort, headerTitleHidden: Binding<Bool>) {
        self.folder = folder
        self.sort = sort
        _headerTitleHidden = headerTitleHidden
        _queriedPages = Query(LibraryQueries.pages(inFolder: folder.id, sort: sort))
    }

    // Only models still in the store: a saved delete can reach this list before its query or
    // relationship drops them, and the header reads every page (`isLive`).
    private var pages: [Page] { queriedPages.filter(\.isLive) }
    private var subfolders: [Folder] { LibraryStore.ordered((folder.children ?? []).filter(\.isLive)) }
    private var isEditing: Bool { screen.isEditing(folderID: folder.id) }
    private var actions: LibraryActions { LibraryActions(library: library, speech: speech, shell: shell, follow: follow) }

    /// *Select* on a row: Edit, with that row selected.
    private func select(_ item: LibraryItemID) -> () -> Void {
        { [screen, folder] in
            withAnimation(Motion.snappy) {
                screen.beginEditing(folderID: folder.id)
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
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { top in
                        let hidden = top + titleLineHeight < contentTop
                        if hidden != headerTitleHidden { headerTitleHidden = hidden }
                    }
                    .listHeader()
            }
            // One mixed list of compact rows (D23): subfolders, then pages, in one card.
            if !subfolders.isEmpty || !pages.isEmpty {
                Section {
                    ForEach(subfolders, id: \.id) { child in
                        LibraryFolderRow(folder: child, onSelect: select(.folder(child.id)))
                            .tag(LibraryItemID.folder(child.id))
                    }
                    .onMove(perform: isEditing ? moveFolders : nil)
                    .listRowInsets(EdgeInsets())
                    .listCard()
                    ForEach(pages, id: \.listenKey) { page in
                        LibraryPageRow(page: page, onSelect: select(.page(page.listenKey)))
                            .tag(LibraryItemID.page(page.listenKey))
                    }
                    .onMove(perform: isEditing && sort == .manual ? movePages : nil)
                    .listRowInsets(EdgeInsets())
                    .listCard()
                }
            }
            if subfolders.isEmpty && pages.isEmpty {
                // A header, like the folder's own: on the page margin, unclipped by a cell.
                Section {
                    EmptyView()
                } header: {
                    Text("Move pages here, or save them here from the Reader’s \(Text.symbol(Icons.save)).")
                        .typeStyle(.row)
                        .foregroundStyle(Palette.secondaryInk)
                        .accessibilityIdentifier("folderEmpty")
                        .listHeader()
                }
            }
        }
        .cardListStyle()
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY + $0.safeAreaInsets.top } action: {
            contentTop = $0
        }
        .environment(\.editMode, .constant(isEditing ? .active : .inactive))
        .accessibilityIdentifier("folderScreen")
    }

    // MARK: - Header

    /// The centred header (`FolderHeader`): the cover for a folder with details, the title,
    /// details and where it is; a followed story's status (`FollowStatus`); then, when its pages
    /// play, the Download control, the big ▶ and *More*.
    private var header: some View {
        let style: FolderHeaderStyle = folder.hasDetails ? .detailed(cover: folder.coverImage) : .folder
        let detail = [folder.byline].compactMap { $0 } + counts
        let playback = actions.progress(of: folder, pages: pages)
        return FolderHeader(style: style, title: folder.name, detail: detail,
                            progressLabel: playback.hasPagesToPlay ? playback.headerLine : [],
                            actions: playback.hasPagesToPlay ? headerActions : nil) {
            if folder.kind == .series { FollowStatus(folder: folder, pages: pages) }
        } more: {
            FolderMenu(folder: folder, pages: pages, actions: actions, downloads: downloads, screen: screen,
                       onTurnOffDownload: { turningOffFromMore = folder })
        } anchor: { control in
            Color.clear.turnOffDownloadQuestion(control == .download ? $turningOffFromControl : $turningOffFromMore)
        }
    }

    /// The Download control, the ▶ (`LibraryActions.playFolder`) and their states. The control
    /// downloads when it shows ↓, the toggle on or off (turning it on, and listing again pages
    /// whose downloads were deleted, P8); downloading or downloaded with the toggle on, it asks to
    /// turn it off (`DownloadCenter.turnOff`: what is downloaded stays); downloaded with the
    /// toggle off, it turns it on and nothing is downloaded again (`DownloadCenter.download`: new
    /// pages download).
    private var headerActions: FolderHeaderActions {
        let state = downloads.state(of: folder, pages: pages)
        let isOn = downloads.isOn(folder)
        return FolderHeaderActions(download: state, downloadIsOn: isOn, onDownload: {
            if isOn && state != .notDownloaded {
                turningOffFromControl = folder
            } else {
                DownloadActions(downloads: downloads, shell: shell).download(folder)
            }
        }, play: actions.playState(of: folder), onPlay: { actions.playFolder(folder) })
    }

    /// ["2 folders", "7 pages"] ("7 chapters" in a book or series); none for an empty folder,
    /// whose list says so.
    private var counts: [String] {
        guard !subfolders.isEmpty || !pages.isEmpty else { return [] }
        var parts: [String] = []
        if !subfolders.isEmpty { parts.append("\(subfolders.count) folder\(subfolders.count == 1 ? "" : "s")") }
        parts.append(folder.itemCount(pages.count))
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
