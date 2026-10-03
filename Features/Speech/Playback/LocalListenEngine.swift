import Foundation

/// Listen through the on-device engine: `LocalModelSpeechEngine` (file player + producer) fed by
/// the coordinator's render queue and audio cache. Progress is player time, so the controller
/// polls `estimatedPosition` while playing.
@MainActor
final class LocalListenEngine: ListenEngine {
    var onEvent: ((PlaybackEngineEvent) -> Void)?

    private let coordinator: LocalTTSCoordinator
    private var engine: LocalModelSpeechEngine { coordinator.localEngineInstance }
    /// Cache key of the article playing (SavedArticle.id or the ephemeral reader key).
    private var articleID: UUID?
    private var document: ParagraphDocument = .empty
    private var appleVoiceID: String?
    /// Paragraph of the unit playing (or the start paragraph until the first unit starts).
    private var paragraph = 0
    private var playGeneration = 0
    private var chunkStartsCache: [String: [Int]] = [:]

    init(coordinator: LocalTTSCoordinator) {
        self.coordinator = coordinator
    }

    var name: String { engine.engineShortName }

    private var cacheVoiceID: String { coordinator.cacheVoiceID(appleVoice: appleVoiceID) }

    func play(_ request: ListenPlayRequest) {
        playGeneration += 1
        let generation = playGeneration
        articleID = request.articleID
        document = request.document
        appleVoiceID = request.appleVoice?.identifier
        let start = document.isEmpty ? 0 : document.index(containingUTF16Offset: request.utf16Offset)
        paragraph = start
        // Scrubbed to a sentence mid-paragraph: start at its synth chunk, offset into the audio.
        let within = request.utf16Offset - document.startUTF16Offset(forParagraph: start)
        let startPoint = within > 0 ? chunkLocation(paragraph: start, offset: within) : (chunk: 0, fraction: 0)
        let queue = coordinator.synthQueue
        ListenTimingLog.log("play", [
            "key": ListenTimingLog.shortKey(articleID), "p": start, "paused": request.startPaused,
            "baked": articleID.flatMap { id in
                coordinator.audioCache.audioURL(articleID: id, paragraphIndex: start,
                                                engineID: coordinator.cacheEngineID, voiceID: cacheVoiceID)
            } != nil,
            "worker_busy": queue.activeBakeCacheKey != nil,
            "worker_key": ListenTimingLog.shortKey(queue.activeBakeCacheKey),
            "worker_p": queue.activeBakeIndex ?? -1,
        ])
        if let articleID {
            // Reshuffle the global queue: this article #1, cursor at the playhead.
            coordinator.prioritizeListen(
                cacheKey: articleID,
                playhead: start,
                paragraphs: document.paragraphs,
                voiceID: cacheVoiceID,
                isEphemeral: coordinator.audioCache.loadMeta(for: articleID)?.kind == .ephemeral
            )
        }
        wire()
        Task { @MainActor in
            guard generation == self.playGeneration else { return }
            do {
                try await self.engine.speak(paragraphs: self.document.paragraphs, startingAt: start,
                                            chunk: startPoint.chunk, fractionInChunk: startPoint.fraction,
                                            voiceID: self.appleVoiceID)
                guard generation == self.playGeneration else { return }
                if request.startPaused {
                    self.engine.pause()
                    self.onEvent?(.becamePaused)
                }
            } catch {
                guard generation == self.playGeneration else { return }
                // The host failed to load: the coordinator marks the engine failed, and the
                // controller's engine-change handling re-speaks this spot with Apple.
                self.coordinator.noteSpeakFailed(error)
            }
        }
    }

    func pause() { engine.pause() }

    func resume() {
        if engine.isPaused { engine.resume() }
    }

    func stop() {
        playGeneration += 1
        engine.stop()
    }

    /// A time-stretch on the player, applied in place: the sentence keeps going at the new speed.
    func setRate(_ multiplier: Double) { engine.setPlaybackRate(Float(multiplier)) }

    /// Save landed on a different key than the reader's: keep playing under the new one.
    func rekey(to id: UUID) {
        articleID = id
        engine.articleID = id
    }

    var snapshot: PlaybackEngineSnapshot {
        PlaybackEngineSnapshot(isAudible: engine.isAudible || engine.isSpeaking, isPaused: engine.isPaused)
    }

    var isWaitingForAudio: Bool {
        guard !engine.isPaused, !engine.isAudible else { return false }
        let count = document.count
        let hasMoreUnits = paragraph + 1 < count || engine.debugNextProduceIndex < count || engine.debugAwaitingMore
        guard hasMoreUnits else { return false }
        return engine.debugAwaitingMore || engine.debugProducerActive || engine.debugBufferedCount == 0
    }

    var sourceNote: String? {
        engine.currentAppleFallbackReason?.localizedNote(engine: engine.engineShortName)
    }

    var needsPlaybackPolling: Bool { true }

    /// The spot inside the playing (or just paused) paragraph from the player's time: chunk
    /// boundaries plus time into the chunk, proportional by characters.
    func estimatedPosition() -> (paragraph: Int, utf16Offset: Int)? {
        guard let pos = engine.currentPlaybackPosition else { return nil }
        let p = pos.item.paragraphIndex
        guard document.paragraphs.indices.contains(p) else { return nil }
        let length = document.paragraphs[p].utf16.count
        let starts = chunkStarts(paragraph: p)
        let fractionOfFile = pos.duration > 0 ? min(1, pos.time / pos.duration) : 0
        let within: Int
        switch pos.item.source {
        case .appleFallback(let fromChunk, _):
            // The rest of the paragraph from `fromChunk` as one Apple file: proportional by characters.
            let from = starts[min(fromChunk, starts.count - 1)]
            within = from + Int(Double(length - from) * fractionOfFile)
        case .baked, .stitched:
            // The stitched paragraph CAF: locate the chunk from its recorded durations.
            let loc = ChunkOffsets.locate(time: pos.time, fileDuration: pos.duration,
                                          durations: pos.item.chunkDurations, chunkCount: starts.count)
            within = loc.chunk < 0
                ? Int(Double(length) * loc.fraction)
                : ChunkOffsets.offset(chunk: loc.chunk, fraction: loc.fraction, starts: starts, length: length)
        case .chunk(let k):
            within = ChunkOffsets.offset(chunk: k, fraction: fractionOfFile, starts: starts, length: length)
        }
        return (p, document.startUTF16Offset(forParagraph: p) + max(0, min(within, max(0, length - 1))))
    }

    /// Apple units queued only because the engine couldn't render in the background are dropped
    /// and re-rendered; the queue cursor moves to the restart paragraph first.
    func appDidBecomeActive() {
        if let from = engine.reclaimBackgroundFallbacks(), let articleID {
            coordinator.synthQueue.focusPlayhead(cacheKey: articleID, paragraph: from)
        }
    }

    var debug: ListenEngineDebug {
        ListenEngineDebug(
            isSpeaking: engine.isSpeaking, isPaused: engine.isPaused,
            bufferedCount: engine.debugBufferedCount, awaitingMore: engine.debugAwaitingMore,
            producerActive: engine.debugProducerActive, epoch: engine.debugEpoch,
            currentCAF: engine.debugCurrentCAF, secondsSinceEnqueue: engine.debugSecondsSinceEnqueue,
            lastHandoffGapMs: engine.debugLastHandoffGapMs, lastHandoffWasPrimed: engine.debugLastHandoffWasPrimed,
            starveEventCount: engine.debugStarveEventCount, renderMode: renderMode, readyAhead: readyAhead)
    }

    /// How audio is produced right now (route, app phase).
    private var renderMode: String {
        let phase = coordinator.synthQueue.runState.phase
        let name = engine.engineShortName
        let pace = RenderPace.shared.snapshot.speed.map { String(format: " · %.1f× real time", $0) } ?? ""
        if engine.hostRendersInBackground {
            switch phase {
            case .active, .inactive:
                return "\(phase.rawValue) · \(name) ONNX CPU (\(engine.hostRoutingLabel ?? "cpu"))\(pace)"
            case .background:
                return "background · \(name) ONNX CPU keeps rendering (playing article)\(pace)"
            }
        }
        switch phase {
        case .active: return "foreground · \(name) Core ML (\(engine.hostRoutingLabel ?? "default"))"
        case .inactive: return "inactive · \(name) for playhead only, bake-ahead held"
        case .background: return "background · no Core ML — baked audio + Apple fallback"
        }
    }

    /// Consecutive paragraphs after the playing one already rendered in the current voice.
    private var readyAhead: Int {
        guard let articleID else { return 0 }
        var n = 0
        var i = paragraph + 1
        while i < document.count,
              coordinator.audioCache.audioURL(articleID: articleID, paragraphIndex: i,
                                              engineID: coordinator.cacheEngineID, voiceID: cacheVoiceID) != nil {
            n += 1
            i += 1
        }
        return n
    }

    // MARK: - Chunk positions

    /// Where each synth chunk of paragraph `paragraph` starts (paragraph UTF-16 offsets).
    private func chunkStarts(paragraph: Int) -> [Int] {
        let paragraphs = document.paragraphs
        guard paragraphs.indices.contains(paragraph) else { return [0] }
        let text = paragraphs[paragraph]
        if let cached = chunkStartsCache[text] { return cached }
        let starts = ChunkOffsets.starts(paragraph: text, chunks: coordinator.synthQueue.chunkTexts(for: text))
        if chunkStartsCache.count > 64 { chunkStartsCache.removeAll() }
        chunkStartsCache[text] = starts
        return starts
    }

    /// Synth chunk + fraction for paragraph offset `offset`.
    private func chunkLocation(paragraph: Int, offset: Int) -> (chunk: Int, fraction: Double) {
        let length = document.paragraphs.indices.contains(paragraph) ? document.paragraphs[paragraph].utf16.count : 0
        return ChunkOffsets.locate(offset: offset, starts: chunkStarts(paragraph: paragraph), length: length)
    }

    // MARK: - Wiring

    /// Point the engine at this article's audio: the bake cache, the render queue, and the
    /// session callbacks. Every provider reads `articleID` / `document` when called.
    private func wire() {
        let engine = self.engine
        engine.onParagraphIndexChange = { [weak self] idx in
            guard let self else { return }
            self.paragraph = idx
            // A unit of `idx` started: the controller places the offset (its start, or the
            // scrubbed sentence when playback began mid-paragraph).
            self.onEvent?(.playheadAdvanced(paragraph: idx, utf16Offset: nil))
        }
        engine.onFinished = { [weak self] in self?.onEvent?(.finished) }
        engine.articleID = articleID
        engine.bakedURLProvider = { [weak self] idx in
            guard let self, let articleID = self.articleID else { return nil }
            // Current voice's CAF, else the previous voice's until this paragraph is re-rendered.
            return self.coordinator.audioCache.playableAudioURL(
                articleID: articleID, paragraphIndex: idx,
                engineID: self.coordinator.cacheEngineID, voiceID: self.cacheVoiceID)
        }
        engine.chunkCountProvider = { [weak self] text in
            self?.coordinator.synthQueue.chunkTexts(for: text).count ?? TextChunker.chunks(for: text).count
        }
        engine.chunkEnsureProvider = { [weak self] index, chunk, text in
            guard let self, let articleID = self.articleID else {
                throw LocalSynthError.engineUnavailable("No article bound to the local engine.")
            }
            return try await self.coordinator.synthQueue.ensureChunk(
                cacheKey: articleID, paragraphIndex: index, chunk: chunk, text: text,
                paragraphs: self.document.paragraphs, voiceID: self.cacheVoiceID,
                isEphemeral: self.coordinator.audioCache.loadMeta(for: articleID)?.kind == .ephemeral)
        }
        engine.chunkTextsProvider = { [weak self] text in
            self?.coordinator.synthQueue.chunkTexts(for: text) ?? []
        }
        engine.chunkDurationsProvider = { [weak self] index in
            guard let self, let articleID = self.articleID else { return nil }
            return self.coordinator.audioCache.entry(articleID: articleID, paragraphIndex: index)?.chunkDurations
        }
        engine.chunkReadyProvider = { [weak self] index, chunk, text in
            guard let self, let articleID = self.articleID else { return false }
            return self.coordinator.synthQueue.isChunkReady(
                cacheKey: articleID, paragraphIndex: index, chunk: chunk, text: text, voiceID: self.cacheVoiceID)
        }
        engine.workerBusyElsewhere = { [weak self] index in
            guard let self, let articleID = self.articleID else { return false }
            let queue = self.coordinator.synthQueue
            guard let active = queue.activeBakeCacheKey else { return false }
            return active != articleID || queue.activeBakeIndex != index
        }
        engine.isRenderingParagraph = { [weak self] index in
            guard let self, let articleID = self.articleID else { return false }
            let queue = self.coordinator.synthQueue
            return queue.activeBakeCacheKey == articleID && queue.activeBakeIndex == index
        }
    }
}
