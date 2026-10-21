import SwiftData
import SwiftUI

/// One screen for every folder at every depth, books and followed stories included (decision
/// D19): the header, subfolders first (by their order), then pages by the folder's sort
/// (`LibraryArticleRow` everywhere, including imported chapters). The header is centred
/// (`FolderHeader`): a folder with details (a book's from its file, or any folder's from *Edit
/// Details*: a cover or an author) has its cover above the title, the author before the counts.
/// A followed story has its status line (Follow). A folder whose pages play has the action row:
/// its Prepare control (the folder's Prepare toggle, F7), the big ▶ (Continue) and *More* (the
/// folder's menu, as its row's ⋯). *Edit*, or *Select* in a row's menu, puts check circles on the
/// rows (and drag handles when the sort is *Manual*); the surface's bottom bar then acts on the
/// selection. Out of Edit, a long press lifts a row to drop on a folder or between rows
/// (`LibraryDrag`); placing a page between pages makes the sort *Manual*.
///
/// The name shows once, in the header; the navigation bar's title stays blank until the
/// header's title scrolls under it. The band's search, begun here, searches everything under the
/// folder (`FolderSearchResults`) in the list's place.
///
/// ```
/// ‹                                                   Edit
///                         Finance
///                    2 folders   7 pages
///                  3 of 7   38%   52 min left
///                ◯↓         ( ▶ )         ⋯
///             Prepare                   More
///  📁 Bonds                                ⋯
///     4 pages
///  ▣ Coupon Basics                      ●  ⋯
///  ▣ ↓ Finished                                 ← prepared, finished (● the ring, full)
///  ▣ Seven-Day Yield                   ▂▅▇ ⋯   ← playing: tinted, with bars
///  ▣ Playing                                     (marks in the trailing listening column)
///  🔗  investing.example.com                ⋯   (link: lighter)
/// ```
struct FolderScreen: View {
    let folder: Folder

    @Environment(LibraryScreenState.self) private var screen
    @Environment(ShellState.self) private var shell
    /// The header's title has scrolled under the navigation bar: the bar shows the name.
    @State private var headerTitleHidden = false

    /// The band's search text while it searches this folder ("" otherwise).
    private var searchText: String {
        shell.librarySearch.isActive && shell.librarySearchFolder == folder.id ? shell.librarySearch.text : ""
    }

    var body: some View {
        if !folder.isLive {
            // Deleted: its screen draws once more as the surface leaves it (`isLive`).
            FolderGoneView()
        } else {
            contents
        }
    }

    private var contents: some View {
        let searching = !searchText.isEmpty
        return Group {
            if searching {
                FolderSearchResults(folder: folder, text: searchText)
            } else {
                FolderContentsList(folder: folder, sort: folder.articleSort, headerTitleHidden: $headerTitleHidden)
            }
        }
            // The title names the screen for VoiceOver, the back button and tests; drawn only
            // once the header's own title has scrolled away, and never over search results, which
            // carry the name themselves.
            .navigationTitle(folder.name)
            .navigationBarTitleDisplayMode(.inline)
            .modifier(BarTitleRemoved())
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(folder.name)
                        .typeStyle(.row, weight: .semibold)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .opacity(headerTitleHidden && !searching ? 1 : 0)
                        .animation(Motion.snappy, value: headerTitleHidden && !searching)
                        .accessibilityHidden(!headerTitleHidden || searching)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    let editing = screen.isEditing(folderID: folder.id)
                    Button(editing ? Verbs.done : Verbs.edit) {
                        withAnimation(Motion.snappy) {
                            if editing { screen.endEditing() } else { screen.beginEditing(folderID: folder.id) }
                        }
                    }
                    .fontWeight(editing ? .semibold : .regular)
                    .disabled(searching)
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
    let sort: ArticleSort

    @Environment(LibraryStore.self) private var library
    @Environment(ShellState.self) private var shell
    @Environment(FollowCenter.self) private var follow
    @Environment(\.speechController) private var speech
    @Environment(LibraryScreenState.self) private var screen
    @Environment(PrepareCenter.self) private var preparedAudio
    @Query private var queriedArticles: [Article]

    @Binding var headerTitleHidden: Bool
    /// *Turn Off Prepare* asked from the header's Prepare control, or from *More*: the question
    /// shows by the control that asked.
    @State private var turningOffFromControl: Folder?
    @State private var turningOffFromMore: Folder?
    /// Where the list's visible content starts (under the navigation bar), in global coordinates.
    @State private var contentTop: CGFloat = 0
    @ScaledMetric(relativeTo: TypeStyle.title.relativeTo) private var titleLineHeight = TypeStyle.title.lineHeight

    init(folder: Folder, sort: ArticleSort, headerTitleHidden: Binding<Bool>) {
        self.folder = folder
        self.sort = sort
        _headerTitleHidden = headerTitleHidden
        _queriedArticles = Query(LibraryQueries.articles(inFolder: folder.id, sort: sort))
    }

    // Only models still in the store: a saved delete can reach this list before its query or
    // relationship drops them, and the header reads every page (`isLive`).
    private var articles: [Article] { queriedArticles.filter(\.isLive) }
    private var subfolders: [Folder] { LibraryStore.ordered((folder.children ?? []).filter(\.isLive)) }
    private var isEditing: Bool { screen.isEditing(folderID: folder.id) }
    private var actions: LibraryActions { LibraryActions(library: library, speech: speech, shell: shell, follow: follow) }

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
            if !subfolders.isEmpty || !articles.isEmpty {
                Section {
                    ForEach(subfolders, id: \.id) { child in
                        LibraryFolderRow(folder: child)
                            .tag(LibraryItemID.folder(child.id))
                    }
                    .onMove(perform: isEditing ? moveFolders : nil)
                    .listRowInsets(EdgeInsets())
                    .listCard()
                    ForEach(articles, id: \.listenKey) { article in
                        LibraryArticleRow(article: article)
                            .tag(LibraryItemID.article(article.listenKey))
                    }
                    .onMove(perform: isEditing && sort == .manual ? moveArticles : nil)
                    .listRowInsets(EdgeInsets())
                    .listCard()
                }
            }
            if subfolders.isEmpty && articles.isEmpty {
                // Every empty list says so the same way (`EmptyState`), under the folder's header.
                Section {
                    EmptyState(String(localized: "This Folder Is Empty"), symbol: Icons.folder,
                               description: Text("Move articles here, or save them here from the Reader’s \(Text.symbol(Icons.save))."))
                        .accessibilityIdentifier("folderEmpty")
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
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
    /// play, the Prepare control, the big ▶ and *More*.
    private var header: some View {
        let style: FolderHeaderStyle = folder.hasDetails ? .detailed(cover: folder.coverImage) : .folder
        let playback = actions.progress(of: folder, articles: articles)
        // Not started, the length joins the details ("Demo Author   4 chapters   4 min", C96);
        // once started, the line says where it is.
        let line = playback.hasArticlesToPlay ? playback.headerLine : []
        let lengthOnly = playback.hasArticlesToPlay && playback.fraction == nil
        let detail = [folder.byline].compactMap { $0 } + counts + (lengthOnly ? line : [])
        return FolderHeader(style: style, title: folder.name, detail: detail,
                            progressLabel: lengthOnly ? [] : line,
                            actions: playback.hasArticlesToPlay ? headerActions : nil) {
            if folder.kind == .series { FollowStatus(folder: folder, articles: articles) }
        } more: {
            FolderMenu(folder: folder, articles: articles, actions: actions, preparedAudio: preparedAudio, screen: screen,
                       place: .header, progress: playback, onTurnOffPrepare: { turningOffFromMore = folder },
                       onMoved: { shell.libraryPath = library.path(to: folder) })
        } anchor: { control in
            Color.clear.turnOffPrepareQuestion(control == .prepare ? $turningOffFromControl : $turningOffFromMore)
        }
    }

    /// The Prepare control, the ▶ (`LibraryActions.playFolder`) and their states. The control
    /// prepared audio when it shows ↓, the toggle on or off (turning it on, and listing again pages
    /// whose prepared audio were deleted, P8); preparing or prepared with the toggle on, it asks to
    /// turn it off (`PrepareCenter.turnOff`: what is prepared stays); prepared with the
    /// toggle off, it turns it on and nothing is prepared again (`PrepareCenter.prepare`: new
    /// pages prepare).
    private var headerActions: FolderHeaderActions {
        let state = preparedAudio.state(of: folder, articles: articles)
        let isOn = preparedAudio.isOn(folder)
        let record = preparedAudio.record(for: .folder(folder.id))
        let running = record.map { $0.hasQueuedArticles } ?? false
        // While it prepared audio, the caption is the count and a tap opens Prepared audio (C96).
        let caption = running ? record.map { String(localized: "\($0.finishedCount) of \($0.entries.count)") } : nil
        return FolderHeaderActions(prepare: state, prepareIsOn: isOn, onPrepare: {
            if running && state != .prepared {
                shell.present(.preparedAudio)
            } else if isOn && state != .notPrepared {
                turningOffFromControl = folder
            } else {
                PrepareActions(preparedAudio: preparedAudio, shell: shell).prepare(folder)
            }
        }, prepareCaption: caption, play: actions.playState(of: folder), onPlay: { actions.playFolder(folder) })
    }

    /// ["2 folders", "7 articles"] ("7 chapters" in an imported EPUB); none for an empty folder,
    /// whose list says so.
    private var counts: [String] {
        guard !subfolders.isEmpty || !articles.isEmpty else { return [] }
        var parts: [String] = []
        if !subfolders.isEmpty { parts.append("\(subfolders.count) folder\(subfolders.count == 1 ? "" : "s")") }
        parts.append(folder.itemCount(articles.count))
        return parts
    }

    private func moveArticles(from source: IndexSet, to destination: Int) {
        let moving = source.map { articles[$0] }
        shell.attempt(String(localized: "Couldn’t change the order")) {
            try library.arrange(moving, in: folder, before: destination < articles.count ? articles[destination] : nil, shownIn: .manual)
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

/// A search begun on a folder's screen: under the folder's name (as the home keeps its title over
/// its results), the folders and pages under it, at any depth, that the home's search on
/// Everything finds (`LibraryQueries.searchFolders` / `searchArticles`), folders first, each row
/// showing where it is below the folder (`LibraryScreenKey.filtered(under:)`).
private struct FolderSearchResults: View {
    let folder: Folder
    let text: String

    @Query private var queriedFolders: [Folder]
    @Query private var queriedArticles: [Article]

    init(folder: Folder, text: String) {
        self.folder = folder
        self.text = text
        _queriedFolders = Query(LibraryQueries.searchFolders(text, in: .everything))
        _queriedArticles = Query(LibraryQueries.searchArticles(text, in: .everything))
    }

    private func isUnder(_ other: Folder?) -> Bool {
        guard let other else { return false }
        return other === folder || other.ancestors.contains { $0 === folder }
    }

    var body: some View {
        let folders = queriedFolders.filter { $0.isLive && isUnder($0.parent) }
        let articles = queriedArticles.filter { $0.isLive && isUnder($0.folder) }
        List {
            Section {
                EmptyView()
            } header: {
                ScreenTitle(folder.name)
                    .lineLimit(2)
                    .listHeader()
            }
            if folders.isEmpty && articles.isEmpty {
                ContentUnavailableView.search(text: text)
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(folders, id: \.id) { LibraryFolderRow(folder: $0) }
                        .listRowInsets(EdgeInsets())
                        .listCard()
                    ForEach(articles, id: \.listenKey) { LibraryArticleRow(article: $0) }
                        .listRowInsets(EdgeInsets())
                        .listCard()
                }
            }
        }
        .cardListStyle()
        .environment(\.libraryScreenKey, .filtered(under: folder.id))
        .accessibilityIdentifier("folderSearchResults")
    }
}
