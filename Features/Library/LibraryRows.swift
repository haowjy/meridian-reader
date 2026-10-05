import SwiftUI

/// A page row: a saved page (its ▶) or a link (lighter, 🔗, no ▶). Tap opens it (the Reader, Now
/// Playing when it is what you hear, the browser for a link); long-press is its menu (decision
/// D11); swipe left removes it from the Library. While its screen is in Edit the List's selection
/// takes the tap.
struct LibraryPageRow: View {
    let page: Page

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
                Button("Remove", role: .destructive) { library.remove(page) }
            }
    }

    /// The site, and a page not played yet gets nothing more (its length is on the right).
    private var subtitle: String? { page.byline.isEmpty ? nil : page.byline }

    @ViewBuilder
    private var menu: some View {
        Button("Move to…", systemImage: "folder") { actions.move([.page(page)]) }
        if page.isSaved {
            if page.finishedAt == nil {
                Button("Mark as Finished", systemImage: "checkmark.circle") { library.setFinished([page], true) }
            } else {
                Button("Mark as Unfinished", systemImage: "circle") { library.setFinished([page], false) }
            }
        }
        if page.url?.isWeb == true {
            Button("Share", systemImage: "square.and.arrow.up") { actions.share(page) }
        }
        if page.isSaved, library.hasDownloads(page) {
            Button("Delete Downloads", systemImage: "arrow.down.circle") { library.deleteDownloads(page) }
        }
        Button("Remove from Library", systemImage: "trash", role: .destructive) { library.remove(page) }
    }
}

/// A folder row (a plain folder, Favorites, a book or series): pushes its screen. Long-press is
/// its menu; swipe left asks to delete it (not Favorites).
struct LibraryFolderRow: View {
    let folder: Folder
    /// Swipe left and the menu offer to delete (off in the Move tree and on Favorites).
    var showsMenu = true

    @Environment(LibraryStore.self) private var library
    @Environment(\.speechController) private var speech
    @Environment(ShellState.self) private var shell
    @Environment(LibraryScreenState.self) private var screen

    private var actions: LibraryActions { LibraryActions(library: library, speech: speech, shell: shell) }

    var body: some View {
        NavigationLink(value: LibraryRoute.folder(folder.id)) {
            ListRow(kind: .folder(symbol: folder.rowSymbol, count: folder.itemCount, cover: folder.coverImage),
                    title: folder.displayName, subtitle: folder.kind.isFixed ? folder.byline : nil,
                    playState: folder.kind.isFixed ? actions.playState(of: folder) : .idle)
        }
        .accessibilityIdentifier("folderRow")
        .contextMenu { if showsMenu { menu } }
        .swipeActions(edge: .trailing) {
            if showsMenu, folder.kind != .favorites {
                Button("Delete", role: .destructive) { screen.confirmDelete([folder]) }
            }
        }
    }

    @ViewBuilder
    private var menu: some View {
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
                Button("Mark as Finished", systemImage: "checkmark.circle") { library.setFinished([page], true) }
            } else {
                Button("Mark as Unfinished", systemImage: "circle") { library.setFinished([page], false) }
            }
            Button("Mark All Above as Finished", systemImage: "checkmark.circle.badge.questionmark") {
                library.markAllAbove(page)
            }
        }
        Button(page.skipsInPlayback ? "Play in Playback" : "Skip in Playback",
               systemImage: page.skipsInPlayback ? "play.circle" : "forward.end") {
            library.setSkipsInPlayback(page, !page.skipsInPlayback)
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
