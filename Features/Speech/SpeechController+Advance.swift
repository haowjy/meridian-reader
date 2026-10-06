import Foundation

/// What the controller keeps between chapters of a book or series: the next chapter staged to
/// render, a link chapter being fetched, and the boundary the timing log measures.
struct ChapterFlow {
    /// A chapter that ended, until the next one is audible (`chapter_boundary`).
    struct Boundary {
        var from: UUID
        var to: UUID?
        var endedAt: CFAbsoluteTime
        /// The audio session's deactivations and the lock screen's clears when it ended: neither
        /// may happen before the next chapter sounds.
        var deactivations: Int
        var lockScreenClears: Int
        /// The next chapter's first paragraph was rendered when it started.
        var nextWasRendered = false
    }

    /// How long playback waits, silent, for a link chapter's fetch before it ends. Short in the
    /// background, where iOS may suspend an app holding a silent audio session.
    struct WaitLimits {
        var foreground: TimeInterval = 30
        var background: TimeInterval = 5
    }

    /// A link chapter being fetched: what plays once it arrives, and when the wait gives up.
    struct Wait {
        var key: UUID
        var folderID: UUID
        var token: UUID
        var deadline: CFAbsoluteTime
    }

    var boundary: Boundary?
    /// The chapter whose successor has been staged (once per chapter).
    var stagedAfter: UUID?
    /// The successor's session, loaded when it was staged.
    var nextSession: SpeechSession?
    var wait: Wait?
    var fetch: Task<Void, Never>?
    var fetchTimeout: Task<Void, Never>?
    var waitLimits = WaitLimits()
}

/// Playback through a book or series: when a chapter ends, the next playable one starts in place,
/// without deactivating the audio session, clearing the session or the lock screen; when there is
/// none, playback stops as for any page. The rule is `ChapterAdvance`; the library is reached
/// through `nextChapters`. See docs/LISTEN_PLAYBACK.md, "Books and series".
extension SpeechController {
    static let nextChapterUnavailable = "Couldn't get the next chapter"

    /// The bound engine played the page to its end (or there was nothing left to speak). The
    /// controller decides before the session sees `finished`: a chapter with a next one carries
    /// on; anything else finishes, its page staying bound.
    func pageEnded(restartBake: Bool) {
        guard let key = playback.articleID, let folderID = playback.folderID, let library = nextChapters else {
            completeArticle(restartBake: restartBake)
            return
        }
        let decision = ChapterAdvance.decide(ChapterAdvance.after(key, in: library.chapters(of: folderID)))
        ListenTimingLog.log("chapter_advance", [
            "from": ListenTimingLog.shortKey(key), "decision": Self.describe(decision),
            "app_phase": localTTS.synthQueue.runState.phase.rawValue,
        ], console: true)
        switch decision {
        case .play(let next):
            beginBoundary(from: key)
            library.pageFinished(key: key, text: playback.textFingerprint)
            advance(to: next, in: folderID)
        case .waitForFetch(let next):
            beginBoundary(from: key)
            library.pageFinished(key: key, text: playback.textFingerprint)
            awaitChapter(next, in: folderID)
        case .end(let notice):
            if let notice { ListenDebugLog.shared.append("chapter: \(notice)") }
            completeArticle(restartBake: restartBake)
        }
    }

    /// Contents → a chapter: it plays from its start, replacing what plays, and the book or
    /// series carries on from it.
    func playPage(_ key: UUID) {
        guard let session = nextChapters?.load(key) else { return }
        noteUserIntent()
        start(session, fromParagraph: 0)
    }

    /// Nothing carries on from the bound page any more (another page binds, Stop Listening): the
    /// staged chapter is unstaged and a fetch in flight is dropped.
    func endChapterFlow() {
        chapterFlow.fetch?.cancel()
        chapterFlow.fetchTimeout?.cancel()
        chapterFlow = ChapterFlow(waitLimits: chapterFlow.waitLimits)
        localTTS.synthQueue.unstage()
    }

    // MARK: - Carrying on

    private func beginBoundary(from key: UUID) {
        chapterFlow.boundary = ChapterFlow.Boundary(from: key, endedAt: ListenTimingLog.now(),
                                                    deactivations: audioSession.deactivationCount,
                                                    lockScreenClears: lockScreen.clearCount)
    }

    /// The next chapter replaces the page in place and is spoken from its start: `speak` stops
    /// the engines as always, but the audio session stays active and the lock screen only
    /// changes its title. Paused (during a fetch) it is bound at its start without sounding.
    private func advance(to nextKey: UUID, in folderID: UUID) {
        let staged = chapterFlow.nextSession
        let loaded = staged?.id == nextKey ? staged : nextChapters?.load(nextKey)
        chapterFlow.stagedAfter = nil
        chapterFlow.nextSession = nil
        guard let session = loaded, !session.document.isEmpty else {
            ListenTimingLog.log("chapter_advance", ["to": ListenTimingLog.shortKey(nextKey), "error": "not loaded"])
            chapterFlow.boundary = nil
            completeArticle(restartBake: false)
            return
        }
        adoptMeta(of: session)
        let standsIn = appleStandsIn(for: session)
        chapterFlow.boundary?.to = session.id
        chapterFlow.boundary?.nextWasRendered = isRendered(session.id, paragraph: 0, of: session.document.count)
        let commands = handlePageInput(.advance(pageKey: session.id, document: session.document,
                                                folderID: session.folderID ?? folderID))
        guard commands.contains(.enginePlay(from: 0)) else {
            stopEngines()
            chapterFlow.boundary = nil
            return
        }
        speak(fromUTF16Offset: 0, startPaused: false, route: standsIn ? .apple : nil, standsIn: standsIn)
    }

    /// Decision D9: in the background, on a route that can't render there (Core ML), no model
    /// call may start, so a chapter not rendered in full plays in Apple's voice until the app is
    /// in front again. The ONNX route renders in the background and keeps its voice.
    private func appleStandsIn(for session: SpeechSession) -> Bool {
        guard case .local = wantedRoute, localTTS.synthQueue.runState.phase == .background,
              !localTTS.activeRouteRendersInBackground else { return false }
        return !localTTS.audioCache.isAudioReady(articleID: session.id, paragraphCount: session.document.count,
                                                 engineID: localTTS.cacheEngineID,
                                                 voiceID: localTTS.normalizedCacheVoice(cacheVoiceID))
    }

    private func isRendered(_ key: UUID, paragraph: Int, of count: Int) -> Bool {
        guard count > paragraph else { return false }
        return localTTS.audioCache.readyIndices(articleID: key, paragraphCount: count, engineID: localTTS.cacheEngineID,
                                                voiceID: localTTS.normalizedCacheVoice(cacheVoiceID)).contains(paragraph)
    }

    // MARK: - Waiting for a link chapter

    /// A series chapter not fetched yet: playback stays playing, silent ("Preparing next…"),
    /// while it is fetched, then carries on. It ends with "Couldn't get the next chapter" if the
    /// fetch fails or takes longer than the wait limit: the background one when the app is in
    /// the background, or goes there during the wait (`shortenChapterWaitInBackground`).
    private func awaitChapter(_ nextKey: UUID, in folderID: UUID) {
        guard let library = nextChapters else { return }
        stopEngines()
        execute(handlePageInput(.awaitPage))
        let token = UUID()
        let background = localTTS.synthQueue.runState.phase == .background
        let limit = background ? chapterFlow.waitLimits.background : chapterFlow.waitLimits.foreground
        chapterFlow.wait = ChapterFlow.Wait(key: nextKey, folderID: folderID, token: token,
                                            deadline: ListenTimingLog.now() + limit)
        chapterFlow.fetch = Task { [weak self] in
            let fetched = await library.fetch(nextKey)
            self?.chapterFetched(nextKey, fetched: fetched, token: token, in: folderID)
        }
        scheduleWaitTimeout(after: limit)
    }

    /// The wait for a link chapter gives up `seconds` from now.
    private func scheduleWaitTimeout(after seconds: TimeInterval) {
        guard let wait = chapterFlow.wait else { return }
        chapterFlow.wait?.deadline = ListenTimingLog.now() + seconds
        chapterFlow.fetchTimeout?.cancel()
        chapterFlow.fetchTimeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.chapterFetched(wait.key, fetched: false, token: wait.token, in: wait.folderID)
        }
    }

    /// The app went to the background while a link chapter is fetched: iOS may suspend an app
    /// holding a silent audio session, so the wait ends within the background limit from now.
    func shortenChapterWaitInBackground() {
        guard localTTS.synthQueue.runState.phase == .background, let wait = chapterFlow.wait,
              playback.awaitingPage else { return }
        let limit = chapterFlow.waitLimits.background
        guard wait.deadline - ListenTimingLog.now() > limit else { return }
        scheduleWaitTimeout(after: limit)
    }

    private func chapterFetched(_ nextKey: UUID, fetched: Bool, token: UUID, in folderID: UUID) {
        guard chapterFlow.wait?.token == token, playback.awaitingPage else { return }
        chapterFlow.wait = nil
        chapterFlow.fetch?.cancel()
        chapterFlow.fetchTimeout?.cancel()
        guard fetched else {
            ListenTimingLog.log("chapter_advance", ["to": ListenTimingLog.shortKey(nextKey), "error": "fetch"], console: true)
            ListenDebugLog.shared.append("chapter: \(Self.nextChapterUnavailable)")
            chapterFlow.boundary = nil
            completeArticle(restartBake: false)
            return
        }
        advance(to: nextKey, in: folderID)
    }

    // MARK: - Rendering across the boundary

    /// Once the chapter's rendering has reached two paragraphs before its end, the next chapter
    /// is staged behind it in the render queue (`GlobalSynthQueue.stageNext`), so its opening is
    /// on disk when it starts, in the background too on the ONNX route. Only on the on-device
    /// engine, not for audio held for unfinished library work; once per chapter.
    func stageNextChapterIfDue() {
        guard let key = playback.articleID, let folderID = playback.folderID, let library = nextChapters,
              chapterFlow.stagedAfter != key, case .local = wantedRoute else { return }
        let count = playback.paragraphCount
        let missing = localTTS.audioCache.missingIndices(articleID: key, paragraphCount: count,
                                                         engineID: localTTS.cacheEngineID,
                                                         voiceID: localTTS.normalizedCacheVoice(cacheVoiceID))
        guard !missing.contains(where: { $0 >= playback.playhead && $0 < count - 2 }) else { return }
        chapterFlow.stagedAfter = key
        guard case .ready(let next) = ChapterAdvance.after(key, in: library.chapters(of: folderID)),
              let session = library.load(next) else { return }
        chapterFlow.nextSession = session
        localTTS.stageNextChapter(cacheKey: next, after: key, paragraphs: session.document.paragraphs,
                                  voiceID: cacheVoiceID)
    }

    /// The bound engine became audible: the boundary it closes goes into the timing log (the
    /// device check's pass line: no deactivation, gap under 1 s), and the next chapter may be due
    /// for staging.
    func chapterBecameAudible() {
        stageNextChapterIfDue()
        guard let boundary = chapterFlow.boundary, boundary.to == playback.articleID else { return }
        chapterFlow.boundary = nil
        ListenTimingLog.log("chapter_boundary", [
            "from": ListenTimingLog.shortKey(boundary.from), "to": ListenTimingLog.shortKey(boundary.to),
            "gap_ms": ListenTimingLog.ms(since: boundary.endedAt),
            "deactivated": audioSession.deactivationCount != boundary.deactivations,
            "session_active": audioSession.isActive,
            "lock_screen_cleared": lockScreen.clearCount != boundary.lockScreenClears,
            "next_rendered": boundary.nextWasRendered,
            "engine": activeEngine?.name ?? "—",
            "app_phase": localTTS.synthQueue.runState.phase.rawValue,
        ], console: true)
    }

    private static func describe(_ decision: ChapterAdvance.Decision) -> String {
        switch decision {
        case .play(let key): "play \(ListenTimingLog.shortKey(key))"
        case .waitForFetch(let key): "fetch \(ListenTimingLog.shortKey(key))"
        case .end(let notice): notice.map { "end: \($0)" } ?? "end"
        }
    }
}
