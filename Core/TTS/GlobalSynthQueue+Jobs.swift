import Foundation

/// The values `GlobalSynthQueue` works with: its jobs, the persisted work it adopts
/// (`adoptPending` folds it in), what a producer gets back for a chunk, the staged chapter, and
/// the keys chunk plans and waiters are filed under.
extension GlobalSynthQueue {
    struct ArticleJob: Equatable {
        var cacheKey: UUID
        var paragraphs: [String] {
            didSet {
                if paragraphs != oldValue { paragraphHashes = paragraphs.map(ArticleIdentity.paragraphHash) }
            }
        }
        /// `ArticleIdentity.paragraphHash` of each paragraph (chunk scratch dirs, failure marks):
        /// hashed when the text is set, not again for every chunk the worker picks.
        private(set) var paragraphHashes: [String]
        var voiceID: String
        var plan: BakePriorityPlan
        /// FIFO demotion order among non-#1 articles (lower = older / demoted earlier).
        var demoteOrder: Int
        var isEphemeral: Bool

        init(cacheKey: UUID, paragraphs: [String], voiceID: String, plan: BakePriorityPlan,
             demoteOrder: Int, isEphemeral: Bool) {
            self.cacheKey = cacheKey
            self.paragraphs = paragraphs
            self.paragraphHashes = paragraphs.map(ArticleIdentity.paragraphHash)
            self.voiceID = voiceID
            self.plan = plan
            self.demoteOrder = demoteOrder
            self.isEphemeral = isEphemeral
        }

        /// Of `work` (missing paragraphs in plan order), those that may render now: below `cap`
        /// (a staged chapter's opening), and with `aheadOnly` only from the plan's start (the
        /// playhead) on.
        func renderable(_ work: [Int], cap: Int?, aheadOnly: Bool) -> [Int] {
            work.filter { $0 < (cap ?? .max) && !(aheadOnly && $0 < plan.priorityStart) }
        }
    }

    /// A chunk plan's cache key: plans are per engine and text.
    struct ChunkPlanKey: Hashable {
        var engine: String
        var text: String
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
        var voiceID: String
        var priorityStart: Int
        var isEphemeral: Bool
    }

    /// Fold persisted pending jobs into the queue after the local engine warms.
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
            if primary == job.cacheKey {
                continue // already #1 with a live plan; don't reset its playhead cursor
            } else if primary == nil || job.cacheKey == focusKey {
                openArticle(cacheKey: job.cacheKey, paragraphs: job.paragraphs,
                            voiceID: job.voiceID, resumeParagraph: job.priorityStart, isEphemeral: job.isEphemeral)
            } else {
                enqueueDemoted(cacheKey: job.cacheKey, paragraphs: job.paragraphs,
                               voiceID: job.voiceID, resumeParagraph: job.priorityStart, isEphemeral: job.isEphemeral)
            }
        }
    }

    /// What the producer should play for (paragraph, chunk).
    enum ChunkResolution {
        /// Per-chunk CAF (paragraph still building, or kept scratch).
        case chunk(URL)
        /// Paragraph already stitched; play `url` from `startTime` (chunk boundary).
        case paragraph(URL, startTime: TimeInterval)
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
