import Foundation

/// How far through a page or chapter is, as its row shows it: its length unplayed, the fraction
/// and time left part-way, finished, or skipped.
enum PageProgress {
    /// The row's progress. Only a part-way page reads its stored paragraphs, so long folders
    /// stay cheap to draw.
    static func of(_ page: Page) -> ListRow.Progress {
        if page.finishedAt != nil { return .finished }
        if page.skipsInPlayback { return .skipped }
        if isPartWay(page), let paragraphs = page.cachedListenParagraphs, !paragraphs.isEmpty {
            let document = ParagraphDocument(parts: paragraphs)
            let offset = utf16Offset(in: document, paragraph: page.positionParagraph, utf16Offset: page.positionUTF16)
            return .partWay(fraction: document.progress(atUTF16Offset: offset),
                            minutesLeft: ListeningTime.minutesLeft(in: document, fromUTF16Offset: offset))
        }
        return .unplayed(minutes: page.hasText ? page.estimatedMinutes : nil)
    }

    /// Started and not finished.
    static func isPartWay(_ page: Page) -> Bool {
        page.finishedAt == nil && (page.positionParagraph > 0 || page.positionUTF16 > 0)
    }

    /// The stored spot as an offset into the listen text: the offset when it lies in the stored
    /// paragraph, else that paragraph's start.
    private static func utf16Offset(in document: ParagraphDocument, paragraph: Int, utf16Offset: Int) -> Int {
        let p = min(max(0, paragraph), document.count - 1)
        let start = document.startUTF16Offset(forParagraph: p)
        return utf16Offset >= start ? utf16Offset : start
    }
}

/// A folder as its row and its screen show it (any folder whose pages play, a book or series too):
/// the page Continue resumes (or the one playing), its number among the pages that play, how far
/// through they are, and what's left. Built once by `LibraryActions.progress(of:pages:)`, so the
/// row and the header agree.
struct FolderProgress {
    /// The page Continue resumes, or the one playing.
    let currentKey: UUID?
    /// `currentKey`'s number among the pages that play ("3 of 7").
    let number: Int?
    /// How many pages play (link pages and skipped chapters don't; a series' link chapters do).
    let playingCount: Int
    /// 0…1 by length; nil before any page that plays is finished or part-way.
    let fraction: Double?
    /// The playable pages' length left (all of it before anything has played).
    let minutesLeft: Int
    /// A page with text plays: the folder's row gets its ▶ and its header its play buttons.
    let hasPagesToPlay: Bool
    /// Every page with text that plays is finished.
    let isFinished: Bool
    /// Something in it has played, or is finished or part-way: the row names its place and the
    /// header's button says *Continue*; before that, its byline and *Play*.
    let hasStarted: Bool
    /// One of its pages is what you hear.
    let isPlaying: Bool

    /// `pages` in play order (`LibraryStore.playOrder`); `playingKey`: the page playing, when one
    /// of this folder's is what you hear.
    @MainActor
    init(folder: Folder, pages: [Page], playingKey: UUID?, library: LibraryStore) {
        let snapshot = library.chapterSnapshot(of: folder, pages: pages)
        isPlaying = playingKey != nil
        if let playingKey {
            currentKey = playingKey
        } else {
            switch ChapterAdvance.start(snapshot, place: folder.currentPageKey) {
            case .ready(let key), .pending(let key): currentKey = key
            case .unavailable, .none: currentKey = nil
            }
        }
        let plays = zip(pages, snapshot).filter { !$0.1.skipsInPlayback }.map(\.0)
        playingCount = plays.count
        number = currentKey.flatMap { key in plays.firstIndex { $0.listenKey == key } }.map { $0 + 1 }

        let timed = plays.filter { !$0.isLink }
        hasPagesToPlay = !timed.isEmpty
        isFinished = hasPagesToPlay && timed.allSatisfy { $0.finishedAt != nil }
        let total = timed.reduce(0) { $0 + $1.estimatedMinutes }
        let left = timed.reduce(0) { sum, page in
            switch PageProgress.of(page) {
            case .finished: sum
            case .partWay(_, let minutes): sum + minutes
            default: sum + page.estimatedMinutes
            }
        }
        minutesLeft = left
        let started = timed.contains { $0.finishedAt != nil || PageProgress.isPartWay($0) }
        fraction = total > 0 && started ? 1 - Double(left) / Double(total) : nil
        hasStarted = folder.currentPageKey != nil || fraction != nil
    }

    /// The header's round button and the lighter place after it: "Continue" "3 of 7", "Playing"
    /// "3 of 7"; "Play" before anything in it has started.
    var buttonTitle: (title: String, detail: String?) {
        let place = number.map { "\($0) of \(playingCount)" }
        if isPlaying { return (String(localized: "Playing"), place) }
        if !hasStarted { return (String(localized: "Play"), nil) }
        return (String(localized: "Continue"), place)
    }

    /// The header's bar and ["38%", "6 h 10 min left"], once a page is finished or part-way.
    var header: (fraction: Double?, label: [String]) {
        guard let fraction else { return (nil, []) }
        return (fraction, ["\(Int((fraction * 100).rounded()))%", "\(ListeningTime.label(minutes: minutesLeft)) left"])
    }
}
