import Foundation

/// Listen through the on-device engine: a `LocalListenPlayer` fed, per play, by a
/// `QueueUnitSource` over the coordinator's render queue and audio cache. Player time has no
/// callbacks, so while audio is wanted the engine samples it 5×/s (`clock`) and reports the spot
/// being spoken and listen-bar status changes itself.
@MainActor
final class LocalListenEngine: ListenEngine {
    var onEvent: ((PlaybackEngineEvent) -> Void)?

    private let coordinator: LocalTTSCoordinator
    let player: LocalListenPlayer
    /// The current play's audio (nil: stopped).
    private var source: QueueUnitSource?
    private var document: ParagraphDocument = .empty
    private var mapper = ListenPositionMapper(document: .empty) { _ in [] }
    /// Paragraph of the unit playing (or the start paragraph until the first unit starts).
    private var paragraph = 0
    /// Where the current play began: positions in that paragraph never report earlier (a
    /// sub-paragraph start begins a hair early in the audio, see `LocalListenPlayer.subChunkLeadIn`).
    private var playStart = (paragraph: 0, utf16: 0)
    private var reported: (paragraph: Int, utf16: Int)?
    private var playGeneration = 0
    /// A paused play, or Pause while the model loads: hold the audio once the play starts.
    private var holdsAtStart = false
    private var clock: Task<Void, Never>?
    private var lastStatus: Status?
    #if canImport(UIKit)
    /// Keeps the app alive while the player waits for audio in the background (e.g. an Apple
    /// fallback paragraph rendering): with nothing audible iOS may suspend the app.
    private lazy var gapGrace = BackgroundGrace(name: "ReaderListenGap")
    #endif

    private struct Status: Equatable {
        var waiting: Bool
        var note: String?
        var snapshot: PlaybackEngineSnapshot
    }

    init(coordinator: LocalTTSCoordinator) {
        self.coordinator = coordinator
        let player = LocalListenPlayer()
        self.player = player
        coordinator.listenPlayer = player
        player.onUnitStarted = { [weak self] idx in
            guard let self else { return }
            self.paragraph = idx
            self.reportPosition(force: true)
            self.onEvent?(.becameAudible)
            // In the background the render queue idles between bursts; playing on may wake it.
            self.coordinator.synthQueue.playbackAdvanced()
        }
        player.onFinished = { [weak self] in
            self?.stopClock()
            self?.onEvent?(.finished)
        }
    }

    var name: String { coordinator.synth.engineShortName }

    func play(_ request: ListenPlayRequest) {
        playGeneration += 1
        let generation = playGeneration
        document = request.document
        let source = QueueUnitSource(coordinator: coordinator, articleID: request.articleID,
                                     paragraphs: document.paragraphs, appleVoiceID: request.appleVoice?.identifier)
        self.source = source
        let queue = coordinator.synthQueue
        mapper = ListenPositionMapper(document: document) { queue.chunkTexts(for: $0) }
        // Scrubbed to a sentence mid-paragraph: start at its synth chunk, offset into the audio.
        let start = mapper.startPoint(utf16: request.utf16Offset)
        paragraph = start.paragraph
        playStart = (start.paragraph, request.utf16Offset)
        reported = nil
        lastStatus = nil
        holdsAtStart = request.startPaused
        ListenTimingLog.log("play", [
            "key": ListenTimingLog.shortKey(request.articleID), "p": start.paragraph, "paused": request.startPaused,
            "baked": source.isRenderedInThisVoice(paragraph: start.paragraph),
            "worker_busy": queue.activeBakeCacheKey != nil,
            "worker_key": ListenTimingLog.shortKey(queue.activeBakeCacheKey),
            "worker_p": queue.activeBakeIndex ?? -1,
        ])
        // Reshuffle the global queue: this article #1, cursor at the playhead.
        coordinator.prioritizeListen(
            cacheKey: request.articleID,
            playhead: start.paragraph,
            paragraphs: document.paragraphs,
            voiceID: coordinator.cacheVoiceID(appleVoice: request.appleVoice?.identifier),
            isEphemeral: coordinator.audioCache.loadMeta(for: request.articleID)?.kind == .ephemeral
        )
        if !request.startPaused { startClock() }
        Task { @MainActor in
            guard generation == self.playGeneration else { return }
            do {
                try await self.player.play(source, from: start.paragraph, chunk: start.chunk,
                                           fractionInChunk: start.fraction)
                guard generation == self.playGeneration else { return }
                // The producer hasn't run yet: pausing now holds the first unit unstarted.
                if self.holdsAtStart { self.pause() }
            } catch {
                guard generation == self.playGeneration else { return }
                // The host failed to load: the engine is marked failed, and the controller's
                // engine-change handling re-speaks this spot with Apple.
                self.coordinator.synth.noteSpeakFailed(error)
            }
        }
    }

    func pause() {
        holdsAtStart = true
        player.pause()
        stopClock()
        reportPosition(force: false)
        onEvent?(.becamePaused)
    }

    func resume() {
        holdsAtStart = false
        guard player.isPaused else { return }
        player.resume()
        startClock()
        if player.isAudible { onEvent?(.becameAudible) }
        coordinator.synthQueue.playbackAdvanced()
    }

    func stop() {
        playGeneration += 1
        source = nil
        holdsAtStart = false
        stopClock()
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
        let hasMoreUnits = paragraph + 1 < count || player.nextParagraphToProduce < count || player.awaitingMore
        guard hasMoreUnits else { return false }
        return player.awaitingMore || player.isProducing || player.bufferedUnitCount == 0
    }

    var sourceNote: String? {
        player.currentAppleFallbackReason?.localizedNote(engine: name)
    }

    /// Apple units queued only because the engine couldn't render in the background are dropped
    /// and re-rendered; the queue cursor moves to the restart paragraph first.
    func appDidBecomeActive() { player.reclaimBackgroundFallbacks() }

    var debug: ListenEngineDebug {
        ListenEngineDebug(
            isSpeaking: player.isSpeaking, isPaused: player.isPaused,
            bufferedCount: player.bufferedUnitCount, awaitingMore: player.awaitingMore,
            producerActive: player.isProducing, epoch: player.debugEpoch,
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
                return "background · \(name) ONNX CPU (\(synth.hostRoutingLabel ?? "cpu")), playing article in bursts\(pace)"
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

    // MARK: - Clock

    /// While audio is wanted: sample player time 5×/s. Foreground: report the spot being spoken
    /// and listen-bar status changes. Background: nothing on screen needs either; only hold the
    /// app alive while the player waits for audio. Back in the foreground the next tick catches up.
    private func startClock() {
        clock?.cancel()
        clock = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.tick()
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    private func stopClock() {
        clock?.cancel()
        clock = nil
        #if canImport(UIKit)
        gapGrace.end()
        #endif
    }

    private func tick() {
        let background = coordinator.synthQueue.runState.phase == .background
        #if canImport(UIKit)
        if background, isWaitingForAudio { gapGrace.begin() } else { gapGrace.end() }
        #endif
        guard !background else { return }
        reportPosition(force: false)
        let status = Status(waiting: isWaitingForAudio, note: sourceNote, snapshot: snapshot)
        if status != lastStatus {
            lastStatus = status
            onEvent?(.statusChanged)
        }
    }

    /// Report the spot the player is at: always when `force` (a unit started), else once it
    /// moved a few characters.
    private func reportPosition(force: Bool) {
        guard let unit = player.currentPlaybackPosition,
              var spot = mapper.position(of: unit.item, time: unit.time, duration: unit.duration) else { return }
        if spot.paragraph == playStart.paragraph { spot.utf16 = max(spot.utf16, playStart.utf16) }
        if !force, let reported, reported.paragraph == spot.paragraph, abs(reported.utf16 - spot.utf16) < 4 { return }
        reported = spot
        onEvent?(.position(paragraph: spot.paragraph, utf16: spot.utf16))
    }
}
