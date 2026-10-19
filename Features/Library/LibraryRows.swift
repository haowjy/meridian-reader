import SwiftUI

/// A page row: a saved page, a link (lighter, 🔗), a followed story's chapter waiting for its
/// text (a link with its status: "Fetching text…", "Retrying in 1:52", "Waiting"), or a page
/// played without saving. Every page uses this same row, including imported chapters: two lines,
/// the title and then its site and status (decision D21). In a book or series the second line is
/// the status alone ("5 min", "Skipped", "Playing"): its header already names the author or site,
/// so rows don't repeat it. Front matter is dimmed and "Skipped" (any page skipped in playback is).
///
/// Tapping the row plays it (`LibraryActions.play`; a waiting chapter is fetched first), except
/// the page you hear, which opens Now Playing, so a stray tap never pauses it, and a link that
/// can't play, which opens in the browser. Its only control is ⋯ (`PageMenu`), the same menu as
/// its long press (decision D11), whose first row, *Read*, opens it. Its download shows on the
/// row (`DownloadCenter.state(of:)`): dimmed under a jade ↓ while downloading, a grey ✓ once
/// downloaded. Swipe left removes it from the Library, and from every list it shows in
/// (`LibraryQueries`). A page in the Library lifts into a drag from the long press, to be filed in
/// a folder or placed between rows (`LibraryDrag`), a chapter as any page (decision D19); not on
/// the home's Favorites tab or in search results (`LibraryScreenKey.filtered`), where a page in a
/// folder shows the folder's path instead of its site. While its screen is in Edit the List's
/// selection takes the tap, and the row has no ⋯.
struct LibraryPageRow: View {
    let page: Page
    /// *Select* in the menu: enters Edit with this row selected (folder screens only).
    var onSelect: (() -> Void)?

    @Environment(LibraryStore.self) private var library
    @Environment(\.speechController) private var speech
    @Environment(ShellState.self) private var shell
    @Environment(FollowCenter.self) private var follow
    @Environment(DownloadCenter.self) private var downloads
    @Environment(LibraryScreenState.self) private var screen
    @Environment(\.editMode) private var editMode
    @Environment(\.libraryScreenKey) private var screenKey

    private var actions: LibraryActions { LibraryActions(library: library, speech: speech, shell: shell, follow: follow) }
    private var isEditing: Bool { editMode?.wrappedValue.isEditing == true }
    private var dragID: LibraryItemID? {
        guard !screenKey.isFiltered, !isEditing, page.isInLibrary else { return nil }
        return .page(page.listenKey)
    }
    /// ★ after a favorite's title, except in the Favorites list, where every row is one.
    private var marksFavorite: Bool { !(screenKey == .filtered(under: nil) && shell.homeTab == .favorites) }

    var body: some View {
        if !page.isLive {
            DeletedRow()
        } else if case .retrying? = chapterStatus {
            // "Retrying in 1:52" counts down.
            TimelineView(.periodic(from: .now, by: 1)) { context in liveBody(now: context.date) }
        } else {
            liveBody(now: .now)
        }
    }

    /// A followed story's chapter waiting for its text: where it stands.
    private var chapterStatus: FollowCenter.ChapterStatus? { follow.status(of: page) }

    /// A followed story's chapter says where its text stands ("Fetching text…", "Waiting").
    private func note(now: Date) -> String? {
        chapterStatus.map { FollowText.rowNote($0, now: now) }
    }

    /// A tap: the page you hear opens Now Playing, a link that can't play opens in the browser
    /// (`LibraryActions.open`); anything else plays (a waiting chapter once fetched).
    private func activate() {
        if playState.isCurrent || (page.isLink && !page.isWaitingChapter) {
            actions.open(page)
        } else {
            actions.play(page)
        }
    }

    private var menu: PageMenu {
        PageMenu(actions: PageActions(page: page, library: library, shell: shell, speech: speech, downloads: downloads,
                                      follow: follow),
                 place: .list(onSelect: onSelect))
    }

    private var playState: PlayState {
        guard page.isLink else { return actions.playState(of: page) }
        return follow.playWhenFetched == page.listenKey ? .preparing : .idle
    }

    private func liveBody(now: Date) -> some View {
        ListRow(kind: kind, title: page.lineOne, subtitle: subtitle, note: note(now: now),
                progress: page.isLink ? .unplayed(minutes: nil) : actions.progress(of: page),
                playState: playState,
                insertionEdge: screen.insertion?.id == .page(page.listenKey) ? screen.insertion?.edge : nil,
                download: downloads.state(of: page), isFavorite: marksFavorite && page.isFavorite,
                menu: isEditing ? nil : AnyView(menu))
            .opensOnTap(isEditing ? nil : activate)
            .libraryDropRow(.page(page.listenKey), in: screen)
            .libraryDrag(dragID, in: screen)
            .contextMenu { menu }
            .swipeActions(edge: .trailing) {
                // The menu's remove: *Remove from Library* in the Library, *Remove from Recent* in
                // Recent. The row leaves every list once the remove is stored; a save that fails
                // keeps it, with a toast. So no role, which would take the row out first.
                menu.rows.swipeRow("menuSave", "menuRemoveFromRecent")?.swipeButton()
            }
    }

    private var kind: ListRow.Kind {
        if page.isLink { return .link }
        return .page(artwork: page.artworkImage, letter: page.artworkLetter)
    }

    /// Where it is on a filtered list, which gathers rows from many folders (its folder's path, on
    /// a folder's search from below it); elsewhere its site, as everywhere else, but nothing in a
    /// book or series, whose header names the source once (a folder you made mixes sites).
    /// Untitled, its title line is already its site.
    private var subtitle: String? {
        if let place = screenKey.place(of: page.folder) { return place }
        if page.isChapter { return nil }
        return PageTitle.lineTwoSource(title: page.givenTitle, source: page.byline)
    }
}

/// A folder row (a folder you made, a book or series, all alike: decision D19): a tap pushes
/// its screen. Its cover, when it has one (a book's, or one given in *Edit Details*), stands in
/// for the symbol. A folder whose pages play shows its place (the page it is at) and the time
/// left; any other folder shows its count. Its only control is ⋯ (`FolderMenu`, with *Continue*
/// and *Play from Start*), the same menu as its long press, which also lifts it into a drag; a
/// dragged row let go on it is filed in it. Its download shows as a page's does: dimmed under a
/// jade ↓ while its download runs, a grey ✓ once every page it covers is downloaded; Download
/// itself is in its screen's header. Swipe left asks to delete it. On the home's Favorites tab or in search results
/// (`LibraryScreenKey.filtered`) a nested folder shows its parents' path, opens under them, so ‹
/// goes to its parent, and doesn't lift.
struct LibraryFolderRow: View {
    let folder: Folder
    /// *Select* in the menu: enters Edit with this row selected (folder screens only).
    var onSelect: (() -> Void)?

    @Environment(LibraryStore.self) private var library
    @Environment(\.speechController) private var speech
    @Environment(ShellState.self) private var shell
    @Environment(FollowCenter.self) private var follow
    @Environment(DownloadCenter.self) private var downloads
    @Environment(LibraryScreenState.self) private var screen
    @Environment(\.editMode) private var editMode
    @Environment(\.libraryScreenKey) private var screenKey
    /// Its menu's *Turn Off Download* asked: the question shows by its ⋯.
    @State private var turningOff: Folder?

    private var actions: LibraryActions { LibraryActions(library: library, speech: speech, shell: shell, follow: follow) }
    private var isEditing: Bool { editMode?.wrappedValue.isEditing == true }
    private var isFiltered: Bool { screenKey.isFiltered }
    /// Where it is on a filtered list (`LibraryScreenKey.place(of:)`; nil at the top level).
    private var location: String? { screenKey.place(of: folder.parent) }
    /// ★ after a favorite's title, except in the Favorites list, where every row is one.
    private var marksFavorite: Bool { !(screenKey == .filtered(under: nil) && shell.homeTab == .favorites) }

    var body: some View {
        if folder.isLive { liveBody } else { DeletedRow() }
    }

    @ViewBuilder private var liveBody: some View {
        let pages = folder.playOrder
        let progress = actions.progress(of: folder, pages: pages)
        let menu = FolderMenu(folder: folder, pages: pages, actions: actions, downloads: downloads, screen: screen,
                              onTurnOffDownload: { turningOff = folder }, onSelect: onSelect)
        opening(row(progress, download: downloads.state(of: folder, pages: pages), menu: isEditing ? nil : AnyView(menu)))
            .accessibilityIdentifier("folderRow")
            .libraryDropRow(.folder(folder.id), in: screen)
            .libraryDrag(isEditing || isFiltered ? nil : .folder(folder.id), in: screen)
            .contextMenu { menu }
            .swipeActions(edge: .trailing) {
                // The menu's *Delete Folder…*: it asks first, so the row can stay (no role).
                menu.rows.swipeRow("menuDeleteFolder")?.swipeButton()
            }
    }

    /// A tap opens its screen. On the filtered home it opens under its parents, as every other
    /// way to a folder does. Elsewhere the link sits behind the row, so the List draws no
    /// disclosure of its own. Selecting the cell (a tap) follows it; in Edit the List's selection
    /// takes the tap instead.
    @ViewBuilder
    private func opening(_ row: some View) -> some View {
        if isFiltered {
            row.opensOnTap { shell.libraryPath = library.path(to: folder) }
        } else {
            row.background {
                NavigationLink(value: LibraryRoute.folder(folder.id)) { EmptyView() }
                    .opacity(0)
                    .accessibilityHidden(true)
            }
        }
    }

    private func row(_ progress: FolderProgress, download: DownloadState, menu: AnyView?) -> some View {
        let plays = progress.hasPagesToPlay
        let kind = ListRow.Kind.folder(symbol: folder.rowSymbol, count: plays ? [] : contents,
                                       cover: folder.hasDetails ? folder.coverImage : nil)
        return ListRow(kind: kind, title: folder.name, subtitle: location ?? (plays ? place(progress) : folder.byline),
                       progress: plays ? rowProgress(progress) : .unplayed(minutes: nil),
                       playState: plays ? actions.playState(of: folder) : .idle,
                       isDropTarget: screen.dropTarget == folder.id,
                       insertionEdge: screen.insertion?.id == .folder(folder.id) ? screen.insertion?.edge : nil,
                       download: download, isFavorite: marksFavorite && folder.isFavorite,
                       folderHasDetails: folder.hasDetails, menu: menu,
                       menuAnchor: AnyView(Color.clear.turnOffDownloadQuestion($turningOff)))
    }

    /// What is in it, as its screen's header counts it: ["2 folders", "3 pages"]; ["Empty"].
    private var contents: [String] {
        let folders = (folder.children ?? []).filter(\.isLive).count
        let pages = folder.livePages.count
        var parts: [String] = []
        if folders > 0 { parts.append(String(localized: "\(folders) folder\(folders == 1 ? "" : "s")")) }
        if pages > 0 { parts.append(folder.itemCount(pages)) }
        return parts.isEmpty ? [String(localized: "Empty")] : parts
    }

    /// Once it has a place: the title of the page it is at. Before that (and once finished), its
    /// byline: a book's author, a series' site, the author given in its details.
    private func place(_ progress: FolderProgress) -> String? {
        guard progress.hasStarted, !progress.isFinished, let key = progress.currentKey else { return folder.byline }
        return folder.livePages.first { $0.listenKey == key }?.givenTitle ?? folder.byline
    }

    /// Finished when every page that plays is (pages added later play on from it).
    private func rowProgress(_ progress: FolderProgress) -> ListRow.Progress {
        if progress.isFinished { return .finished }
        if let fraction = progress.fraction { return .partWay(fraction: fraction, minutesLeft: progress.minutesLeft) }
        return .unplayed(minutes: progress.minutesLeft > 0 ? progress.minutesLeft : nil)
    }
}

/// A row whose page or folder a saved delete just took, for the one redraw before its list drops
/// it: drawn from nothing, since reading the model then traps (`isLive`).
private struct DeletedRow: View {
    var body: some View {
        Color.clear.accessibilityHidden(true)
    }
}

extension View {
    /// A row that acts on a tap (and VoiceOver's activate): opens, or plays. nil: no tap of its
    /// own, so a List in Edit selects the row instead.
    @ViewBuilder
    func opensOnTap(_ open: (() -> Void)?) -> some View {
        if let open {
            contentShape(Rectangle())
                .onTapGesture(perform: open)
                .accessibilityAction { open() }
        } else {
            self
        }
    }
}

extension Page {
    /// The page's icon as an image, when it has one.
    var artworkImage: Image? {
        artworkData.flatMap(UIImage.init(data:)).map(Image.init(uiImage:))
    }
}

extension Folder {
    /// Its pages in play order, from the relationship (sorted here as `LibraryStore.pages(in:)`
    /// sorts, so a home with a long series doesn't fetch on every redraw).
    var playOrder: [Page] {
        livePages.sorted(using: LibraryQueries.sortDescriptors(pageSort))
    }

    /// Its pages still in the store: a delete being saved (a book with its chapters) redraws a
    /// row once more while the relationship still holds pages whose data is gone, and reading
    /// one then traps (`isLive`).
    var livePages: [Page] {
        (pages ?? []).filter(\.isLive)
    }

    /// What its pages are called in a count: "chapters" in a book or series, "pages" in any
    /// other folder (its row, its header, Downloads).
    var itemNoun: String {
        kind.isBookOrSeries ? String(localized: "chapters") : String(localized: "pages")
    }

    /// "3 pages", "1 chapter": `count` of its pages, by `itemNoun`.
    func itemCount(_ count: Int) -> String {
        if kind.isBookOrSeries {
            return count == 1 ? String(localized: "1 chapter") : String(localized: "\(count) chapters")
        }
        return count == 1 ? String(localized: "1 page") : String(localized: "\(count) pages")
    }

    var coverImage: Image? {
        coverData.flatMap(UIImage.init(data:)).map(Image.init(uiImage:))
    }
}
