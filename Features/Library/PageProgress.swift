import Foundation

/// How far through a page or chapter is, as its row shows it: its length unplayed, the fraction
/// and time left part-way, finished, or skipped. Minutes count at `rate`, the playback speed
/// (`LibraryActions` passes the current one).
enum PageProgress {
    /// The row's progress. Only a part-way page reads its stored paragraphs, so long folders
    /// stay cheap to draw.
    static func of(_ page: Page, rate: Double) -> ListRow.Progress {
        if page.finishedAt != nil { return .finished }
        if page.skipsInPlayback { return .skipped }
        if let spot = spot(of: page) {
            return .partWay(fraction: spot.fraction, minutesLeft: ListeningTime.minutes(words: spot.wordsLeft, rate: rate))
        }
        return .unplayed(minutes: page.hasText ? ListeningTime.minutes(words: page.wordCount, rate: rate) : nil)
    }

    /// Started and not finished.
    static func isPartWay(_ page: Page) -> Bool {
        page.finishedAt == nil && (page.positionParagraph > 0 || page.positionUTF16 > 0)
    }

    /// A part-way page's place, measured on its stored listen text: how far through, the words
    /// left, and the words in the whole text on the same measure (`ListeningTime.words`), so what
    /// is left never exceeds the whole. Words, not minutes: they don't depend on the speed, and a
    /// folder rounds their sum once. Nil unless part-way with stored paragraphs.
    static func spot(of page: Page) -> (fraction: Double, wordsLeft: Double, words: Double)? {
        guard isPartWay(page), let paragraphs = page.cachedListenParagraphs, !paragraphs.isEmpty else { return nil }
        let document = ParagraphDocument(parts: paragraphs)
        let offset = utf16Offset(in: document, paragraph: page.positionParagraph, utf16Offset: page.positionUTF16)
        return (document.progress(atUTF16Offset: offset),
                ListeningTime.words(utf16Length: max(0, document.utf16Length - offset)),
                ListeningTime.words(utf16Length: document.utf16Length))
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
    /// How many pages play (link pages and skipped chapters don't; a followed story's chapters
    /// waiting for their text do).
    let playingCount: Int
    /// 0…1 by length; nil before any page that plays is finished or part-way.
    let fraction: Double?
    /// The playable pages' length left (all of it before anything has played).
    let minutesLeft: Int
    /// A page plays (one with text, or a chapter waiting for it): the folder's row gets its ▶ and
    /// its header its play buttons.
    let hasPagesToPlay: Bool
    /// Every page that plays is finished (a chapter waiting for its text isn't).
    let isFinished: Bool
    /// Something in it has played, or is finished or part-way: the row names its place and the
    /// header's button says *Continue*; before that, its byline and *Play*.
    let hasStarted: Bool
    /// One of its pages is what you hear.
    let isPlaying: Bool

    /// `pages` in play order (`LibraryStore.pages(in:)`); `playingKey`: the page playing, when one
    /// of this folder's is what you hear; `rate`: the playback speed the minutes count at.
    @MainActor
    init(folder: Folder, pages: [Page], playingKey: UUID?, rate: Double, library: LibraryStore) {
        let snapshot = library.chapterSnapshot(of: folder, pages: pages)
        isPlaying = playingKey != nil
        if let playingKey {
            currentKey = playingKey
        } else {
            currentKey = ChapterAdvance.start(snapshot, place: folder.currentPageKey).key
        }
        let plays = zip(pages, snapshot).filter { !$0.1.skipsInPlayback }.map(\.0)
        playingCount = plays.count
        number = currentKey.flatMap { key in plays.firstIndex { $0.listenKey == key } }.map { $0 + 1 }

        let timed = plays.filter { !$0.isLink }
        hasPagesToPlay = !plays.isEmpty
        isFinished = hasPagesToPlay && plays.allSatisfy { !$0.isLink && $0.finishedAt != nil }
        // Each page's whole and what is left in words, on one measure: a part-way page's both come
        // from its listen text, the rest from its word count. Summed before rounding, so the
        // fraction doesn't move with the speed and the time left is rounded once.
        var total = 0.0, left = 0.0
        for page in timed {
            let words = Double(page.wordCount)
            if page.finishedAt != nil {
                total += words
            } else if let spot = PageProgress.spot(of: page) {
                total += spot.words
                left += spot.wordsLeft
            } else {
                total += words
                left += words
            }
        }
        minutesLeft = ListeningTime.minutes(words: left, rate: rate)
        let started = timed.contains { $0.finishedAt != nil || PageProgress.isPartWay($0) }
        fraction = total > 0 && started ? 1 - left / total : nil
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
        return (fraction, ["\(Int((fraction * 100).rounded()))%", ListeningTime.leftLabel(minutes: minutesLeft)])
    }
}
