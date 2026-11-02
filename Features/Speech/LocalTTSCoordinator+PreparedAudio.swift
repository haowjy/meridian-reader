import Foundation

/// Prepared audio (`PrepareCenter`) render through the one render queue as ordinary bake jobs
/// (`startBakeIfNeeded`, `Demand.queued`): behind the article playing and the chapter staged after
/// it, held while the phone is hot or in Low Power Mode, in front and, while audio plays, in the
/// background. Nothing here renders on its own.
extension LocalTTSCoordinator: PrepareRendering {
    func queuePrepare(cacheKey: UUID, paragraphs: [String]) -> PrepareQueueing {
        guard wantsLocalBake else { return .notRendering }
        if let notice = cantReadNotice(of: cacheKey, paragraphs: paragraphs) { return .cantRead(notice) }
        guard !audioCache.held.contains(cacheKey) else { return .held }
        if missingPrepareParagraphs(cacheKey: cacheKey, paragraphs: paragraphs) == 0 { return .ready }
        startBakeIfNeeded(articleID: cacheKey, paragraphs: paragraphs)
        return .rendering
    }

    /// Paragraphs that still need audio in the prepare voice (`ArticleAudioCache.missingParagraphs`).
    /// It reads `bakeMarksRevision`, so a view showing it redraws as audio is rendered.
    func missingPrepareParagraphs(cacheKey: UUID, paragraphs: [String]) -> Int {
        _ = bakeMarksRevision
        let selection = effectiveSelection(of: cacheKey)
        guard let voice = cacheVoice(of: selection) else { return paragraphs.count }
        return audioCache.missingParagraphs(articleID: cacheKey, paragraphs: paragraphs,
                                            engineID: selection.engine.rawValue, voiceID: voice, plans: chunkPlans).count
    }

    func renderedVoice(of key: UUID) -> String? {
        audioCache.renderedVoice(articleID: key)
    }

    /// C138a: the cache voice `key`'s audio is in: its own selection's, else the default's.
    func prepareVoice(of key: UUID) -> String? { cacheVoice(of: effectiveSelection(of: key)) }

    /// The launch's hold is over (so no job waits for it), and `cacheKey`'s job is neither in the
    /// queue nor in the pending jobs on disk.
    func bakeJobEnded(cacheKey: UUID) -> Bool {
        !isHeldForLaunch && !synthQueue.hasJob(cacheKey: cacheKey)
            && !pendingBakes.pendingJobs().contains { $0.articleID == cacheKey }
    }

    /// The chapter staged to play after the playing one (`stageNextChapter`): listening needs it.
    var stagedChapterKey: UUID? { synthQueue.stagedCacheKey }
}
