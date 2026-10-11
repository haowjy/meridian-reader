import Foundation

/// The rule for folders (books and series, and any other folder, decision D15): when a page ends,
/// the next playable page starts; when there is none, playback stops. Pure, so it is tested
/// without SwiftData: it works on a snapshot of the folder's pages in their full play order
/// (`LibraryStore.chapterSnapshot`), skipped ones included, so a chapter marked *Skip in
/// Playback* while it played is still found.
///
/// A page is playable when it isn't skipped: a saved page, or a series chapter not fetched yet
/// (a link), which is fetched first. A link anywhere else is skipped.
enum ChapterAdvance {
    struct Chapter: Equatable {
        var key: UUID
        /// A series chapter not fetched yet.
        var isLink: Bool
        var skipsInPlayback: Bool
        var isFinished: Bool
        /// Why the chapter can't be fetched (locked, needs the browser), as the notice playback
        /// ends with.
        var blockedReason: String?

        init(key: UUID, isLink: Bool = false, skipsInPlayback: Bool = false, isFinished: Bool = false,
             blockedReason: String? = nil) {
            self.key = key
            self.isLink = isLink
            self.skipsInPlayback = skipsInPlayback
            self.isFinished = isFinished
            self.blockedReason = blockedReason
        }
    }

    enum Next: Equatable {
        /// A saved chapter.
        case ready(UUID)
        /// A link chapter: fetch it first.
        case pending(UUID)
        /// The next chapter can't be had (locked, needs the browser).
        case unavailable(reason: String)
        /// The end of the book or series.
        case none
    }

    enum Decision: Equatable {
        case play(UUID)
        case waitForFetch(UUID)
        /// Playback stops; `notice` says why when it isn't the end of the book.
        case end(notice: String?)
    }

    /// Where Continue starts: the place (the chapter that last played) at its saved spot while
    /// unfinished; past it once finished; with no place, the first playable chapter. A finished
    /// book (nothing playable after its place) starts again at its first playable chapter.
    static func start(_ chapters: [Chapter], place: UUID?) -> Next {
        guard let place, let index = chapters.firstIndex(where: { $0.key == place }) else {
            return first(in: chapters[...])
        }
        let chapter = chapters[index]
        if !chapter.isFinished, !chapter.skipsInPlayback { return classify(chapter) }
        let next = first(in: chapters[(index + 1)...])
        return next == .none ? first(in: chapters[...]) : next
    }

    /// Carrying on: the next playable chapter after `pageKey`. A page that isn't one of
    /// `chapters` (a page in no book or series) has none.
    static func after(_ pageKey: UUID, in chapters: [Chapter]) -> Next {
        guard let index = chapters.firstIndex(where: { $0.key == pageKey }) else { return .none }
        return first(in: chapters[(index + 1)...])
    }

    static func decide(_ next: Next) -> Decision {
        switch next {
        case .ready(let key): .play(key)
        case .pending(let key): .waitForFetch(key)
        case .unavailable(let reason): .end(notice: reason)
        case .none: .end(notice: nil)
        }
    }

    private static func first(in chapters: ArraySlice<Chapter>) -> Next {
        chapters.first { !$0.skipsInPlayback }.map(classify) ?? .none
    }

    private static func classify(_ chapter: Chapter) -> Next {
        if let reason = chapter.blockedReason { return .unavailable(reason: reason) }
        return chapter.isLink ? .pending(chapter.key) : .ready(chapter.key)
    }
}
