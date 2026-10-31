import Foundation

/// Listen through the on-device engine: a `LocalListenPlayer` fed, per play, by a
/// `QueueUnitSource` over the coordinator's render queue and audio cache. `SpeechController`
/// sends it every command; it reports what happened through `onEvent` (audible, paused, the spot
/// being spoken, stalled, finished) and never changes the session itself. Player time has no
/// callbacks, so while audio is wanted and the app is on screen the engine samples it 5×/s
/// (`clock`) and reports the spot being spoken and listen-bar status changes itself. In the
/// background (the phone locked) nothing is on screen and the clock stops; the player's own
/// events (a unit starting, the player running dry) report the paragraph and hold the app alive
/// while it waits for audio.
@MainActor
final class LocalListenEngine {
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
    /// Playing or about to (not paused, not stopped): the clock runs while the app is in front.
    private var audioWanted = false
    private var clock: Task<Void, Never>?
    private var lastStatus: Status?
    private var runStateObserver: NSObjectProtocol?
    #if canImport(UIKit)
    /// Keeps the app alive while the player waits for audio in the background (a chunk the ONNX
    /// route is rendering): with nothing audible iOS may suspend the app.
    private lazy var gapGrace = BackgroundGrace(name: "ReaderListenGap")
    #endif

    private struct Status: Equatable {
        var waiting: Bool
        var waitingForVoice: Bool
        var snapshot: PlaybackEngineSnapshot
    }

    init(coordinator: LocalTTSCoordinator) {
        self.coordinator = coordinator
        let player = LocalListenPlayer(runState: coordinator.synthQueue.runState)
        self.player = player
        coordinator.listenPlayer = player
        player.onUnitStarted = { [weak self] idx in
            guard let self else { return }
            self.paragraph = idx
            self.reportPosition(force: true)
            self.onEvent?(.becameAudible)
            self.updateGapGrace()
            // In the background the render queue idles between bursts; playing on may wake it.
            self.coordinator.synthQueue.playbackAdvanced()
        }
        player.onStarved = { [weak self] in self?.updateGapGrace() }
        player.rendersPausedForRetry = { [weak coordinator] in coordinator?.isPausedForRetry ?? false }
        player.onStalled = { [weak self] stall in self?.stall(stall) }
        player.onFinished = { [weak self] in
            self?.stopClock()
            self?.onEvent?(.finished)
        }
        runStateObserver = NotificationCenter.default.addObserver(
            forName: AppRunState.didChange, object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, note.object as AnyObject? === self.runState else { return }
                self.appPhaseChanged()
            }
        }
    }

    deinit {
        if let runStateObserver { NotificationCenter.default.removeObserver(runStateObserver) }
    }

    private var runState: AppRunState { coordinator.synthQueue.runState }

    /// Diagnostics / timing-log name ("Kokoro").
    var name: String { coordinator.synth.engineShortName }

    /// Start at `request.utf16Offset`. Paused: take the spot without sounding; `resume` or a new
    /// `play` sounds it.
    func play(_ request: ListenPlayRequest) {
        document = request.document
        let source = QueueUnitSource(coordinator: coordinator, articleID: request.articleID,
                                     paragraphs: document.paragraphs, selection: request.selection)
        self.source = source
        let queue = coordinator.synthQueue
        let engineID = source.selection.engine.rawValue
        mapper = ListenPositionMapper(document: document) { queue.chunkTexts(for: $0, engineID: engineID) }
        // Scrubbed to a sentence mid-paragraph: start at its synth chunk, offset into the audio.
        let start = mapper.startPoint(utf16: request.utf16Offset)
        paragraph = start.paragraph
        playStart = (start.paragraph, request.utf16Offset)
        reported = nil
        lastStatus = nil
        ListenTimingLog.log("play", [
            "key": ListenTimingLog.shortKey(request.articleID), "p": start.paragraph, "paused": request.startPaused,
            "baked": source.isRenderedInThisVoice(paragraph: start.paragraph),
            "worker_busy": queue.activeBakeCacheKey != nil,
            "worker_key": ListenTimingLog.shortKey(queue.activeBakeCacheKey),
            "worker_p": queue.activeBakeIndex ?? -1,
        ])
        // Reshuffle the global queue: this article #1, cursor at the playhead.
        coordinator.openArticle(
            cacheKey: request.articleID,
            paragraphs: document.paragraphs,
            from: start.paragraph,
            isEphemeral: coordinator.audioCache.isEphemeral(request.articleID)
        )
        if !request.startPaused { startClock() }
        player.play(source, from: start.paragraph, chunk: start.chunk, fractionInChunk: start.fraction)
        // The producer hasn't run yet: pausing now holds the first unit unstarted.
        if request.startPaused { pause() }
    }

    /// Playback reached audio the engine can't give now: it pauses there, and the controller says
    /// why (`PlaybackEngineEvent.stalled`).
    private func stall(_ stall: ListenStall) {
        pause()
        onEvent?(.stalled(stall))
    }

    /// Confirmed with `becamePaused` once the audio holds.
    func pause() {
        player.pause()
        stopClock()
        reportPosition(force: false)
        onEvent?(.becamePaused)
    }

    /// Continue what `pause` held (no-op when nothing is held).
    func resume() {
        guard player.state == .paused else { return }
        player.resume()
        startClock()
        if player.isAudible { onEvent?(.becameAudible) }
        coordinator.synthQueue.playbackAdvanced()
    }

    func stop() {
        source = nil
        stopClock()
        player.stop()
    }

    /// A time-stretch on the player, applied in place: the sentence keeps going at the new speed.
    func setRate(_ multiplier: Double) { player.setPlaybackRate(Float(multiplier)) }

    /// Save landed on a different key than the reader's: keep playing under the new one.
    func rekey(to id: UUID) { source?.rekey(to: id) }

    var snapshot: PlaybackEngineSnapshot {
        PlaybackEngineSnapshot(isAudible: player.isAudible || player.state == .playing, isPaused: player.state == .paused)
    }

    var isWaitingForAudio: Bool {
        guard player.state != .paused, !player.isAudible else { return false }
        let count = document.count
        let hasMoreUnits = paragraph + 1 < count || player.nextParagraphToProduce < count || player.awaitingMore
        guard hasMoreUnits else { return false }
        return player.awaitingMore || player.isProducing || player.bufferedUnitCount == 0
    }

    /// Playing (not held), and the first audio waits for the model to load: nothing at the start
    /// is rendered (`LocalListenPlayer.isWaitingForVoice`).
    var isWaitingForVoice: Bool { player.isWaitingForVoice }

    /// iOS restarted its media services: stop, and build new audio objects for the next `play`
    /// (the old ones are dead and fail silently). Each unit gets its own `AVAudioPlayer`, so
    /// stopping drops every dead one. The render queue drops the engine's host too (after the
    /// call in flight); the next work loads a fresh one.
    func mediaServicesWereReset() {
        stop()
        if let engine = coordinator.residentEngineID { coordinator.synthQueue.dropHost(engineID: engine) }
    }

    var debug: ListenEngineDebug {
        ListenEngineDebug(
            isSpeaking: player.state == .playing, isPaused: player.state == .paused,
            bufferedCount: player.bufferedUnitCount, awaitingMore: player.awaitingMore,
            producerActive: player.isProducing, epoch: player.debugEpoch,
            currentCAF: player.debugCurrentCAF, secondsSinceEnqueue: player.debugSecondsSinceEnqueue,
            lastHandoffGapMs: player.debugLastHandoffGapMs, lastHandoffWasPrimed: player.debugLastHandoffWasPrimed,
            starveEventCount: player.debugStarveEventCount, renderMode: renderMode,
            renderedParagraphsAhead: renderedParagraphsAhead)
    }

    /// How audio is produced right now: the app phase, then the engine and its host's routing.
    private var renderMode: String {
        let phase = coordinator.synthQueue.runState.phase
        let synth = coordinator.synth
        let route = "\(name) (\(synth.hostRoutingLabel ?? "default"))"
        let pace = RenderPace.shared.snapshot.speed.map { String(format: ", %.1f× real time", $0) } ?? ""
        switch (phase, synth.rendersInBackground) {
        case (.active, _), (.inactive, true): return "\(phase.rawValue), \(route)\(pace)"
        case (.inactive, false): return "inactive, \(name) for playhead only, bake-ahead held"
        case (.background, true): return "background, \(route), playing article in bursts\(pace)"
        case (.background, false): return "background, no model calls: rendered audio, then a pause"
        }
    }

    /// Consecutive paragraphs after the playing one already rendered in the current voice.
    private var renderedParagraphsAhead: Int {
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

    /// The clock samples player time 5×/s while audio is wanted and the app is in front (active
    /// or inactive: the screen shows it): it reports the spot being spoken and listen-bar status
    /// changes. In the background nothing on screen needs either, so it doesn't run (polling
    /// there would wake a locked phone 5×/s, ~18,000 times an hour of listening); the player's
    /// events keep the paragraph and the gap grace current. Back in front it restarts and its
    /// first tick catches up.
    private func startClock() {
        audioWanted = true
        updateClock()
        updateGapGrace()
    }

    private func stopClock() {
        audioWanted = false
        updateClock()
        updateGapGrace()
    }

    private func appPhaseChanged() {
        updateClock()
        updateGapGrace()
    }

    private func updateClock() {
        guard audioWanted, runState.phase != .background else {
            clock?.cancel()
            clock = nil
            return
        }
        guard clock == nil else { return }
        clock = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.tick()
                try? await Task.sleep(for: .milliseconds(200), tolerance: .milliseconds(50))
            }
        }
    }

    private func tick() {
        reportPosition(force: false)
        let status = Status(waiting: isWaitingForAudio, waitingForVoice: isWaitingForVoice, snapshot: snapshot)
        if status != lastStatus {
            lastStatus = status
            onEvent?(.statusChanged)
        }
    }

    /// In the background, keep the app alive while the player waits for audio (with nothing
    /// audible iOS may suspend it). Asked on the events that change it: a play or resume, a unit
    /// starting, the player running dry, pause, stop, the end, and a phase change.
    private func updateGapGrace() {
        #if canImport(UIKit)
        if audioWanted, runState.phase == .background, isWaitingForAudio { gapGrace.begin() } else { gapGrace.end() }
        #endif
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
