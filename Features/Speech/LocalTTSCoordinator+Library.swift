import Foundation

/// What the library's changes do to audio (`LibraryAudioEffects`): the files, the render queue,
/// the saved bake jobs and the crash-resume target move together.
extension LocalTTSCoordinator: LibraryAudioEffects {
    func isPrepared(_ key: UUID) -> Bool { preparedKey(key) }
    func listeningNeeds(_ key: UUID) -> Bool { listeningNeedsKey(key) }

    /// The queue lets the key go before its files do; a delete that fails keeps the saved job.
    func clearListenAudio(for articleID: UUID) throws {
        synthQueue.remove(cacheKey: articleID)
        try audioCache.deleteAudio(for: articleID)
        noteBakeMarksChanged()
        pendingBakes.removePending(articleID: articleID)
    }

    /// Also when a download stops (paused, removed). `DownloadCenter` never asks this of a page
    /// listening needs (`needsAudio`): removing a job fails its chunk waiters.
    func removeBakeJob(cacheKey: UUID) {
        synthQueue.remove(cacheKey: cacheKey)
        pendingBakes.removePending(articleID: cacheKey)
    }

    func markListenCacheSaved(_ key: UUID) {
        audioCache.markSaved(cacheKey: key)
        synthQueue.setEphemeral(cacheKey: key, false)
    }

    /// The audio (and the page's playhead) stays.
    func markListenCacheEphemeral(_ key: UUID, canonicalURL: String?) {
        audioCache.markEphemeral(cacheKey: key, canonicalURL: canonicalURL, lastAccess: Date())
        synthQueue.setEphemeral(cacheKey: key, true)
    }

    /// The target was read at init, before the launch maintenance rebuilt the page's paragraphs
    /// or merged it into another page.
    func remapPendingResume(article: UUID, _ move: (ListenResumeTarget) -> ListenResumeTarget) {
        guard let target = pendingResume, target.matches(article) else { return }
        pendingResume = move(target)
    }
}
