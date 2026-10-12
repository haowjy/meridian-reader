import SwiftUI

/// A page row: a saved page (its ▶), a link (lighter, 🔗, no ▶), or a page played without saving
/// ("Not saved", *Save* in its menu; decision D5). Tap opens it (the Reader, Now Playing when it is
/// what you hear, the browser for a link); long-press is its menu (decision D11); swipe left
/// removes it from the Library. A page in the Library lifts into a drag from the long press, to
/// be filed in a folder or placed between rows (`LibraryDrag`). While its screen is in Edit the
/// List's selection takes the tap.
struct LibraryPageRow: View {
    let page: Page
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
        guard drags, !isEditing, page.isInLibrary, !page.isInFixedFolder else { return nil }
        return .page(page.listenKey)
    }

    var body: some View {
        ListRow(kind: page.isLink ? .link : .page(artwork: page.artworkImage, letter: page.byline.siteLetter),
                title: page.title, subtitle: page.byline.isEmpty ? nil : page.byline,
                note: page.isLink || page.isInLibrary ? nil : String(localized: "Not saved"),
                progress: page.isLink ? .unplayed(minutes: nil) : PageProgress.of(page),
                playState: page.isLink ? .idle : actions.playState(of: page),
                onPlay: page.isLink || isEditing ? nil : { actions.play(page) },
                insertionEdge: screen.insertion?.id == .page(page.listenKey) ? screen.insertion?.edge : nil,
                isDownloaded: page.isInLibrary && downloads.isDownloaded(page))
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

    @ViewBuilder
    private var menu: some View {
        if let onSelect {
            Button("Select", systemImage: "checkmark.circle", action: onSelect)
        }
        if !page.isInLibrary {
            Button("Save", systemImage: "plus.circle") { actions.save(page) }
            if page.url?.isWeb == true {
                Button("Share", systemImage: "square.and.arrow.up") { actions.share(page) }
            }
        } else {
            Button("Move to…", systemImage: "folder") { actions.move([.page(page)]) }
            if page.isSaved {
                if page.finishedAt == nil {
                    Button("Mark as Finished", systemImage: "checkmark.circle") { actions.setFinished([page], true) }
                } else {
                    Button("Mark as Unfinished", systemImage: "circle") { actions.setFinished([page], false) }
                }
            }
            if page.url?.isWeb == true {
                Button("Share", systemImage: "square.and.arrow.up") { actions.share(page) }
            }
            if !downloads.isQueued(.page(page.listenKey)) {
                Button("Download", systemImage: "arrow.down.circle") {
                    DownloadActions(downloads: downloads, shell: shell).download(page)
                }
            }
            if page.isSaved, library.hasDownloads(page) {
                Button("Delete Downloads", systemImage: "trash.circle") { downloads.deleteDownloads(of: page) }
            }
            Button("Remove from Library", systemImage: "trash", role: .destructive) { actions.remove([page]) }
        }
    }
}

/// A folder row (a plain folder, Favorites, a book or series): pushes its screen. Its cover, when
/// it has one (a book's, or one given in *Edit Details*), stands in for the symbol. A folder whose
/// pages play (a book or series always) shows its place ("Ch 24", or the page it is at), the time
/// left and its own ▶, which resumes it there and carries on page to page; any other folder shows
/// its count and ›. Long-press is its menu, and lifts it into a drag (not Favorites); a dragged
/// row let go on it is filed in it, unless it is a book or series. Swipe left asks to delete it
/// (not Favorites).
struct LibraryFolderRow: View {
    let folder: Folder
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
            .libraryDrag(folder.kind == .favorites || isEditing ? nil : .folder(folder.id), in: screen)
            .contextMenu { menu(progress) }
            .swipeActions(edge: .trailing) {
                if folder.kind != .favorites {
                    Button("Delete", role: .destructive) { screen.confirmDelete([folder]) }
                }
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
    /// one then traps.
    private var livePages: [Page] {
        (folder.pages ?? []).filter { !$0.isDeleted && $0.modelContext != nil }
    }

    private func plays(_ progress: FolderProgress) -> Bool {
        folder.kind.isFixed || progress.hasPagesToPlay
    }

    @ViewBuilder
    private func row(_ progress: FolderProgress, isDownloaded: Bool) -> some View {
        let kind = ListRow.Kind.folder(symbol: folder.rowSymbol, count: folder.itemCount, cover: folder.coverImage)
        let isDropTarget = screen.dropTarget == folder.id
        let edge = screen.insertion?.id == .folder(folder.id) ? screen.insertion?.edge : nil
        if plays(progress) {
            ListRow(kind: kind, title: folder.displayName, subtitle: place(progress), progress: rowProgress(progress),
                    playState: actions.playState(of: folder), opensScreen: true,
                    onPlay: isEditing ? nil : { actions.playFolder(folder) }, isDropTarget: isDropTarget,
                    insertionEdge: edge, isDownloaded: isDownloaded)
        } else {
            ListRow(kind: kind, title: folder.displayName, subtitle: folder.byline, opensScreen: true,
                    isDropTarget: isDropTarget, insertionEdge: edge)
        }
    }

    /// Once it has a place: "Ch 24" in a book or series, the page's title in any other folder.
    /// Before that (and once finished), its byline: a book's author, a series' site, the author
    /// given in a folder's details.
    private func place(_ progress: FolderProgress) -> String? {
        let started = folder.currentPageKey != nil || progress.fraction != nil
        if folder.kind.isFixed {
            if started, folder.finishedAt == nil, let number = progress.number { return "Ch \(number)" }
            return folder.byline
        }
        guard started, !progress.isFinished, let key = progress.currentKey else { return folder.byline }
        return livePages.first { $0.listenKey == key }?.title ?? folder.byline
    }

    /// A book is finished when its last chapter is; any other folder when every page that plays
    /// is (pages added later play on from it).
    private func rowProgress(_ progress: FolderProgress) -> ListRow.Progress {
        if folder.kind.isFixed ? folder.finishedAt != nil : progress.isFinished { return .finished }
        if let fraction = progress.fraction { return .partWay(fraction: fraction, minutesLeft: progress.minutesLeft) }
        return .unplayed(minutes: progress.minutesLeft > 0 ? progress.minutesLeft : nil)
    }

    @ViewBuilder
    private func menu(_ progress: FolderProgress) -> some View {
        if let onSelect {
            Button("Select", systemImage: "checkmark.circle", action: onSelect)
        }
        if plays(progress) {
            Button("Continue", systemImage: "play.fill") { actions.playFolder(folder) }
            Button("Play from Start", systemImage: "backward.end") { actions.playFolderFromStart(folder) }
        }
        if !livePages.isEmpty, !downloads.isQueued(.folder(folder.id)) {
            Button("Download", systemImage: "arrow.down.circle") {
                DownloadActions(downloads: downloads, shell: shell).download(folder)
            }
        }
        if folder.kind != .favorites {
            Button("Move to…", systemImage: "folder") { actions.move([.folder(folder)]) }
            Button("Rename", systemImage: "pencil") { screen.rename(folder) }
            Button("Edit Details", systemImage: "square.and.pencil") { shell.present(.folderDetails(folder.id)) }
            Button(folder.kind.isFixed ? (folder.kind == .series ? "Delete Series…" : "Delete Book…") : "Delete…",
                   systemImage: "trash", role: .destructive) { screen.confirmDelete([folder]) }
        }
    }
}

/// A chapter row in a book or series: ▶ plays from it (and on through the book); front matter
/// shows dimmed and "skipped". A link chapter (a series chapter not fetched yet) is lighter.
struct LibraryChapterRow: View {
    let page: Page

    @Environment(LibraryStore.self) private var library
    @Environment(\.speechController) private var speech
    @Environment(ShellState.self) private var shell
    @Environment(DownloadCenter.self) private var downloads

    private var actions: LibraryActions { LibraryActions(library: library, speech: speech, shell: shell) }

    var body: some View {
        ListRow(kind: page.isLink ? .link : .chapter, title: page.title,
                subtitle: page.isLink ? String(localized: "not fetched yet") : nil,
                progress: page.isLink ? .unplayed(minutes: nil) : PageProgress.of(page),
                playState: actions.playState(of: page),
                onPlay: page.isLink || page.skipsInPlayback ? nil : { actions.play(page) },
                isDownloaded: downloads.isDownloaded(page))
            .opensOnTap { actions.open(page) }
            .accessibilityIdentifier("chapterRow")
            .contextMenu { menu }
    }

    @ViewBuilder
    private var menu: some View {
        if !page.isLink {
            Button("Play from Here", systemImage: "play.fill") { actions.playFromStart(page) }
            if page.finishedAt == nil {
                Button("Mark as Finished", systemImage: "checkmark.circle") { actions.setFinished([page], true) }
            } else {
                Button("Mark as Unfinished", systemImage: "circle") { actions.setFinished([page], false) }
            }
            Button("Mark All Above as Finished", systemImage: "checkmark.circle.badge.questionmark") {
                actions.markAllAbove(page)
            }
        }
        Button(page.skipsInPlayback ? "Play in Playback" : "Skip in Playback",
               systemImage: page.skipsInPlayback ? "play.circle" : "forward.end") {
            actions.toggleSkipsInPlayback(page)
        }
        if !downloads.isQueued(.page(page.listenKey)) {
            Button("Download", systemImage: "arrow.down.circle") {
                DownloadActions(downloads: downloads, shell: shell).download(page)
            }
        }
        if library.hasDownloads(page) {
            Button("Delete Downloads", systemImage: "trash.circle") { downloads.deleteDownloads(of: page) }
        }
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
