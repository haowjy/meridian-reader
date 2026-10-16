import Foundation

/// Listen diagnostics, kept out of the controller: the debug panel / bake overlay snapshot and its
/// labels, and what the last stretch in the background played (`app_phase` timing log).
@MainActor
final class ListenDiagnostics {
    private unowned let speech: SpeechController
    /// What the last stretch in the background played (debug panel).
    private(set) var lastBackgroundSummary = "—"
    private var deferralsAtBackground = 0

    init(speech: SpeechController) {
        self.speech = speech
    }

    private var localTTS: LocalTTSCoordinator { speech.localTTS }
    private var playback: PlaybackSessionState { speech.playback }

    /// The app moved between active / inactive / background: log it, and track what the
    /// background stretch played.
    func appPhaseChanged(_ phase: AppRunState.Phase) {
        let player = speech.localEngine.player
        let deferrals = localTTS.synthQueue.backgroundDeferrals
        var fields: [String: Any] = [
            "phase": phase.rawValue, "listen": String(describing: playback.phase),
            "engine": speech.activeEngine?.name ?? "—", "p": playback.playhead,
        ]
        switch phase {
        case .background:
            player.backgroundStats = .init()
            deferralsAtBackground = deferrals
            fields["rendered_paragraphs_ahead"] = speech.activeEngine?.debug.renderedParagraphsAhead ?? 0
        case .active:
            if player.backgroundStats != .init() || deferrals > deferralsAtBackground {
                lastBackgroundSummary = player.backgroundStats.label + " · deferred \(deferrals - deferralsAtBackground)"
                fields["bg_summary"] = lastBackgroundSummary
            }
        case .inactive:
            break
        }
        ListenTimingLog.log("app_phase", fields)
    }

    func snapshot() -> ListenDebugSnapshot {
        let engine = speech.activeEngine?.debug ?? ListenEngineDebug()
        let articleID = playback.articleID
        let paragraphs = playback.document.paragraphs
        let queue = localTTS.synthQueue
        let bakePlan: String
        let pending: Int
        if let articleID {
            bakePlan = queue.planDescription(for: articleID)
                ?? (queue.primaryCacheKey == articleID ? "primary" : "queued/idle")
            pending = localTTS.bakeTasksCount(for: articleID)
        } else if let primary = queue.primaryCacheKey {
            bakePlan = queue.planDescription(for: primary) ?? "primary"
            pending = localTTS.bakeTasksCount(for: primary)
        } else {
            bakePlan = "—"
            pending = 0
        }
        let identityKey = articleID ?? queue.primaryCacheKey
        // The session's paragraphs; with no session, queue #1's paragraphs still to render.
        let total = paragraphs.isEmpty ? pending : paragraphs.count
        // Rendered in the active engine's voice (the bake marks' count).
        let ready = identityKey.flatMap { key in
            localTTS.activeCacheVoice.map {
                localTTS.audioCache.readyIndices(articleID: key, paragraphCount: total, engineID: localTTS.cacheEngineID,
                                                 voiceID: $0).count
            }
        } ?? 0

        let isEph: Bool = {
            guard let key = identityKey else { return false }
            if let flagged = queue.isEphemeral(cacheKey: key) { return flagged }
            return localTTS.audioCache.isEphemeral(key)
        }()
        let articleIdentity: String = {
            guard let key = identityKey else { return "—" }
            let kind = isEph ? "eph" : "svd"
            return "\(kind):\(key.uuidString.prefix(8))"
        }()
        let queuePrimary: String = {
            guard let key = queue.primaryCacheKey else { return "—" }
            let kind = (queue.isEphemeral(cacheKey: key) == true
                        || localTTS.audioCache.isEphemeral(key)) ? "eph" : "svd"
            return "\(kind):\(key.uuidString.prefix(8))"
        }()
        let activeBake: String = {
            guard let key = queue.activeBakeCacheKey, let idx = queue.activeBakeIndex else { return "—" }
            return "\(key.uuidString.prefix(8)) p\(idx)"
        }()
        let nextMissing: String = {
            if let idx = queue.nextMissingIndex() { return "p\(idx)" }
            return "—"
        }()
        let phaseLabel: String = {
            if speech.isBufferingNext { return "buffering" }
            switch playback.phase {
            case .playing: return "playing"
            case .paused: return "paused"
            case .prepared: return "prepared"
            case .finished: return "finished"
            case .idle: return "idle"
            }
        }()
        let warmingLocal = localTTS.synth.state.warmingEngineID != nil
        let snap = speech.engineSnapshot()
        return ListenDebugSnapshot(
            phase: String(describing: playback.phase),
            phaseLabel: phaseLabel,
            engine: speech.activeEngine?.name ?? "—",
            isAudible: snap.isAudible,
            isSpeaking: engine.isSpeaking,
            isPaused: engine.isPaused,
            playhead: playback.playhead,
            paragraphCount: paragraphs.count,
            bufferedCount: engine.bufferedCount,
            awaitingMore: engine.awaitingMore,
            producerActive: engine.producerActive,
            epoch: engine.epoch,
            currentCAF: engine.currentCAF,
            secondsSinceEnqueue: engine.secondsSinceEnqueue,
            lastHandoffGapMs: engine.lastHandoffGapMs,
            lastHandoffWasPrimed: engine.lastHandoffWasPrimed,
            starveEventCount: engine.starveEventCount,
            bakePlan: bakePlan,
            bakePendingJobs: pending,
            bakeReadyCount: ready,
            bakeParagraphCount: total,
            articleIdentity: articleIdentity,
            queuePrimary: queuePrimary,
            demotedCount: queue.demotedCount,
            activeBakeUnit: activeBake,
            nextMissingUnit: nextMissing,
            workerBusy: queue.isWorkerRunning,
            warmingLocal: warmingLocal,
            lastBakeEvent: queue.lastBakeEvent,
            language: languageLabel,
            renderMode: speech.activeEngine == nil ? "idle · \(queue.runState.phase.rawValue)" : engine.renderMode,
            renderedParagraphsAhead: engine.renderedParagraphsAhead,
            background: queue.runState.phase == .background
                ? "now: " + speech.localEngine.player.backgroundStats.label
                : lastBackgroundSummary,
            audioSession: "\(speech.audioSession.isActive ? "active" : "inactive") · activations \(speech.audioSession.activationCount)"
        )
    }

    /// Debug overlay line: language code + source → engine.
    var languageLabel: String {
        let r = speech.languageResolution
        let source = r.source == .detected ? "auto" : (r.source == .manual ? "manual" : "auto: undetected")
        let engine = r.unsupportedEngineID != nil ? "Apple (\(speech.languageEngineDescriptor?.languageLimitNote ?? "unsupported"))"
            : localTTS.engines.shortName(r.engineID)
        return "\(r.languageCode) (\(source)) → \(engine)"
    }
}
