import SwiftData
import SwiftUI

/// A book or series: its details, the round Continue / playing button, *Play from Start*, and
/// the chapters in their source order (no Edit). Front matter shows dimmed and "skipped";
/// *Jump to current* scrolls to the chapter Continue resumes.
///
/// ```
/// ‹ Fiction
/// ╭──────╮  Pride and Prejudice
/// │cover │  Jane Austen · Book · 61 chapters
/// ╰──────╯  imported 2 Oct
/// ━━━━━━━━━━░░░░░░░░  38% · 6 h 10 min left
///  ( ▶ Continue · Ch 24 )        Play from Start
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
                PlayStateButton(state: actions.playState(of: folder), look: .pill(title: continueTitle)) {
                    actions.playBook(folder)
                }
                .accessibilityIdentifier("bookContinue")
                PillButton(String(localized: "Play from Start"), style: .neutral) { actions.playBookFromStart(folder) }
                    .accessibilityIdentifier("bookPlayFromStart")
            }
        }
    }

    /// "Jane Austen · Book · 61 chapters", "serials.example.com · Series · 108 chapters · 13 saved".
    private var detail: String {
        let count = chapters.count
        var parts = [folder.byline ?? "", folder.kind == .series ? String(localized: "Series") : String(localized: "Book"),
                     "\(count) chapter\(count == 1 ? "" : "s")"]
        if folder.kind == .series { parts.append("\(chapters.filter(\.isSaved).count) saved") }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Where it came from: the series' contents page, or when the book was added.
    private var source: String? {
        if folder.kind == .series { return folder.sourceURLString.flatMap(URL.init(string:))?.host }
        return "Added \(folder.createdAt.formatted(.dateTime.day().month(.abbreviated)))"
    }

    /// The chapters that play, by length: how far through, and what's left.
    private var progress: (fraction: Double?, label: String?) {
        let playable = chapters.filter { !$0.skipsInPlayback && !$0.isLink }
        let total = playable.reduce(0) { $0 + $1.estimatedMinutes }
        guard total > 0, playable.contains(where: { $0.finishedAt != nil || PageProgress.isPartWay($0) }) else {
            return (nil, nil)
        }
        let left = playable.reduce(0) { sum, chapter in
            switch PageProgress.of(chapter) {
            case .finished: sum
            case .partWay(_, let minutes): sum + minutes
            default: sum + chapter.estimatedMinutes
            }
        }
        let fraction = 1 - Double(left) / Double(total)
        return (fraction, "\(Int((fraction * 100).rounded()))% · \(Self.duration(minutes: left)) left")
    }

    static func duration(minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
    }

    // MARK: - Continue

    /// The chapter Continue resumes (or the one playing).
    private var currentKey: UUID? {
        if actions.playState(of: folder).isCurrent, let playing = speech.activeSessionID { return playing }
        switch ChapterAdvance.start(library.chapterSnapshot(of: folder), place: folder.currentPageKey) {
        case .ready(let key), .pending(let key): return key
        case .unavailable, .none: return nil
        }
    }

    /// "Continue · Ch 24", "Play from Chapter 1" before anything has played, "Playing · Ch 24".
    private var continueTitle: String {
        let number = currentKey.flatMap { key in
            chapters.filter { !$0.skipsInPlayback }.firstIndex { $0.listenKey == key }
        }.map { $0 + 1 }
        if actions.playState(of: folder).isCurrent {
            return number.map { "Playing · Ch \($0)" } ?? String(localized: "Playing")
        }
        if folder.currentPageKey == nil {
            return number.map { "Play from Chapter \($0)" } ?? String(localized: "Play")
        }
        return number.map { "Continue · Ch \($0)" } ?? String(localized: "Continue")
    }
}
