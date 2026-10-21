import Foundation

/// Prepared audio (`PrepareCenter`) render through the one render queue as ordinary bake jobs
/// (`startBakeIfNeeded`): behind the article playing and the chapter staged after it, held while
/// the phone is hot or in Low Power Mode. In the background the playing article renders first,
/// in bursts (`RenderAdmission`, `BackgroundRenderWatermarks`); while it is safely ahead and audio
/// plays, a prepare's job takes the same one-thread worker (C94). Nothing here renders on its own.
extension LocalTTSCoordinator: PrepareRendering {
    /// The voice a new article's prepared audio renders in (the Settings default), as a cache voice key.
    var prepareVoice: String? { cacheVoice(of: defaultSelection) }

    func queuePrepare(cacheKey: UUID, paragraphs: [String]) -> PrepareQueueing {
        guard wantsLocalBake else { return .notRendering }
        // C138a: an article in an Apple voice (or a language the engine can't speak) speaks live.
        guard rendersAhead(cacheKey, paragraphs: paragraphs) else { return .speaksLive }
        guard !audioCache.held.contains(cacheKey) else { return .held }
        if missingPrepareParagraphs(cacheKey: cacheKey, paragraphs: paragraphs) == 0 { return .ready }
        startBakeIfNeeded(articleID: cacheKey, paragraphs: paragraphs)
        synthQueue.markPrepare(cacheKey: cacheKey)
        return .rendering
    }

    /// Paragraphs that still need audio in the prepare voice (`ArticleAudioCache.missingParagraphs`).
    /// It reads `bakeMarksRevision`, so a view showing it redraws as audio is rendered.
    func missingPrepareParagraphs(cacheKey: UUID, paragraphs: [String]) -> Int {
        _ = bakeMarksRevision
        let selection = peekSelection(of: cacheKey, paragraphs: paragraphs)
        guard let voice = cacheVoice(of: selection) else { return paragraphs.count }
        return audioCache.missingParagraphs(articleID: cacheKey, paragraphs: paragraphs,
                                            engineID: selection.engine.rawValue, voiceID: voice, plans: chunkPlans).count
    }

    func renderedVoice(of key: UUID) -> String? {
        audioCache.renderedVoice(articleID: key)
    }

    /// C138a: the cache voice `key`'s audio is in: its own selection's, else the default's.
    func prepareVoice(of key: UUID) -> String? { cacheVoice(of: effectiveSelection(of: key)) }

    /// The engine is loaded and the launch's hold over (so no job waits for either), and
    /// `cacheKey`'s job is neither in the queue nor in the pending jobs on disk.
    func bakeJobEnded(cacheKey: UUID) -> Bool {
        usesLocalEngine && !isHeldForLaunch && !synthQueue.hasJob(cacheKey: cacheKey)
            && !pendingBakes.pendingJobs().contains { $0.articleID == cacheKey }
    }

    /// Prepared audio may go on in the background now (C94): audio is playing on a route that renders
    /// there (Kokoro's ONNX CPU route). The render queue still puts the playing article first.
    var rendersPreparedAudioInBackground: Bool { activeRouteRendersInBackground && playingCacheKey != nil }

    /// The chapter staged to play after the playing one (`stageNextChapter`): listening needs it.
    var stagedChapterKey: UUID? { synthQueue.stagedCacheKey }
}
