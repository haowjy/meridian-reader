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

/// A book or series as its row and its screen show it: the chapter Continue resumes (or the one
/// playing), its number, how far through the playable chapters are, and what's left.
struct BookProgress {
    /// The chapter Continue resumes, or the one playing.
    let currentKey: UUID?
    /// `currentKey`'s number among the chapters that play ("Ch 24").
    let chapterNumber: Int?
    /// 0…1 by length; nil before any chapter is finished or part-way.
    let fraction: Double?
    /// The playable chapters' length left (all of it before anything has played).
    let minutesLeft: Int

    /// `chapters` in play order (`LibraryStore.playOrder`); `playingKey`: the chapter playing,
    /// when one of this book's is what you hear.
    @MainActor
    init(folder: Folder, chapters: [Page], playingKey: UUID?, library: LibraryStore) {
        if let playingKey {
            currentKey = playingKey
        } else {
            switch ChapterAdvance.start(library.chapterSnapshot(of: folder, pages: chapters), place: folder.currentPageKey) {
            case .ready(let key), .pending(let key): currentKey = key
            case .unavailable, .none: currentKey = nil
            }
        }
        chapterNumber = currentKey.flatMap { key in
            chapters.filter { !$0.skipsInPlayback }.firstIndex { $0.listenKey == key }
        }.map { $0 + 1 }

        let playable = chapters.filter { !$0.skipsInPlayback && !$0.isLink }
        let total = playable.reduce(0) { $0 + $1.estimatedMinutes }
        let left = playable.reduce(0) { sum, chapter in
            switch PageProgress.of(chapter) {
            case .finished: sum
            case .partWay(_, let minutes): sum + minutes
            default: sum + chapter.estimatedMinutes
            }
        }
        minutesLeft = left
        let started = playable.contains { $0.finishedAt != nil || PageProgress.isPartWay($0) }
        fraction = total > 0 && started ? 1 - Double(left) / Double(total) : nil
    }
}
