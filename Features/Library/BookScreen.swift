import SwiftData
import SwiftUI

/// A book or series: its details, the round Continue / playing button, *Play from Start*, and
/// the chapters in their source order (no Edit). Front matter shows dimmed and "skipped";
/// *Jump to current* scrolls to the chapter Continue resumes.
///
/// ```
/// ‹ Fiction
/// ╭──────╮  Pride and Prejudice
/// │cover │  Jane Austen   Book   61 chapters
/// ╰──────╯  Added 2 Oct
/// ━━━━━━━━━━░░░░░░░░  38%   6 h 10 min left
///  ( ▶ Continue  Ch 24 )         Play from Start
/// Chapters                                   Jump to current
///    Title page                      skipped
///  ✓ Chapter 1                         Finished
///  ◐ Chapter 24                        6 min left
/// ```
struct BookScreen: View {
    let folder: Folder

    @Environment(LibraryStore.self) private var library
    @Environment(\.speechController) private var speech
    @Environment(ShellState.self) private var shell
    @Query private var chapters: [Page]

    init(folder: Folder) {
        self.folder = folder
        _chapters = Query(LibraryQueries.pages(inFolder: folder.id, sort: .manual))
    }

    private var actions: LibraryActions { LibraryActions(library: library, speech: speech, shell: shell) }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    EmptyView()
                } header: {
                    header
                        .libraryHeader()
                        .padding(.horizontal, -Spacing.pageMargin)
                }
                Section {
                    ForEach(chapters, id: \.listenKey) { chapter in
                        LibraryChapterRow(page: chapter)
                            .id(chapter.listenKey)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Palette.chrome)
                } header: {
                    SectionHeader(title: String(localized: "Chapters"),
                                  actionTitle: currentKey == nil ? nil : String(localized: "Jump to current"),
                                  actionIdentifier: "bookJumpToCurrent") {
                        if let currentKey { withAnimation(Motion.standard) { proxy.scrollTo(currentKey, anchor: .center) } }
                    }
                    .libraryHeader()
                    .accessibilityIdentifier("bookChaptersHeader")
                }
            }
            .libraryListStyle()
        }
        .navigationTitle(folder.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("bookScreen")
    }

    // MARK: - Header

    private var header: some View {
        FolderHeader(style: .book(cover: folder.coverImage), title: folder.displayName, detail: detail,
                     source: source, progress: progress.fraction, progressLabel: progress.label) {
            HStack(spacing: Spacing.s) {
                let play = continueTitle
                PlayStateButton(state: actions.playState(of: folder),
                                look: .pill(title: play.title, detail: play.detail)) {
                    actions.playBook(folder)
                }
                .accessibilityIdentifier("bookContinue")
                PillButton(String(localized: "Play from Start"), style: .neutral) { actions.playBookFromStart(folder) }
                    .accessibilityIdentifier("bookPlayFromStart")
            }
        }
    }

    /// ["Jane Austen", "Book", "61 chapters"], ["serials.example.com", "Series", "108 chapters", "13 saved"].
    private var detail: [String] {
        let count = chapters.count
        var parts = [folder.byline ?? "", folder.kind == .series ? String(localized: "Series") : String(localized: "Book"),
                     "\(count) chapter\(count == 1 ? "" : "s")"]
        if folder.kind == .series { parts.append("\(chapters.filter(\.isSaved).count) saved") }
        return parts.filter { !$0.isEmpty }
    }

    /// Where it came from: the series' contents page, or when the book was added.
    private var source: [String] {
        if folder.kind == .series { return [folder.sourceURLString.flatMap(URL.init(string:))?.host].compactMap { $0 } }
        return ["Added \(folder.createdAt.formatted(.dateTime.day().month(.abbreviated)))"]
    }

    /// The place, how far through and what's left, from the chapters that play.
    private var bookProgress: BookProgress {
        let playing = actions.playState(of: folder).isCurrent ? speech.activeSessionID : nil
        return BookProgress(folder: folder, chapters: chapters, playingKey: playing, library: library)
    }

    /// The header's bar and ["38%", "6 h 10 min left"], once a chapter is finished or part-way.
    private var progress: (fraction: Double?, label: [String]) {
        let book = bookProgress
        guard let fraction = book.fraction else { return (nil, []) }
        return (fraction, ["\(Int((fraction * 100).rounded()))%",
                           "\(ListeningTime.label(minutes: book.minutesLeft)) left"])
    }

    // MARK: - Continue

    /// The chapter Continue resumes (or the one playing).
    private var currentKey: UUID? { bookProgress.currentKey }

    /// The round button's title and the lighter chapter after it: "Continue" "Ch 24", "Playing"
    /// "Ch 24"; "Play from Chapter 1" before anything has played.
    private var continueTitle: (title: String, detail: String?) {
        let number = bookProgress.chapterNumber
        let chapter = number.map { "Ch \($0)" }
        if actions.playState(of: folder).isCurrent { return (String(localized: "Playing"), chapter) }
        if folder.currentPageKey == nil {
            return (number.map { "Play from Chapter \($0)" } ?? String(localized: "Play"), nil)
        }
        return (String(localized: "Continue"), chapter)
    }
}
