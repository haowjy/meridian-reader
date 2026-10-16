import Foundation

/// Told about the render queue (`LocalTTSCoordinator.renderObserver`).
@MainActor
protocol RenderQueueObserver: AnyObject {
    /// An article's bake job left the queue with nothing more it could render.
    func bakeCompleted(cacheKey: UUID)
    /// Audio was rendered or deleted, or the engine or voice changed. Called often, and inside
    /// the queue's own work: an observer handles it later, not in the call.
    func renderStateChanged()
}

/// Downloads (`DownloadCenter`) render through the one render queue as ordinary bake jobs
/// (`startBakeIfNeeded`): behind the article playing and the chapter staged after it, held while
/// the phone is hot or in Low Power Mode, and parked in the background, where only the playing
/// article renders, in bursts (`RenderAdmission`, `BackgroundRenderWatermarks`). Nothing here
/// renders on its own.
extension LocalTTSCoordinator {
    /// The voice downloads render in, as a cache voice key: the selected on-device voice, or, while
    /// Apple's voice is selected, the voice the default on-device engine would use.
    var downloadVoice: String? {
        (wantsLocalBake ? activeLocalEngineID : engines.defaultLocalEngineID).flatMap(cacheVoice(of:))
    }

    /// An on-device voice that renders downloads is selected (it may still be loading).
    var rendersDownloads: Bool { wantsLocalBake }

    /// "Kokoro Heart" for a cache voice key.
    func voiceLabel(forCacheVoice voiceID: String) -> String {
        engines.voiceLabel(forCacheVoice: voiceID)
    }

    enum DownloadQueueing: Equatable {
        /// Its bake job is queued (or waits for the engine to load); `bakeCompleted` follows.
        case rendering
        /// Every paragraph that has words is rendered in the download voice already.
        case ready
        /// The engine doesn't speak its language: Apple's voice speaks it, live.
        case speaksLive
        /// Its audio waits for library work an earlier launch couldn't finish (`ArticleAudioCache.held`).
        case held
        /// No on-device voice that renders downloads is selected.
        case notRendering
    }

    /// Queue `paragraphs` of `cacheKey` to render in full in the download voice.
    func queueDownload(cacheKey: UUID, paragraphs: [String]) -> DownloadQueueing {
        guard rendersDownloads else { return .notRendering }
        guard localLanguageAllows(paragraphs) else { return .speaksLive }
        guard !audioCache.held.contains(cacheKey) else { return .held }
        if missingDownloadParagraphs(cacheKey: cacheKey, paragraphs: paragraphs) == 0 { return .ready }
        startBakeIfNeeded(articleID: cacheKey, paragraphs: paragraphs)
        return .rendering
    }

    /// Paragraphs that still need audio in the download voice (`ArticleAudioCache.missingParagraphs`).
    func missingDownloadParagraphs(cacheKey: UUID, paragraphs: [String]) -> Int {
        guard let voice = downloadVoice else { return paragraphs.count }
        return audioCache.missingParagraphs(articleID: cacheKey, paragraphs: paragraphs, engineID: cacheEngineID,
                                            voiceID: voice, plans: chunkPlans).count
    }

    /// How much of `cacheKey`'s audio is rendered in the download voice (0…1): 1 once no
    /// paragraph needs audio.
    func downloadFraction(cacheKey: UUID, paragraphs: [String]) -> Double {
        guard !paragraphs.isEmpty, downloadVoice != nil else { return 0 }
        _ = bakeMarksRevision
        let missing = missingDownloadParagraphs(cacheKey: cacheKey, paragraphs: paragraphs)
        return Double(paragraphs.count - missing) / Double(paragraphs.count)
    }

    /// The bake job of `cacheKey` is still queued, or waits on disk for the engine to load.
    func hasDownloadJob(cacheKey: UUID) -> Bool {
        synthQueue.hasJob(cacheKey: cacheKey)
            || PendingBakeJobStore.shared.pendingJobs().contains { $0.articleID == cacheKey }
    }

    /// A download stops (paused, removed): its bake job leaves the queue, unless the page is what
    /// plays or the chapter staged to play next, whose audio listening needs.
    func cancelDownload(cacheKey: UUID) {
        guard cacheKey != playingCacheKey, cacheKey != synthQueue.stagedCacheKey else { return }
        synthQueue.remove(cacheKey: cacheKey)
        PendingBakeJobStore.shared.removePending(articleID: cacheKey)
    }
}
