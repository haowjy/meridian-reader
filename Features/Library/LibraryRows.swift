import SwiftUI

/// A page row: a saved page, a link (lighter, 🔗), a followed story's chapter waiting for its
/// text (a link with its status: "Fetching text…", "Retrying in 1:52", "Waiting"), or a page
/// played without saving. Every page uses this same row, including imported chapters: two lines,
/// the title and then its status (decision D21). In a folder the second line is the status alone
/// ("5 min", "Skipped", "Playing"): the folder's header already names the author or site, so
/// rows don't repeat it. Front matter is dimmed and "Skipped" (any page skipped in playback is).
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
        guard screenKey != .filtered, !isEditing, page.isInLibrary else { return nil }
        return .page(page.listenKey)
    }
    /// ★ after a favorite's title, except in the Favorites list, where every row is one.
    private var marksFavorite: Bool { !(screenKey == .filtered && shell.homeTab == .favorites) }

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
        PageMenu(page: page, actions: actions, downloads: downloads, onSelect: onSelect)
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
                // In the Library: *Remove* from it; in History: from History. The same remove.
                if page.isInLibrary || LibraryQueries.isInHistory(page) {
                    // The row leaves every list once the remove is stored; a save that fails keeps
                    // it, with a toast. So not `.destructive`, which takes the row out first
                    // (`Palette.destructive`).
                    Button("Remove") { actions.remove([page]) }
                        .tint(Palette.destructive)
                }
            }
    }

    private var kind: ListRow.Kind {
        if page.isLink { return .link }
        return .page(artwork: page.artworkImage, letter: page.byline.siteLetter)
    }

    /// Its folder's path on the filtered home, which gathers rows from every folder; elsewhere
    /// its site, and nothing in a folder, whose header names it. Untitled, its title line is
    /// already its site.
    private var subtitle: String? {
        if let folder = page.folder { return screenKey == .filtered ? folder.pathName : nil }
        return page.byline.isEmpty || page.givenTitle == nil ? nil : page.byline
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

    private var actions: LibraryActions { LibraryActions(library: library, speech: speech, shell: shell, follow: follow) }
    private var isEditing: Bool { editMode?.wrappedValue.isEditing == true }
    private var isFiltered: Bool { screenKey == .filtered }
    /// Its parents' path on the filtered home (nil for a folder at the top level).
    private var location: String? { isFiltered ? folder.parent?.pathName : nil }
    /// ★ after a favorite's title, except in the Favorites list, where every row is one.
    private var marksFavorite: Bool { !(isFiltered && shell.homeTab == .favorites) }

    var body: some View {
        if folder.isLive { liveBody } else { DeletedRow() }
    }

    @ViewBuilder private var liveBody: some View {
        let pages = playOrder
        let progress = actions.progress(of: folder, pages: pages)
        let menu = FolderMenu(folder: folder, progress: progress, hasPages: !pages.isEmpty, actions: actions,
                              downloads: downloads, screen: screen, onSelect: onSelect)
        opening(row(progress, download: downloads.state(of: folder, pages: pages), menu: isEditing ? nil : AnyView(menu)))
            .accessibilityIdentifier("folderRow")
            .libraryDropRow(.folder(folder.id), in: screen)
            .libraryDrag(isEditing || isFiltered ? nil : .folder(folder.id), in: screen)
            .contextMenu { menu }
            .swipeActions(edge: .trailing) {
                Button("Delete") { screen.confirmDelete([folder]) }
                    .tint(Palette.destructive)
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

    /// Its pages in play order, from the relationship (sorted here as `LibraryStore.pages(in:)`
    /// sorts, so a home with a long series doesn't fetch on every redraw).
    private var playOrder: [Page] {
        livePages.sorted(using: LibraryQueries.sortDescriptors(folder.pageSort))
    }

    /// Its pages still in the store: a delete being saved (a book with its chapters) redraws the
    /// row once more while the relationship still holds pages whose data is gone, and reading
    /// one then traps (`isLive`).
    private var livePages: [Page] {
        (folder.pages ?? []).filter(\.isLive)
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
                       folderHasDetails: folder.hasDetails, menu: menu)
    }

    /// What is in it, as its screen's header counts it: ["2 folders", "3 pages"]; ["Empty"].
    private var contents: [String] {
        let folders = (folder.children ?? []).filter(\.isLive).count
        let pages = livePages.count
        var parts: [String] = []
        if folders > 0 { parts.append(String(localized: "\(folders) folder\(folders == 1 ? "" : "s")")) }
        if pages > 0 { parts.append(String(localized: "\(pages) page\(pages == 1 ? "" : "s")")) }
        return parts.isEmpty ? [String(localized: "Empty")] : parts
    }

    /// Once it has a place: the title of the page it is at. Before that (and once finished), its
    /// byline: a book's author, a series' site, the author given in its details.
    private func place(_ progress: FolderProgress) -> String? {
        guard progress.hasStarted, !progress.isFinished, let key = progress.currentKey else { return folder.byline }
        return livePages.first { $0.listenKey == key }?.givenTitle ?? folder.byline
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
    /// "Finance › Bonds": the folders from the top level down to this one.
    var pathName: String {
        (ancestors.reversed() + [self]).map(\.name).joined(separator: " › ")
    }

    var coverImage: Image? {
        coverData.flatMap(UIImage.init(data:)).map(Image.init(uiImage:))
    }
}

extension String {
    /// The letter a site's tile shows without an icon: "investopedia.com" → "I".
    var siteLetter: String {
        let host = hasPrefix("www.") ? String(dropFirst(4)) : self
        return host.first(where: { $0.isLetter || $0.isNumber }).map { String($0).uppercased() } ?? "?"
    }
}
