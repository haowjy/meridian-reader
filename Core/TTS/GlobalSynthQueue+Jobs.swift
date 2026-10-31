import Foundation

/// The values `GlobalSynthQueue` works with: its jobs, the persisted work it adopts
/// (`adoptPending` folds it in), what a producer gets back for a chunk, the staged chapter, and
/// the keys waiters are filed under.
extension GlobalSynthQueue {
    struct ArticleJob: Equatable {
        var cacheKey: UUID
        var paragraphs: [String] {
            didSet {
                guard paragraphs != oldValue else { return }
                paragraphHashes = paragraphs.map(ArticleIdentity.paragraphHash)
                missing = nil
            }
        }
        /// `ArticleIdentity.paragraphHash` of each paragraph (chunk scratch dirs, failure marks):
        /// hashed when the text is set, not again for every chunk the worker picks.
        private(set) var paragraphHashes: [String]
        var plan: BakePriorityPlan
        var isEphemeral: Bool
        /// The paragraphs still needing audio, kept between picks (nil: work it out again).
        var missing: MissingParagraphs?

        init(cacheKey: UUID, paragraphs: [String], plan: BakePriorityPlan, isEphemeral: Bool) {
            self.cacheKey = cacheKey
            self.paragraphs = paragraphs
            self.paragraphHashes = paragraphs.map(ArticleIdentity.paragraphHash)
            self.plan = plan
            self.isEphemeral = isEphemeral
        }

        /// The kept missing paragraphs when they are still `target`'s at the article's index
        /// change `changes`; else `compute` (of the job's paragraphs) is kept and returned.
        mutating func missing(in target: RenderTarget, changes: UInt64, compute: ([String]) -> [Int]) -> [Int] {
            if let missing, missing.holds(for: target, at: changes) { return missing.paragraphs }
            let paragraphs = compute(self.paragraphs)
            missing = MissingParagraphs(target: target, indexChanges: changes, paragraphs: paragraphs)
            return paragraphs
        }

        /// Paragraph `index` has audio in `target`'s voice now: the kept list loses it, when it was
        /// current (`before`: the article's index changes then); `after` is the count now. Else the
        /// next pick works the list out again.
        mutating func noteRendered(_ index: Int, in target: RenderTarget, changes before: UInt64, after: UInt64) {
            guard var kept = missing, kept.holds(for: target, at: before) else {
                missing = nil
                return
            }
            kept.paragraphs.removeAll { $0 == index }
            kept.indexChanges = after
            missing = kept
        }
    }

    /// A job's paragraphs that still need audio in `target`'s voice
    /// (`ArticleAudioCache.missingParagraphs`), as of its article's index change `indexChanges`
    /// (`ArticleAudioCache.indexChanges(of:)`). Worked out again when the text, the voice or the
    /// article's audio changes; the queue's own publish shortens it instead.
    struct MissingParagraphs: Equatable {
        var target: RenderTarget
        var indexChanges: UInt64
        var paragraphs: [Int]

        func holds(for target: RenderTarget, at changes: UInt64) -> Bool {
            self.target == target && indexChanges == changes
        }
    }

    struct ParagraphKey: Hashable {
        var cacheKey: UUID
        var index: Int
    }

    /// A chunk a listener waits for.
    struct ChunkKey: Hashable {
        var cacheKey: UUID
        var index: Int
        var chunk: Int
    }

    /// Pending bake job (persisted by `PendingBakeJobStore`).
    struct PendingWork: Equatable {
        var cacheKey: UUID
        var paragraphs: [String]
        var priorityStart: Int
        var isEphemeral: Bool
    }

    /// Fold persisted pending jobs into the queue (at the end of the launch's hold, and when
    /// audio held for library work is let go).
    ///
    /// The active article / playhead stays #1:
    /// - `focusKey` (the article the user most recently opened / listened to) is adopted first
    ///   and becomes #1 unless it already is (its live plan is then left alone);
    /// - any other job becomes #1 only when the queue has no #1 at all;
    /// - everything else — including jobs started mid-article (`priorityStart > 0`) — is demoted
    ///   behind #1, keeping its mid-article plan for when its turn comes.
    func adoptPending(_ pending: [PendingWork], focusKey: UUID? = nil) {
        var ordered = pending
        if let focusKey, let i = ordered.firstIndex(where: { $0.cacheKey == focusKey }) {
            ordered.insert(ordered.remove(at: i), at: 0)
        }
        for job in ordered {
            let primary = primaryCacheKey
            guard primary != job.cacheKey else { continue } // #1 with a live plan: keep its playhead cursor
            enqueue(cacheKey: job.cacheKey, paragraphs: job.paragraphs, from: job.priorityStart,
                    isEphemeral: job.isEphemeral, at: primary == nil || job.cacheKey == focusKey ? .front : .back)
        }
    }

    /// What the producer should play for (paragraph, chunk).
    enum ChunkResolution {
        /// Per-chunk CAF (paragraph still building, or kept scratch).
        case chunk(URL)
        /// Paragraph already stitched; play `url` from `startTime` (chunk boundary).
        case paragraph(URL, startTime: TimeInterval)

        /// The file to play.
        var fileURL: URL {
            switch self {
            case .chunk(let url), .paragraph(let url, _): url
            }
        }
    }

    /// The next chapter staged behind the one playing (`stageNext`).
    struct StagedJob: Equatable {
        var cacheKey: UUID
        /// The chapter playing when it was staged: the staged job sits right behind its job.
        var behind: UUID?
        /// Paragraphs from the top it renders before it plays.
        var cap: Int
        /// The job was in the queue before it was staged (a book's demoted bake): unstaging
        /// leaves it there.
        var wasQueued: Bool
    }
}

/// Render order for one article: the priority stretch from `priorityStart` (the resume point, a
/// jump, 0 for a save) to the end, then the missing paragraphs above it, so the whole article
/// lands on disk.
struct BakePriorityPlan: Equatable, Sendable {
    /// First paragraph of the priority stretch.
    let priorityStart: Int
    let paragraphCount: Int

    init(resume: Int, count: Int) {
        priorityStart = max(0, min(resume, max(count - 1, 0)))
        paragraphCount = count
    }

    /// `missing` (ascending) in render order.
    func orderedWork(missing: [Int]) -> [Int] {
        let start = min(priorityStart, paragraphCount)
        let missingSet = Set(missing)
        return (start..<paragraphCount).filter(missingSet.contains) + (0..<start).filter(missingSet.contains)
    }
}
