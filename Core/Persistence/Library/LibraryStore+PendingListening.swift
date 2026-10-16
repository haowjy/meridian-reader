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
///
/// An entry is progress in one text, and is written again only on a page holding that text.
struct PendingListening {
    struct Position: Equatable {
        var paragraph: Int
        var utf16Offset: Int
    }

    /// The text the progress was made in: what its page held when it was written
    /// (`LibraryStore.textFingerprint(of:)`), which is the text the session played, since the
    /// recorder writes only then (`LibraryStore.holds`).
    var text: String?
    /// The text of the latest play that may not find it stored: the article it started from
    /// (`playbackPage(for:)`), or a copy of the library page's text as it started
    /// (`recordPlaybackStarted`). It makes the page again when the rollback dropped the page a
    /// play made (one the library didn't have), and refreshes its text otherwise, so the position
    /// is on the paragraphs it was written for. Nil when each play found the page's text stored.
    var article: ReaderArticle?
    /// The latest start: the page dated and unfinished, a chapter its book's place.
    var startedAt: Date?
    /// A listen to an article started (`recordPlayback`): a page removed from the Library is
    /// played without saving again (`Page.removedAt` cleared).
    var listened = false
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
    /// Notes progress about to be written to `page`, in the text the page holds now, until a save
    /// stores it. What an entry noted in other text (the page's text changed since, unsaved) was
    /// that text's: it starts over.
    func noteListening(_ page: Page, _ change: (inout PendingListening) -> Void) {
        let text = textFingerprint(of: page)
        var pending = pendingListening[page.listenKey].flatMap { $0.text == text ? $0 : nil } ?? PendingListening(text: text)
        change(&pending)
        pendingListening[page.listenKey] = pending
    }

    func applyStart(_ page: Page, at date: Date) {
        page.lastPlayedAt = date
        page.finishedAt = nil
        placeChapter(page)
    }

    func applyPosition(_ page: Page, paragraph: Int, utf16Offset: Int) {
        page.positionParagraph = paragraph
        page.positionUTF16 = utf16Offset
    }

    func applyFinish(_ page: Page, at date: Date) {
        page.finishedAt = date
        page.lastPlayedAt = date
    }

    /// After a rollback: the listening progress it dropped is written again, with the dates it
    /// was made at, for the next save to store. A page only a play had made is made again from
    /// its article, and a page whose text the play refreshed gets that text back. Progress is
    /// written only on a page holding the text it was made in (`holds`); for a page that is gone,
    /// or reads other text once rolled back, it has nowhere to go and is dropped.
    func writeListeningAgain() {
        guard !pendingListening.isEmpty else { return }
        var written: [String] = []
        for (key, pending) in pendingListening.sorted(by: { $0.value.latest < $1.value.latest }) {
            guard let page = pending.article.map({ playbackPage(for: $0).page }) ?? page(key: key) else {
                pendingListening[key] = nil
                log("listening of \(Self.short(key)) dropped: its page is gone")
                continue
            }
            guard holds(page, text: pending.text) else {
                pendingListening[key] = nil
                log("listening of \(Self.short(key)) dropped: its page holds other text")
                continue
            }
            if let at = pending.startedAt { applyStart(page, at: at) }
            if pending.listened { page.removedAt = nil }
            if let position = pending.position {
                applyPosition(page, paragraph: position.paragraph, utf16Offset: position.utf16Offset)
            }
            if let at = pending.finishedAt { applyFinish(page, at: at) }
            written.append(Self.short(key))
        }
        log("rollback: listening written again for \(written.joined(separator: ", "))")
    }

    // MARK: - The text listened to

    /// Whether `page` holds `text` now, the text a session plays
    /// (`PlaybackSessionState.textFingerprint`): its stored listen paragraphs are that text.
    /// Listening progress (a start, a position, an end) is stored on a page only while it does
    /// (`ListeningProgressRecorder`, `pageFinished`, `writeListeningAgain`), and a session follows
    /// a merged key only onto a page holding its text (`keyMerged`). A key can name other text than
    /// a session on it plays: a chapter a *Replace* revised or brought back under the key, a page
    /// refreshed on open while it played, a resumed or staged session older than its page. A
    /// position in one text means nothing in another.
    func holds(_ page: Page, text: String?) -> Bool {
        guard let text else { return false }
        return textFingerprint(of: page) == text
    }

    /// The text `page` holds: `ArticleIdentity.contentFingerprint` of its stored listen paragraphs,
    /// nil when it stores none under the current rules. The last stored text hashed is kept with
    /// its fingerprint, so the recorder's write on each paragraph compares the stored bytes rather
    /// than hashing them again.
    func textFingerprint(of page: Page) -> String? {
        guard page.listenBlocksVersion == ListenHTMLBlocks.version, let data = page.listenBlocksData else { return nil }
        if let last = lastTextHashed, last.data == data { return last.fingerprint }
        guard let paragraphs = Page.decodeListenParagraphs(data, version: page.listenBlocksVersion) else { return nil }
        let fingerprint = ArticleIdentity.contentFingerprint(paragraphs: paragraphs)
        lastTextHashed = (data, fingerprint)
        return fingerprint
    }
}
