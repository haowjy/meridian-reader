import SwiftData
import SwiftUI

/// The top of the tree: Continue (books, series and part-way pages to resume), the top-level
/// folders (Favorites first), then *Pages*, the pages in no folder (first five, newest first;
/// *Show All* pushes the rest).
///
/// ```
/// Library                                   large title
/// Continue
///  ╭ cover ╮ ╭ [i] ╮ ╭ [i] ╮  →             horizontal cards, most recent first, max 8
/// Folders
///  ★ Favorites 12   📁 Fiction 3            books and series show their cover
/// Pages · 48                     Show All › pages in no folder, newest first, first 5
/// ```
struct LibraryHomeView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.speechController) private var speech
    @Environment(ShellState.self) private var shell

    @Query(LibraryQueries.continueFolders) private var continueFolders: [Folder]
    @Query(LibraryQueries.recentlyPlayed) private var recentlyPlayed: [Page]
    @Query(LibraryQueries.undatedInProgress) private var undatedInProgress: [Page]
    @Query private var folders: [Folder]
    @Query private var loosePages: [Page]

    /// How many of the pages in no folder the home shows before *Show All*.
    static let pagesShown = 5

    init(pageSort: PageSort) {
        _loosePages = Query(LibraryQueries.loosePages(sort: pageSort))
    }

    private var actions: LibraryActions { LibraryActions(library: library, speech: speech, shell: shell) }

    private var continueItems: [ContinueItem] {
        LibraryQueries.continueItems(folders: continueFolders, recent: recentlyPlayed, undated: undatedInProgress)
    }

    private var topLevelFolders: [Folder] {
        LibraryStore.ordered(folders.filter { $0.parent == nil })
    }

    /// Nothing to show but an empty Favorites.
    private var isEmpty: Bool {
        continueItems.isEmpty && loosePages.isEmpty && topLevelFolders.allSatisfy { $0.kind == .favorites && $0.itemCount == 0 }
    }

    var body: some View {
        List {
            if isEmpty {
                Section { emptyCard }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            let items = continueItems
            if !items.isEmpty {
                Section {
                    continueRow(items)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } header: {
                    SectionHeader(title: String(localized: "Continue")).libraryHeader()
                }
                .accessibilityIdentifier("libraryContinue")
            }
            Section {
                ForEach(topLevelFolders, id: \.id) { folder in
                    LibraryFolderRow(folder: folder)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Palette.chrome)
            } header: {
                SectionHeader(title: String(localized: "Folders")).libraryHeader()
            }
            if !loosePages.isEmpty {
                Section {
                    ForEach(loosePages.prefix(Self.pagesShown), id: \.listenKey) { page in
                        LibraryPageRow(page: page)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Palette.chrome)
                } header: {
                    SectionHeader(title: "Pages · \(loosePages.count)",
                                  actionTitle: loosePages.count > Self.pagesShown ? String(localized: "Show All") : nil,
                                  actionNavigates: true, actionIdentifier: "libraryPagesShowAll") {
                        shell.libraryPath.append(.pages)
                    }
                    .libraryHeader()
                    .accessibilityIdentifier("libraryPagesHeader")
                }
            }
        }
        .libraryListStyle()
        .navigationTitle("Library")
        .accessibilityIdentifier("libraryHome")
    }

    // MARK: - Continue

    private func continueRow(_ items: [ContinueItem]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Spacing.s) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    card(item)
                }
            }
            .padding(.vertical, Spacing.xxs)
        }
        .contentMargins(.horizontal, Spacing.pageMargin, for: .scrollContent)
        .scrollClipDisabled()
    }

    @ViewBuilder
    private func card(_ item: ContinueItem) -> some View {
        switch item {
        case .folder(let folder):
            let chapter = folder.currentPageKey.flatMap(library.page(key:))
            ContinueCard(title: chapter?.title ?? folder.displayName,
                         detail: chapterDetail(folder: folder, chapter: chapter),
                         artwork: folder.coverImage, artworkLetter: folder.displayName,
                         progress: chapter.map(PageProgress.fraction(of:)) ?? 0,
                         playState: actions.playState(of: folder)) {
                actions.playBook(folder)
            }
            .onTapGesture { shell.libraryPath.append(.folder(folder.id)) }
            .accessibilityAction { shell.libraryPath.append(.folder(folder.id)) }
            .accessibilityIdentifier("continueCard")
        case .page(let page):
            ContinueCard(title: page.title, detail: pageDetail(page), artwork: page.artworkImage,
                         artworkLetter: page.byline.siteLetter, progress: PageProgress.fraction(of: page),
                         playState: actions.playState(of: page),
                         badge: page.isInLibrary ? nil : String(localized: "Not saved")) {
                actions.play(page)
            }
            .onTapGesture { actions.open(page) }
            .accessibilityAction { actions.open(page) }
            .accessibilityIdentifier("continueCard")
        }
    }

    private func chapterDetail(folder: Folder, chapter: Page?) -> String {
        guard let chapter, case .partWay(_, let left) = PageProgress.of(chapter) else { return folder.displayName }
        return "\(folder.displayName) · \(left) min left"
    }

    private func pageDetail(_ page: Page) -> String {
        if case .partWay(_, let left) = PageProgress.of(page) { return "\(left) min left" }
        return page.byline
    }

    // MARK: - Empty

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Find something to listen to")
                .typeStyle(.heading)
                .foregroundStyle(Palette.ink)
            Text("Pages you save or listen to, books you import and folders you make show up here.")
                .typeStyle(.row)
                .foregroundStyle(Palette.secondaryInk)
            HStack(spacing: Spacing.s) {
                PillButton("Browse the web", style: .filled) { shell.leaveLibrary() }
                    .accessibilityIdentifier("libraryEmptyBrowse")
                PillButton("Import a book", style: .neutral) {
                    BookImportActions(library: library, shell: shell).pickBook(into: nil)
                }
                .accessibilityIdentifier("libraryEmptyImport")
            }
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.chrome, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("libraryEmpty")
    }
}

extension View {
    /// A section header in the Library's lists: in line with the cards (no extra header inset).
    func libraryHeader() -> some View {
        textCase(nil)
            .listRowInsets(EdgeInsets(top: Spacing.m, leading: 0, bottom: Spacing.xs, trailing: 0))
    }

    /// The Library's lists: grouped cards on paper, at the page margin.
    func libraryListStyle() -> some View {
        listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Palette.paper)
            .contentMargins(.horizontal, Spacing.pageMargin, for: .scrollContent)
            .environment(\.defaultMinListRowHeight, 0)
    }
}
