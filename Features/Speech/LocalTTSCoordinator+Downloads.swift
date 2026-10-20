import Foundation

/// Downloads (`DownloadCenter`) render through the one render queue as ordinary bake jobs
/// (`startBakeIfNeeded`): behind the article playing and the chapter staged after it, held while
/// the phone is hot or in Low Power Mode. In the background the playing article renders first,
/// in bursts (`RenderAdmission`, `BackgroundRenderWatermarks`); while it is safely ahead and audio
/// plays, a download's job takes the same one-thread worker (C94). Nothing here renders on its own.
extension LocalTTSCoordinator: DownloadRendering {
    /// The voice downloads render in, as a cache voice key: the selected on-device voice, or, while
    /// Apple's voice is selected, the voice the default on-device engine would use.
    var downloadVoice: String? {
        (wantsLocalBake ? activeLocalEngineID : engines.defaultLocalEngineID).flatMap(cacheVoice(of:))
    }

    func queueDownload(cacheKey: UUID, paragraphs: [String]) -> DownloadQueueing {
        guard wantsLocalBake else { return .notRendering }
        guard localLanguageAllows(paragraphs) else { return .speaksLive }
        guard !audioCache.held.contains(cacheKey) else { return .held }
        if missingDownloadParagraphs(cacheKey: cacheKey, paragraphs: paragraphs) == 0 { return .ready }
        startBakeIfNeeded(articleID: cacheKey, paragraphs: paragraphs)
        synthQueue.markDownload(cacheKey: cacheKey)
        return .rendering
    }

    /// Paragraphs that still need audio in the download voice (`ArticleAudioCache.missingParagraphs`).
    /// It reads `bakeMarksRevision`, so a view showing it redraws as audio is rendered.
    func missingDownloadParagraphs(cacheKey: UUID, paragraphs: [String]) -> Int {
        _ = bakeMarksRevision
        guard let voice = downloadVoice else { return paragraphs.count }
        return audioCache.missingParagraphs(articleID: cacheKey, paragraphs: paragraphs, engineID: cacheEngineID,
                                            voiceID: voice, plans: chunkPlans).count
    }

    func renderedVoice(of key: UUID) -> String? {
        audioCache.renderedVoice(articleID: key)
    }

    /// The engine is loaded and the launch's hold over (so no job waits for either), and
    /// `cacheKey`'s job is neither in the queue nor in the pending jobs on disk.
    func bakeJobEnded(cacheKey: UUID) -> Bool {
        usesLocalEngine && !isHeldForLaunch && !synthQueue.hasJob(cacheKey: cacheKey)
            && !pendingBakes.pendingJobs().contains { $0.articleID == cacheKey }
    }

    /// Downloads may go on in the background now (C94): audio is playing on a route that renders
    /// there (Kokoro's ONNX CPU route). The render queue still puts the playing article first.
    var rendersDownloadsInBackground: Bool { activeRouteRendersInBackground && playingCacheKey != nil }

    /// The chapter staged to play after the playing one (`stageNextChapter`): listening needs it.
    var stagedChapterKey: UUID? { synthQueue.stagedCacheKey }
}
