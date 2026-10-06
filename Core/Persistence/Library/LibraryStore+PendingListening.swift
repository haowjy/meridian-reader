import Foundation

/// A page's listening progress (`recordPlayback`, `recordPlaybackStarted`, `recordPosition`,
/// `recordFinished`) written to the context and not stored yet. A save that fails leaves it
/// there for the next one, but a rollback (`LibraryStore.rollBack`, after an edit's save fails)
/// drops every unsaved change in the context, this progress with the edit. So the store keeps it
/// here until a save stores it, and writes it again after each rollback: progress made while
/// saves fail is stored once they work again, and the edit that failed stays undone.
///
/// It holds one entry per page played while saves fail (each from someone pressing play, or
/// playback moving on to the next chapter), and the first save that works empties it. An entry
/// keeps a play's text only when the store may not hold it: the page is new, the play refreshed
/// its text, or it holds changes not stored yet. That keeps it small without a cap; a cap would
/// drop listening the next save could store.
struct PendingListening {
    struct Position: Equatable {
        var paragraph: Int
        var utf16Offset: Int
    }

    /// The text of the latest play that may not find it stored: the article it started from
    /// (`playbackPage(for:)`), or a copy of the library page's text as it started
    /// (`recordPlaybackStarted`). It makes the page again when the rollback dropped the page a
    /// play made (one the library didn't have), and refreshes its text otherwise, so the position
    /// is on the paragraphs it was written for. Nil when each play found the page's text stored.
    var article: ReaderArticle?
    /// The latest start: the page dated and unfinished, a chapter its book's place.
    var startedAt: Date?
    var position: Position?
    /// Played to the end after `startedAt`.
    var finishedAt: Date?

    mutating func start(at date: Date) {
        startedAt = date
        finishedAt = nil
    }

    /// When it last started or finished: pages are written again in that order, so the chapter
    /// that played last is its book's place.
    var latest: Date { max(startedAt ?? .distantPast, finishedAt ?? .distantPast) }
}

extension LibraryStore {
    /// Notes progress about to be written to `page`, until a save stores it.
    func noteListening(_ page: Page, _ change: (inout PendingListening) -> Void) {
        change(&pendingListening[page.listenKey, default: PendingListening()])
    }

    func applyStart(_ page: Page, at date: Date) {
        page.lastPlayedAt = date
        page.finishedAt = nil
        placeChapter(page, at: date)
    }

    func applyPosition(_ page: Page, paragraph: Int, utf16Offset: Int) {
        page.positionParagraph = paragraph
        page.positionUTF16 = utf16Offset
    }

    func applyFinish(_ page: Page, at date: Date) {
        page.finishedAt = date
        page.lastPlayedAt = date
        noteChapterFinished(page, at: date)
    }

    /// After a rollback: the listening progress it dropped is written again, with the dates it
    /// was made at, for the next save to store. A page only a play had made is made again from
    /// its article. Progress for a page that is gone otherwise has nowhere to go and is dropped.
    func writeListeningAgain() {
        guard !pendingListening.isEmpty else { return }
        var written: [String] = []
        for (key, pending) in pendingListening.sorted(by: { $0.value.latest < $1.value.latest }) {
            guard let page = pending.article.map({ playbackPage(for: $0).page }) ?? page(key: key) else {
                pendingListening[key] = nil
                log("listening of \(Self.short(key)) dropped: its page is gone")
                continue
            }
            if let at = pending.startedAt { applyStart(page, at: at) }
            if let position = pending.position {
                applyPosition(page, paragraph: position.paragraph, utf16Offset: position.utf16Offset)
            }
            if let at = pending.finishedAt { applyFinish(page, at: at) }
            written.append(Self.short(key))
        }
        log("rollback: listening written again for \(written.joined(separator: ", "))")
    }
}
