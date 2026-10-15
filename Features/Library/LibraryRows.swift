import SwiftUI

/// A page row: a saved page (its ▶), a link (lighter, 🔗, no ▶), or a page played without saving
/// ("Not saved", *Save* in its menu; decision D5). Every page uses this same row, including
/// imported chapters: two lines, the title and then its status (decision D21). In a folder the
/// second line is the status alone ("5 min", "skipped", "Playing"): the folder's header already
/// names the author or site, so rows don't repeat it. Front matter is dimmed and "skipped" (any
/// page skipped in playback is), with no ▶. Saved pages have Download beside ▶. Tap
/// opens it (the Reader, Now Playing when it is what you hear, the browser for a link);
/// long-press is its menu (decision D11); swipe left removes it from the Library. A page in the
/// Library lifts into a drag from the long press, to be filed in a folder or placed between rows
/// (`LibraryDrag`), a chapter as any page (decision D19). While its screen is in Edit the List's
/// selection takes the tap.
struct LibraryPageRow: View {
    let page: Page
    var subtitleOverride: String?
    /// *Select* in the menu: enters Edit with this row selected (folder screens only).
    var onSelect: (() -> Void)?
    /// Lifts into a drag (not in search results, which have nowhere to drop it).
    var drags = true

    @Environment(LibraryStore.self) private var library
    @Environment(\.speechController) private var speech
    @Environment(ShellState.self) private var shell
    @Environment(DownloadCenter.self) private var downloads
    @Environment(LibraryScreenState.self) private var screen
    @Environment(\.editMode) private var editMode

    private var actions: LibraryActions { LibraryActions(library: library, speech: speech, shell: shell) }
    private var isEditing: Bool { editMode?.wrappedValue.isEditing == true }
    private var dragID: LibraryItemID? {
        guard drags, !isEditing, page.isInLibrary else { return nil }
        return .page(page.listenKey)
    }

    var body: some View {
        if page.isLive { liveBody } else { DeletedRow() }
    }

    private var liveBody: some View {
        ListRow(kind: kind, title: page.title, subtitle: subtitle,
                note: page.isLink || page.isInLibrary ? nil : String(localized: "Not saved"),
                progress: page.isLink ? .unplayed(minutes: nil) : PageProgress.of(page),
                playState: page.isLink ? .idle : actions.playState(of: page),
                onPlay: page.isLink || page.skipsInPlayback || isEditing ? nil : { actions.play(page) },
                insertionEdge: screen.insertion?.id == .page(page.listenKey) ? screen.insertion?.edge : nil,
                download: download, isFavorite: page.isFavorite)
            .opensOnTap(isEditing ? nil : { actions.open(page) })
            .libraryDropRow(.page(page.listenKey), in: screen)
            .libraryDrag(dragID, in: screen)
            .contextMenu { menu }
            .swipeActions(edge: .trailing) {
                if page.isInLibrary {
                    Button("Remove", role: .destructive) { actions.remove([page]) }
                }
            }
    }

    private var kind: ListRow.Kind {
        if page.isLink { return .link }
        return .page(artwork: page.artworkImage, letter: page.byline.siteLetter)
    }

    /// Where it is (`subtitleOverride`: a path in Favorites or search), else its site; none in a
    /// folder, whose header names it.
    private var subtitle: String? {
        if let subtitleOverride { return subtitleOverride }
        return page.folder != nil || page.byline.isEmpty ? nil : page.byline
    }

    /// A saved page's Download, beside its ▶ (none out of the Library, or in Edit).
    private var download: ListRow.Download? {
        guard page.isInLibrary, !isEditing else { return nil }
        let target = DownloadRecord.Target.page(page.listenKey)
        return ListRow.Download(state: downloads.state(of: target, isDownloaded: downloads.isDownloaded(page))) {
            DownloadActions(downloads: downloads, shell: shell).download(page)
        }
    }

    @ViewBuilder
    private var menu: some View {
        if let onSelect {
            Button("Select", systemImage: Icons.select, action: onSelect)
        }
        if !page.isInLibrary {
            Button("Save", systemImage: Icons.save) { actions.save(page) }
            if page.url?.isWeb == true {
                Button("Share", systemImage: Icons.share) { actions.share(page) }
            }
        } else {
            let inFolder = page.folder != nil
            if inFolder, page.isSaved {
                Button("Play from Here", systemImage: Icons.play) { actions.playFromStart(page) }
            }
            Button("Move to…", systemImage: Icons.move) { actions.move([.page(page)]) }
            if page.isSaved {
                if page.finishedAt == nil {
                    Button("Mark as Finished", systemImage: Icons.markFinished) { actions.setFinished([page], true) }
                } else {
                    Button("Mark as Unfinished", systemImage: Icons.markUnfinished) { actions.setFinished([page], false) }
                }
                if inFolder {
                    Button("Mark All Above as Finished", systemImage: Icons.markAllAboveFinished) {
                        actions.markAllAbove(page)
                    }
                    Button(page.skipsInPlayback ? "Play in Playback" : "Skip in Playback",
                           systemImage: page.skipsInPlayback ? Icons.includeInPlayback : Icons.skipInPlayback) {
                        actions.toggleSkipsInPlayback(page)
                    }
                }
            }
            if page.url?.isWeb == true {
                Button("Share", systemImage: Icons.share) { actions.share(page) }
            }
            if !downloads.isQueued(.page(page.listenKey)) {
                Button("Download", systemImage: Icons.download) {
                    DownloadActions(downloads: downloads, shell: shell).download(page)
                }
            }
            if page.isSaved, library.hasDownloads(page) {
                Button("Delete Downloads", systemImage: Icons.deleteDownloads) { downloads.deleteDownloads(of: page) }
            }
            Button("Remove from Library", systemImage: Icons.unsave, role: .destructive) { actions.remove([page]) }
        }
        if let url = page.url, LibraryStore.canFavorite(url) {
            Button(page.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                   systemImage: page.isFavorite ? Icons.unfavorite : Icons.favorite) {
                shell.attempt(page.isFavorite ? "Couldn’t remove favorite" : "Couldn’t add favorite") {
                    if page.isFavorite { try library.removeFavorite(page) }
                    else { _ = try library.addFavorite(url: url, title: page.title, artwork: page.artworkData) }
                }
            }
        }
    }
}

/// A folder row (a folder you made, a book or series, all alike: decision D19): pushes
/// its screen. Its cover, when it has one (a book's, or one given in *Edit Details*), stands in
/// for the symbol. A folder whose pages play shows its place (the page it is at), the time left
/// and its own ▶, which resumes it there and carries on page to page; any other folder shows its
/// count and ›. Long-press is its menu, and lifts it into a drag (not Favorites); a dragged row
/// let go on it is filed in it. Swipe left asks to delete it (not Favorites).
struct LibraryFolderRow: View {
    let folder: Folder
    var subtitleOverride: String?
    /// *Select* in the menu: enters Edit with this row selected (folder screens only).
    var onSelect: (() -> Void)?

    @Environment(LibraryStore.self) private var library
    @Environment(\.speechController) private var speech
    @Environment(ShellState.self) private var shell
    @Environment(DownloadCenter.self) private var downloads
    @Environment(LibraryScreenState.self) private var screen
    @Environment(\.editMode) private var editMode

    private var actions: LibraryActions { LibraryActions(library: library, speech: speech, shell: shell) }
    private var isEditing: Bool { editMode?.wrappedValue.isEditing == true }

    var body: some View {
        if folder.isLive { liveBody } else { DeletedRow() }
    }

    @ViewBuilder private var liveBody: some View {
        let pages = playOrder
        let progress = folderProgress(pages)
        row(progress, isDownloaded: downloads.isDownloaded(folder, pages: pages))
            // The link sits behind the row, so the List draws no disclosure of its own: the
            // row's › shares the ▶ column. Selecting the cell (a tap) follows it; in Edit the
            // List's selection takes the tap instead.
            .background {
                NavigationLink(value: LibraryRoute.folder(folder.id)) { EmptyView() }
                    .opacity(0)
                    .accessibilityHidden(true)
            }
            .accessibilityIdentifier("folderRow")
            .libraryDropRow(.folder(folder.id), in: screen)
            .libraryDrag(isEditing ? nil : .folder(folder.id), in: screen)
            .contextMenu { menu(progress) }
            .swipeActions(edge: .trailing) {
                Button("Delete") { screen.confirmDelete([folder]) }
                    .tint(Palette.destructive)
            }
    }

    /// Where it is in `pages`, its pages in play order.
    private func folderProgress(_ pages: [Page]) -> FolderProgress {
        let state = actions.playState(of: folder)
        return FolderProgress(folder: folder, pages: pages, playingKey: state.isCurrent ? speech.activeSessionID : nil,
                              library: library)
    }

    /// Its pages in play order, from the relationship (sorted here as `LibraryStore.playOrder`
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

    private func plays(_ progress: FolderProgress) -> Bool {
        progress.hasPagesToPlay
    }

    @ViewBuilder
    private func row(_ progress: FolderProgress, isDownloaded: Bool) -> some View {
        let kind = ListRow.Kind.folder(symbol: folder.rowSymbol, count: folder.itemCount,
                                       cover: folder.hasDetails ? folder.coverImage : nil)
        let isDropTarget = screen.dropTarget == folder.id
        let edge = screen.insertion?.id == .folder(folder.id) ? screen.insertion?.edge : nil
        if plays(progress) {
            ListRow(kind: kind, title: folder.displayName, subtitle: subtitleOverride ?? place(progress), progress: rowProgress(progress),
                    playState: actions.playState(of: folder), opensScreen: true,
                    onPlay: isEditing ? nil : { actions.playFolder(folder) }, isDropTarget: isDropTarget,
                    insertionEdge: edge, download: download(isDownloaded: isDownloaded), isFavorite: folder.isFavorite,
                    largeArtwork: true, folderHasDetails: folder.hasDetails)
        } else {
            ListRow(kind: kind, title: folder.displayName, subtitle: subtitleOverride ?? folder.byline, opensScreen: true,
                    isDropTarget: isDropTarget, insertionEdge: edge, isFavorite: folder.isFavorite,
                    largeArtwork: true, folderHasDetails: folder.hasDetails)
        }
    }

    /// Its Download, beside its ▶ (none in Edit).
    private func download(isDownloaded: Bool) -> ListRow.Download? {
        guard !isEditing, !livePages.isEmpty else { return nil }
        return ListRow.Download(state: downloads.state(of: .folder(folder.id), isDownloaded: isDownloaded)) {
            DownloadActions(downloads: downloads, shell: shell).download(folder)
        }
    }

    /// Once it has a place: the title of the page it is at. Before that (and once finished), its
    /// byline: a book's author, a series' site, the author given in its details.
    private func place(_ progress: FolderProgress) -> String? {
        let started = folder.currentPageKey != nil || progress.fraction != nil
        guard started, !progress.isFinished, let key = progress.currentKey else { return folder.byline }
        return livePages.first { $0.listenKey == key }?.title ?? folder.byline
    }

    /// Finished when every page that plays is (pages added later play on from it).
    private func rowProgress(_ progress: FolderProgress) -> ListRow.Progress {
        if progress.isFinished { return .finished }
        if let fraction = progress.fraction { return .partWay(fraction: fraction, minutesLeft: progress.minutesLeft) }
        return .unplayed(minutes: progress.minutesLeft > 0 ? progress.minutesLeft : nil)
    }

    @ViewBuilder
    private func menu(_ progress: FolderProgress) -> some View {
        if let onSelect {
            Button("Select", systemImage: Icons.select, action: onSelect)
        }
        if plays(progress) {
            Button("Continue", systemImage: Icons.play) { actions.playFolder(folder) }
            Button("Play from Start", systemImage: Icons.previous) { actions.playFolderFromStart(folder) }
        }
        if !livePages.isEmpty, !downloads.isQueued(.folder(folder.id)) {
            Button("Download", systemImage: Icons.download) {
                DownloadActions(downloads: downloads, shell: shell).download(folder)
            }
        }
        Button(folder.isFavorite ? "Remove from Favorites" : "Add to Favorites",
               systemImage: folder.isFavorite ? Icons.unfavorite : Icons.favorite) {
            shell.attempt(folder.isFavorite ? "Couldn’t remove favorite" : "Couldn’t add favorite") {
                try library.toggleFavorite(folder)
            }
        }
        Button("Move to…", systemImage: Icons.move) { actions.move([.folder(folder)]) }
        Button("Rename", systemImage: Icons.rename) { screen.rename(folder) }
        Button("Edit Details", systemImage: Icons.editDetails) { shell.present(.folderDetails(folder.id)) }
        Button("Delete…", systemImage: Icons.delete, role: .destructive) { screen.confirmDelete([folder]) }
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
    /// A row that opens on a tap (and VoiceOver's activate). nil: no tap of its own, so a List in
    /// Edit selects the row instead.
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
