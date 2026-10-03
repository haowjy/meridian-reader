import Foundation

/// Listen through the on-device engine: a `LocalListenPlayer` fed, per play, by a
/// `QueueUnitSource` over the coordinator's render queue and audio cache. Progress is player
/// time, so the controller polls `estimatedPosition` while playing.
@MainActor
final class LocalListenEngine: ListenEngine {
    var onEvent: ((PlaybackEngineEvent) -> Void)?

    private let coordinator: LocalTTSCoordinator
    let player: LocalListenPlayer
    /// The current play's audio (nil: stopped).
    private var source: QueueUnitSource?
    private var document: ParagraphDocument = .empty
    /// Paragraph of the unit playing (or the start paragraph until the first unit starts).
    private var paragraph = 0
    private var playGeneration = 0
    private var chunkStartsCache: [String: [Int]] = [:]

    init(coordinator: LocalTTSCoordinator) {
        self.coordinator = coordinator
        let player = LocalListenPlayer()
        self.player = player
        coordinator.listenPlayer = player
        player.onParagraphIndexChange = { [weak self] idx in
            guard let self else { return }
            self.paragraph = idx
            // A unit of `idx` started: the controller places the offset (its start, or the
            // scrubbed sentence when playback began mid-paragraph).
            self.onEvent?(.playheadAdvanced(paragraph: idx, utf16Offset: nil))
        }
        player.onFinished = { [weak self] in self?.onEvent?(.finished) }
    }

    var name: String { coordinator.synth.engineShortName }

    func play(_ request: ListenPlayRequest) {
        playGeneration += 1
        let generation = playGeneration
        document = request.document
        let source = QueueUnitSource(coordinator: coordinator, articleID: request.articleID,
                                     paragraphs: document.paragraphs, appleVoiceID: request.appleVoice?.identifier)
        self.source = source
        let start = document.isEmpty ? 0 : document.index(containingUTF16Offset: request.utf16Offset)
        paragraph = start
        // Scrubbed to a sentence mid-paragraph: start at its synth chunk, offset into the audio.
        let within = request.utf16Offset - document.startUTF16Offset(forParagraph: start)
        let startPoint = within > 0 ? chunkLocation(paragraph: start, offset: within) : (chunk: 0, fraction: 0)
        let queue = coordinator.synthQueue
        ListenTimingLog.log("play", [
            "key": ListenTimingLog.shortKey(request.articleID), "p": start, "paused": request.startPaused,
            "baked": source.isRenderedInThisVoice(paragraph: start),
            "worker_busy": queue.activeBakeCacheKey != nil,
            "worker_key": ListenTimingLog.shortKey(queue.activeBakeCacheKey),
            "worker_p": queue.activeBakeIndex ?? -1,
        ])
        // Reshuffle the global queue: this article #1, cursor at the playhead.
        coordinator.prioritizeListen(
            cacheKey: request.articleID,
            playhead: start,
            paragraphs: document.paragraphs,
            voiceID: coordinator.cacheVoiceID(appleVoice: request.appleVoice?.identifier),
            isEphemeral: coordinator.audioCache.loadMeta(for: request.articleID)?.kind == .ephemeral
        )
        Task { @MainActor in
            guard generation == self.playGeneration else { return }
            do {
                try await self.player.play(source, from: start, chunk: startPoint.chunk,
                                           fractionInChunk: startPoint.fraction)
                guard generation == self.playGeneration else { return }
                if request.startPaused {
                    self.player.pause()
                    self.onEvent?(.becamePaused)
                }
            } catch {
                guard generation == self.playGeneration else { return }
                // The host failed to load: the engine is marked failed, and the controller's
                // engine-change handling re-speaks this spot with Apple.
                self.coordinator.synth.noteSpeakFailed(error)
            }
        }
    }

    func pause() { player.pause() }

    func resume() {
        if player.isPaused { player.resume() }
    }

    func stop() {
        playGeneration += 1
        source = nil
        player.stop()
    }

    /// A time-stretch on the player, applied in place: the sentence keeps going at the new speed.
    func setRate(_ multiplier: Double) { player.setPlaybackRate(Float(multiplier)) }

    /// Save landed on a different key than the reader's: keep playing under the new one.
    func rekey(to id: UUID) { source?.rekey(to: id) }

    var snapshot: PlaybackEngineSnapshot {
        PlaybackEngineSnapshot(isAudible: player.isAudible || player.isSpeaking, isPaused: player.isPaused)
    }

    var isWaitingForAudio: Bool {
        guard !player.isPaused, !player.isAudible else { return false }
        let count = document.count
        let hasMoreUnits = paragraph + 1 < count || player.debugNextProduceIndex < count || player.debugAwaitingMore
        guard hasMoreUnits else { return false }
        return player.debugAwaitingMore || player.debugProducerActive || player.debugBufferedCount == 0
    }

    var sourceNote: String? {
        player.currentAppleFallbackReason?.localizedNote(engine: name)
    }

    var needsPlaybackPolling: Bool { true }

    /// The spot inside the playing (or just paused) paragraph from the player's time: chunk
    /// boundaries plus time into the chunk, proportional by characters.
    func estimatedPosition() -> (paragraph: Int, utf16Offset: Int)? {
        guard let pos = player.currentPlaybackPosition else { return nil }
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
    func appDidBecomeActive() { player.reclaimBackgroundFallbacks() }

    var debug: ListenEngineDebug {
        ListenEngineDebug(
            isSpeaking: player.isSpeaking, isPaused: player.isPaused,
            bufferedCount: player.debugBufferedCount, awaitingMore: player.debugAwaitingMore,
            producerActive: player.debugProducerActive, epoch: player.debugEpoch,
            currentCAF: player.debugCurrentCAF, secondsSinceEnqueue: player.debugSecondsSinceEnqueue,
            lastHandoffGapMs: player.debugLastHandoffGapMs, lastHandoffWasPrimed: player.debugLastHandoffWasPrimed,
            starveEventCount: player.debugStarveEventCount, renderMode: renderMode, readyAhead: readyAhead)
    }

    /// How audio is produced right now (route, app phase).
    private var renderMode: String {
        let phase = coordinator.synthQueue.runState.phase
        let synth = coordinator.synth
        let pace = RenderPace.shared.snapshot.speed.map { String(format: " · %.1f× real time", $0) } ?? ""
        if synth.rendersInBackground {
            switch phase {
            case .active, .inactive:
                return "\(phase.rawValue) · \(name) ONNX CPU (\(synth.hostRoutingLabel ?? "cpu"))\(pace)"
            case .background:
                return "background · \(name) ONNX CPU keeps rendering (playing article)\(pace)"
            }
        }
        switch phase {
        case .active: return "foreground · \(name) Core ML (\(synth.hostRoutingLabel ?? "default"))"
        case .inactive: return "inactive · \(name) for playhead only, bake-ahead held"
        case .background: return "background · no Core ML — baked audio + Apple fallback"
        }
    }

    /// Consecutive paragraphs after the playing one already rendered in the current voice.
    private var readyAhead: Int {
        guard let source else { return 0 }
        var n = 0
        var i = paragraph + 1
        while i < document.count, source.isRenderedInThisVoice(paragraph: i) {
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
}
