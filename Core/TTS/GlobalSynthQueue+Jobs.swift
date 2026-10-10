import Foundation

/// The values `GlobalSynthQueue` works with: its jobs, the persisted work it adopts, what a
/// producer gets back for a chunk, and the staged chapter.
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
    }

    /// Pending bake job (persisted by `PendingBakeJobStore`).
    struct PendingWork: Equatable {
        var cacheKey: UUID
        var paragraphs: [String]
        var voiceID: String
        var priorityStart: Int
        var isEphemeral: Bool
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
