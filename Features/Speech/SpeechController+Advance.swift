import Foundation

/// What the controller keeps between pages of a folder: the next one staged to render, and the
/// boundary the timing log measures.
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

    var boundary: Boundary?
    /// The chapter whose successor has been staged (once per chapter).
    var stagedAfter: UUID?
    /// The successor's session, loaded when it was staged.
    var nextSession: SpeechSession?
}

/// Playback through a folder (a book, a followed story, or any folder, decision D15): when a page
/// ends, the next playable one starts in place, without deactivating the audio session, clearing
/// the session or the lock screen; when there is none, or the next is a chapter still waiting for
/// its text, playback stops as for any page. The rule is `ChapterAdvance`; the library is reached
/// through `nextChapters`. See docs/LISTEN_PLAYBACK.md, "Books, series and folders".
extension SpeechController {
    /// The bound engine played the page to its end (or there was nothing left to speak). The
    /// controller decides before the session sees `finished`: a chapter with a next one carries
    /// on; anything else finishes, its page staying bound.
    func pageEnded(restartBake: Bool) {
        guard let key = playback.articleID, let folderID = playback.folderID, let library = nextChapters else {
            completeArticle(restartBake: restartBake)
            return
        }
        let next = ChapterAdvance.after(key, in: library.chapters(of: folderID))
        ListenTimingLog.log("chapter_advance", [
            "from": ListenTimingLog.shortKey(key), "next": Self.describe(next),
            "app_phase": localTTS.synthQueue.runState.phase.rawValue,
        ], console: true)
        guard case .ready(let nextKey) = next else {
            if case .waiting = next { ListenDebugLog.shared.append("chapter: the next one is still waiting for its text") }
            completeArticle(restartBake: restartBake)
            return
        }
        beginBoundary(from: key)
        library.pageFinished(key: key, text: playback.textFingerprint)
        advance(to: nextKey, in: folderID)
    }

    /// Contents → a chapter: it plays from its start, replacing what plays, and the book or
    /// series carries on from it.
    func playPage(_ key: UUID) {
        guard let session = nextChapters?.load(key) else { return }
        start(session)
    }

    /// Nothing carries on from the bound page any more (another page binds, Stop Listening): the
    /// staged chapter is unstaged.
    func endChapterFlow() {
        chapterFlow = ChapterFlow()
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
    /// changes its title. Paused, it is bound at its start without sounding.
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
        let commands = advancePlayback(to: session.id, document: session.document,
                                       folderID: session.folderID ?? folderID)
        guard commands.contains(.enginePlay) else {
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
              !localTTS.activeRouteRendersInBackground,
              let missing = localTTS.missingParagraphs(of: session.id, paragraphs: session.document.paragraphs)
        else { return false }
        return !missing.isEmpty
    }

    private func isRendered(_ key: UUID, paragraph: Int, of count: Int) -> Bool {
        guard count > paragraph, let target = localTTS.renderTarget else { return false }
        return localTTS.audioCache.readyIndices(articleID: key, paragraphCount: count, engineID: target.engineID,
                                                voiceID: target.cacheVoice).contains(paragraph)
    }

    // MARK: - Rendering across the boundary

    /// Once the chapter's rendering has reached two paragraphs before its end, the next chapter
    /// is staged behind it in the render queue (`GlobalSynthQueue.stageNext`), so its opening is
    /// on disk when it starts, in the background too on the ONNX route. Only on the on-device
    /// engine, not for audio held for unfinished library work; once per chapter.
    func stageNextChapterIfDue() {
        guard let key = playback.articleID, let folderID = playback.folderID, let library = nextChapters,
              chapterFlow.stagedAfter != key, case .local = wantedRoute,
              let missing = localTTS.missingParagraphs(of: key, paragraphs: playback.document.paragraphs) else { return }
        let count = playback.paragraphCount
        guard !missing.contains(where: { $0 >= playback.playhead && $0 < count - 2 }) else { return }
        chapterFlow.stagedAfter = key
        guard case .ready(let next) = ChapterAdvance.after(key, in: library.chapters(of: folderID)),
              let session = library.load(next) else { return }
        chapterFlow.nextSession = session
        localTTS.stageNextChapter(cacheKey: next, after: key, paragraphs: session.document.paragraphs)
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

    private static func describe(_ next: ChapterAdvance.Next) -> String {
        switch next {
        case .ready(let key): "play \(ListenTimingLog.shortKey(key))"
        case .waiting(let key): "end: \(ListenTimingLog.shortKey(key)) waits for its text"
        case .none: "end"
        }
    }
}
