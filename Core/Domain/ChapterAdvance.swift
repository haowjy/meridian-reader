import Foundation

/// The rule for folders (books, followed stories and any other folder, decision D15): when a page
/// ends, the next page that plays starts; when there is none, playback stops. Pure, so it is
/// tested without SwiftData: it works on a snapshot of the folder's pages in their full play order
/// (`LibraryStore.chapterSnapshot`), skipped ones included, so a chapter marked *Skip in Playback*
/// while it played is still found.
///
/// A page plays when it isn't skipped: a page with text, or a followed story's chapter still
/// waiting for its text (`isWaiting`). Playback stops before a waiting chapter rather than skip
/// it, so a story is never heard out of order; Follow fetches it first, the one after the playing
/// page ahead of the rest (`FollowCenter`). A link anywhere else (a favorite) is skipped.
enum ChapterAdvance {
    struct Chapter: Equatable {
        var key: UUID
        /// A followed story's chapter whose text isn't fetched yet.
        var isWaiting: Bool
        var skipsInPlayback: Bool
        var isFinished: Bool

        init(key: UUID, isWaiting: Bool = false, skipsInPlayback: Bool = false, isFinished: Bool = false) {
            self.key = key
            self.isWaiting = isWaiting
            self.skipsInPlayback = skipsInPlayback
            self.isFinished = isFinished
        }
    }

    enum Next: Equatable {
        /// A chapter with text: it plays.
        case ready(UUID)
        /// A chapter still waiting for its text: playback stops before it.
        case waiting(UUID)
        /// The end of the folder.
        case none

        /// The chapter it names, ready or waiting.
        var key: UUID? {
            switch self {
            case .ready(let key), .waiting(let key): key
            case .none: nil
            }
        }
    }

    /// Where Continue starts: the place (the chapter that last played) at its saved spot while
    /// unfinished; past it once finished; with no place, the first playable chapter. A finished
    /// folder (nothing playable after its place) starts again at its first playable chapter.
    static func start(_ chapters: [Chapter], place: UUID?) -> Next {
        guard let place, let index = chapters.firstIndex(where: { $0.key == place }) else {
            return first(in: chapters[...])
        }
        let chapter = chapters[index]
        if !chapter.isFinished, !chapter.skipsInPlayback { return classify(chapter) }
        let next = first(in: chapters[(index + 1)...])
        return next == .none ? first(in: chapters[...]) : next
    }

    /// Carrying on: the next playable chapter after `articleKey`. A page that isn't one of
    /// `chapters` (a page in no folder) has none.
    static func after(_ articleKey: UUID, in chapters: [Chapter]) -> Next {
        guard let index = chapters.firstIndex(where: { $0.key == articleKey }) else { return .none }
        return first(in: chapters[(index + 1)...])
    }

    private static func first(in chapters: ArraySlice<Chapter>) -> Next {
        chapters.first { !$0.skipsInPlayback }.map(classify) ?? .none
    }

    private static func classify(_ chapter: Chapter) -> Next {
        chapter.isWaiting ? .waiting(chapter.key) : .ready(chapter.key)
    }
}
