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

    /// Also when a prepare stops (paused, removed). `PrepareCenter` never asks this of a page
    /// listening needs (`needsAudio`): removing a job fails its chunk waiters.
    func removeBakeJob(cacheKey: UUID) {
        synthQueue.remove(cacheKey: cacheKey)
        pendingBakes.removePending(articleID: cacheKey)
    }

    func markListenCacheSaved(_ key: UUID) throws {
        synthQueue.setEphemeral(cacheKey: key, false)
        try audioCache.markSaved(cacheKey: key)
    }

    /// The audio (and the page's playhead) stays.
    func markListenCacheEphemeral(_ key: UUID, canonicalURL: String?) throws {
        synthQueue.setEphemeral(cacheKey: key, true)
        try audioCache.markEphemeral(cacheKey: key, canonicalURL: canonicalURL, lastAccess: Date())
    }

    /// Not memoized (`storedSelection`): a voice record runs inside the save that changed the
    /// voice, before the memo is cleared.
    func selectedCacheVoice(of key: UUID) -> ArticleAudioCache.CacheVoice? {
        let selection = articleSelection(key).flatMap(VoiceSelection.init(stored:)) ?? defaultSelection
        return cacheVoice(of: selection).map { ArticleAudioCache.CacheVoice(engineID: selection.engine.rawValue, voiceID: $0) }
    }

    /// A recording shipped with the app, installed as `key`'s saved audio in the voice the article
    /// speaks in (`ArticleAudioCache.install`). True when audio is there.
    func installRecording(_ recording: URL, as key: UUID, paragraphs: [String]) -> Bool {
        guard audioCache.install(recording: recording, as: key, voice: selectedCacheVoice(of: key),
                                 paragraphs: paragraphs) else { return false }
        noteBakeMarksChanged(of: key)
        return true
    }

    /// The saved bake jobs of audio the work let go are adopted now, not at the next launch.
    func heldAudioChanged() { drainPendingIntoQueue() }

    /// The target was read at init, before the launch maintenance rebuilt the page's paragraphs
    /// or merged it into another page.
    func remapPendingResume(article: UUID, _ move: (ListenResumeTarget) -> ListenResumeTarget) {
        guard let target = pendingResume, target.matches(article) else { return }
        pendingResume = move(target)
    }
}
