import SwiftUI

/// A page row: a saved page (its ▶), a link (lighter, 🔗, no ▶), or a page played without saving
/// ("Not saved", *Save* in its menu; decision D5). Tap opens it (the Reader, Now Playing when it is
/// what you hear, the browser for a link); long-press is its menu (decision D11); swipe left
/// removes it from the Library. While its screen is in Edit the List's selection takes the tap.
struct LibraryPageRow: View {
    let page: Page
    /// *Select* in the menu: enters Edit with this row selected (folder screens only).
    var onSelect: (() -> Void)?

    @Environment(LibraryStore.self) private var library
    @Environment(\.speechController) private var speech
    @Environment(ShellState.self) private var shell
    @Environment(\.editMode) private var editMode

    private var actions: LibraryActions { LibraryActions(library: library, speech: speech, shell: shell) }
    private var isEditing: Bool { editMode?.wrappedValue.isEditing == true }

    var body: some View {
        ListRow(kind: page.isLink ? .link : .page(artwork: page.artworkImage, letter: page.byline.siteLetter),
                title: page.title, subtitle: page.isLink ? page.byline : subtitle,
                progress: page.isLink ? .unplayed(minutes: nil) : PageProgress.of(page),
                playState: page.isLink ? .idle : actions.playState(of: page),
                onPlay: page.isLink || isEditing ? nil : { actions.play(page) })
            .opensOnTap(isEditing ? nil : { actions.open(page) })
            .contextMenu { menu }
            .swipeActions(edge: .trailing) {
                if page.isInLibrary {
                    Button("Remove", role: .destructive) { actions.remove([page]) }
                }
            }
    }

    /// The site, and "Not saved" for a page played without saving.
    private var subtitle: String? {
        let parts = [page.byline, page.isInLibrary ? "" : String(localized: "Not saved")].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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
            if page.isSaved, library.hasDownloads(page) {
                Button("Delete Downloads", systemImage: "arrow.down.circle") { library.deleteDownloads(page) }
            }
            Button("Remove from Library", systemImage: "trash", role: .destructive) { actions.remove([page]) }
        }
    }
}

/// A folder row (a plain folder, Favorites, a book or series): pushes its screen. A book or
/// series also shows its place ("Ch 24 · 6 h 10 min left") and its own ▶, which resumes it
/// there; other folders show their count and ›. Long-press is its menu; swipe left asks to delete
/// it (not Favorites).
struct LibraryFolderRow: View {
    let folder: Folder
    /// *Select* in the menu: enters Edit with this row selected (folder screens only).
    var onSelect: (() -> Void)?

    @Environment(LibraryStore.self) private var library
    @Environment(\.speechController) private var speech
    @Environment(ShellState.self) private var shell
    @Environment(LibraryScreenState.self) private var screen
    @Environment(\.editMode) private var editMode

    private var actions: LibraryActions { LibraryActions(library: library, speech: speech, shell: shell) }
    private var isEditing: Bool { editMode?.wrappedValue.isEditing == true }

    var body: some View {
        row
            // The link sits behind the row, so the List draws no disclosure of its own: the
            // row's › shares the ▶ column. Selecting the cell (a tap) follows it; in Edit the
            // List's selection takes the tap instead.
            .background {
                NavigationLink(value: LibraryRoute.folder(folder.id)) { EmptyView() }
                    .opacity(0)
                    .accessibilityHidden(true)
            }
            .accessibilityIdentifier("folderRow")
            .contextMenu { menu }
            .swipeActions(edge: .trailing) {
                if folder.kind != .favorites {
                    Button("Delete", role: .destructive) { screen.confirmDelete([folder]) }
                }
            }
    }

    @ViewBuilder
    private var row: some View {
        let kind = ListRow.Kind.folder(symbol: folder.rowSymbol, count: folder.itemCount, cover: folder.coverImage)
        if folder.kind.isFixed {
            let state = actions.playState(of: folder)
            // From the relationship, sorted here as `playOrder` sorts, so a home with a long
            // series doesn't fetch on every redraw.
            let chapters = (folder.pages ?? []).sorted(using: LibraryQueries.sortDescriptors(.manual))
            let book = BookProgress(folder: folder, chapters: chapters,
                                    playingKey: state.isCurrent ? speech.activeSessionID : nil, library: library)
            ListRow(kind: kind, title: folder.displayName, subtitle: place(book), progress: progress(book),
                    playState: state, opensScreen: true,
                    onPlay: isEditing ? nil : { actions.playBook(folder) })
        } else {
            ListRow(kind: kind, title: folder.displayName, opensScreen: true)
        }
    }

    /// "Ch 24" once it has a place; before that, the author or site.
    private func place(_ book: BookProgress) -> String? {
        if folder.currentPageKey != nil || book.fraction != nil, folder.finishedAt == nil,
           let number = book.chapterNumber {
            return "Ch \(number)"
        }
        return folder.byline
    }

    private func progress(_ book: BookProgress) -> ListRow.Progress {
        if folder.finishedAt != nil { return .finished }
        if let fraction = book.fraction { return .partWay(fraction: fraction, minutesLeft: book.minutesLeft) }
        return .unplayed(minutes: book.minutesLeft > 0 ? book.minutesLeft : nil)
    }

    @ViewBuilder
    private var menu: some View {
        if let onSelect {
            Button("Select", systemImage: "checkmark.circle", action: onSelect)
        }
        if folder.kind.isFixed {
            Button("Continue", systemImage: "play.fill") { actions.playBook(folder) }
            Button("Play from Start", systemImage: "backward.end") { actions.playBookFromStart(folder) }
        }
        if folder.kind != .favorites {
            Button("Move to…", systemImage: "folder") { actions.move([.folder(folder)]) }
            Button("Rename", systemImage: "pencil") { screen.rename(folder) }
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

    private var actions: LibraryActions { LibraryActions(library: library, speech: speech, shell: shell) }

    var body: some View {
        ListRow(kind: page.isLink ? .link : .chapter, title: page.title,
                subtitle: page.isLink ? String(localized: "not fetched yet") : nil,
                progress: page.isLink ? .unplayed(minutes: nil) : PageProgress.of(page),
                playState: actions.playState(of: page),
                onPlay: page.isLink || page.skipsInPlayback ? nil : { actions.play(page) })
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
        if library.hasDownloads(page) {
            Button("Delete Downloads", systemImage: "arrow.down.circle") { library.deleteDownloads(page) }
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
