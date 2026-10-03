import Foundation

/// Listen diagnostics: the debug panel / bake overlay snapshot and its labels.
extension SpeechController {
    /// Consecutive paragraphs after the playhead already rendered in the current voice.
    func readyAheadCount() -> Int {
        guard let id = playback.articleID, usesLocalPlayback else { return 0 }
        var n = 0
        var i = playback.playhead + 1
        while i < playback.paragraphCount,
              localTTS.audioCache.audioURL(articleID: id, paragraphIndex: i,
                                           engineID: localTTS.cacheEngineID, voiceID: cacheVoiceID) != nil {
            n += 1
            i += 1
        }
        return n
    }

    /// Debug: how audio is being produced right now (foreground GPU / background / Apple).
    var renderModeLabel: String {
        let phase = localTTS.synthQueue.runState.phase
        guard usesLocalPlayback else { return "Apple TTS (AVSpeechSynthesizer) · \(phase.rawValue)" }
        let eng = localTTS.localEngineInstance
        let pace = RenderPace.shared.snapshot.speed.map { String(format: " · %.1f× real time", $0) } ?? ""
        if eng.hostRendersInBackground {
            switch phase {
            case .active, .inactive:
                return "\(phase.rawValue) · \(eng.engineShortName) ONNX CPU (\(eng.hostRoutingLabel ?? "cpu"))\(pace)"
            case .background:
                return "background · \(eng.engineShortName) ONNX CPU keeps rendering (playing article)\(pace)"
            }
        }
        switch phase {
        case .active:
            return "foreground · \(eng.engineShortName) Core ML (\(eng.hostRoutingLabel ?? "default"))"
        case .inactive:
            return "inactive · \(eng.engineShortName) for playhead only, bake-ahead held"
        case .background:
            return "background · no Core ML — baked audio + Apple fallback"
        }
    }

    func listenDebugSnapshot() -> ListenDebugSnapshot {
        let eng = localTTS.localEngineInstance
        let usingLocal = usesLocalPlayback
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
        let ready: Int
        let totalForCache: Int
        if let identityKey {
            let count = (articleID != nil) ? paragraphs.count : (
                // Fall back to cache status expected paragraphs when viewing queue #1 with no session.
                paragraphs.count > 0 ? paragraphs.count : pending + 0
            )
            let expected = max(count, paragraphs.count)
            switch localTTS.bakeStatus(for: identityKey, paragraphCount: max(expected, 1)) {
            case .ready(paragraphCount: let n):
                ready = n
                totalForCache = n
            case .partial(ready: let r, total: let t):
                ready = r
                totalForCache = t
            case .missing:
                ready = 0
                totalForCache = max(paragraphs.count, 0)
            }
        } else {
            ready = 0
            totalForCache = paragraphs.count
        }

        let isEph: Bool = {
            guard let key = identityKey else { return false }
            if let flagged = queue.isEphemeral(cacheKey: key) { return flagged }
            return localTTS.audioCache.loadMeta(for: key)?.kind == .ephemeral
        }()
        let articleIdentity: String = {
            guard let key = identityKey else { return "—" }
            let kind = isEph ? "eph" : "svd"
            return "\(kind):\(key.uuidString.prefix(8))"
        }()
        let queuePrimary: String = {
            guard let key = queue.primaryCacheKey else { return "—" }
            let kind = (queue.isEphemeral(cacheKey: key) == true
                        || localTTS.audioCache.loadMeta(for: key)?.kind == .ephemeral) ? "eph" : "svd"
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
            if isBufferingNext { return "buffering" }
            switch playback.phase {
            case .playing: return "playing"
            case .paused: return "paused"
            case .prepared: return "prepared"
            case .finished: return "finished"
            case .idle: return "idle"
            }
        }()
        let warmingLocal = localTTS.engineState.warmingEngineID != nil
        let snap = engineSnapshot()
        return ListenDebugSnapshot(
            phase: String(describing: playback.phase),
            phaseLabel: phaseLabel,
            engine: usingLocal ? eng.engineShortName : "Apple",
            isAudible: snap.isAudible,
            isSpeaking: usingLocal ? eng.isSpeaking : appleSynthesizerState.isSpeaking,
            isPaused: usingLocal ? eng.isPaused : appleSynthesizerState.isPaused,
            playhead: playback.playhead,
            paragraphCount: paragraphs.count,
            bufferedCount: usingLocal ? eng.debugBufferedCount : 0,
            awaitingMore: usingLocal ? eng.debugAwaitingMore : false,
            producerActive: usingLocal ? eng.debugProducerActive : false,
            epoch: usingLocal ? eng.debugEpoch : 0,
            currentCAF: usingLocal ? eng.debugCurrentCAF : "—",
            secondsSinceEnqueue: usingLocal ? eng.debugSecondsSinceEnqueue : nil,
            lastHandoffGapMs: usingLocal ? eng.debugLastHandoffGapMs : 0,
            lastHandoffWasPrimed: usingLocal ? eng.debugLastHandoffWasPrimed : false,
            starveEventCount: usingLocal ? eng.debugStarveEventCount : 0,
            bakePlan: bakePlan,
            bakePendingJobs: pending,
            bakeReadyCount: ready,
            bakeParagraphCount: totalForCache > 0 ? totalForCache : paragraphs.count,
            articleIdentity: articleIdentity,
            queuePrimary: queuePrimary,
            demotedCount: queue.demotedCount,
            activeBakeUnit: activeBake,
            nextMissingUnit: nextMissing,
            workerBusy: queue.isWorkerRunning,
            warmingLocal: warmingLocal,
            lastBakeEvent: queue.lastBakeEvent,
            language: languageDebugLabel,
            renderMode: renderModeLabel,
            readyAhead: readyAheadCount(),
            background: queue.runState.phase == .background
                ? "now: " + eng.backgroundStats.label
                : lastBackgroundSummary,
            audioSession: "\(audioSession.isActive ? "active" : "inactive") · activations \(audioSession.activationCount)"
        )
    }

    /// Debug overlay line: language code + source → engine.
    var languageDebugLabel: String {
        let r = languageResolution
        let source = r.source == .detected ? "auto" : (r.source == .manual ? "manual" : "auto: undetected")
        let engine = r.unsupportedEngineID != nil ? "Apple (\(languageEngineDescriptor?.languageLimitNote ?? "unsupported"))"
            : localTTS.engines.shortName(r.engineID)
        return "\(r.languageCode) (\(source)) → \(engine)"
    }
}
