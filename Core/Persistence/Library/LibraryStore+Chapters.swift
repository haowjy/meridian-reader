import Foundation

/// Books and series as playback goes through them: the chapters `ChapterAdvance` works on, the
/// book's place (`Folder.currentPageKey`, the chapter that last played) and when it is finished.
extension LibraryStore {
    /// The folder's chapters in play order, skipped ones included. A link page plays (after its
    /// fetch) only in a series; a locked one, or one that needs the browser, says why it can't.
    func chapterSnapshot(of folder: Folder) -> [ChapterAdvance.Chapter] {
        guard folder.kind.isFixed else { return [] }
        return playOrder(of: folder).map { page in
            ChapterAdvance.Chapter(key: page.listenKey, isLink: page.isLink,
                                   skipsInPlayback: page.skipsInPlayback || (page.isLink && folder.kind != .series),
                                   isFinished: page.finishedAt != nil,
                                   blockedReason: page.isLink ? Self.blockedReason(page.fetchState) : nil)
        }
    }

    /// The notice playback ends with at a link chapter that can't be fetched.
    static func blockedReason(_ state: PageFetchState) -> String? {
        switch state {
        case .locked: String(localized: "Next chapter is locked")
        case .needsBrowser: String(localized: "Open in browser to continue")
        case .none, .fetching, .failed: nil
        }
    }

    /// Where Continue on a book or series starts (`ChapterAdvance.start`): its place at the saved
    /// spot while unfinished, else the next chapter from its start. A finished book starts again
    /// at its first chapter and is no longer finished. nil when that chapter isn't saved yet.
    func continueStart(of folder: Folder) -> (page: Page, paragraph: Int, utf16Offset: Int)? {
        let next = ChapterAdvance.start(chapterSnapshot(of: folder), place: folder.currentPageKey)
        guard case .ready(let key) = next, let page = page(key: key) else { return nil }
        if folder.finishedAt != nil {
            folder.finishedAt = nil
            commit("restart book")
        }
        guard key == folder.currentPageKey, page.finishedAt == nil else { return (page, 0, 0) }
        return (page, page.positionParagraph, page.positionUTF16)
    }

    /// A chapter started playing at `date`: its book's or series' place moves to it, and the
    /// book is listened to again (dated, unfinished). Saved by the caller.
    func placeChapter(_ page: Page, at date: Date) {
        guard let folder = page.folder, folder.kind.isFixed, let key = page.key else { return }
        folder.currentPageKey = key
        folder.lastPlayedAt = date
        folder.finishedAt = nil
    }

    /// A chapter played to its end at `date`: the book or series is finished when no playable
    /// chapter comes after it. Saved by the caller.
    func noteChapterFinished(_ page: Page, at date: Date) {
        guard let folder = page.folder, folder.kind.isFixed else { return }
        folder.lastPlayedAt = date
        if ChapterAdvance.after(page.listenKey, in: chapterSnapshot(of: folder)) == .none {
            folder.finishedAt = date
        }
    }
}
