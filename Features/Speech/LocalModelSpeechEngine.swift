import AVFoundation
import Foundation

/// Local-engine listen adapter (any registered on-device engine): file **player** + background
/// **producer**. The synth backend is a `LocalSynthHost` built by the engine's provider (via
/// `EngineRegistry`) and driven through the shared `LocalChunkRenderer`; only one is alive at a time.
/// Session phase lives in `PlaybackSessionState` — this type only plays Ready URLs
/// and reports callbacks. See docs/LISTEN_PLAYBACK.md.
@MainActor
final class LocalModelSpeechEngine: SpeechSynthesizing, SynthChunkRendering {
    /// Active local backend. Switched by `LocalTTSCoordinator.selectEngine` via `setActiveLocalEngine`.
    private(set) var engineID: SpeechEngineID

    private let engines: EngineRegistry
    private let player = ChunkPlaybackQueue(maxBuffered: 8)
    private var tempDir: URL
    /// Host + shared renderer for the active engine (nil until first use / after unload).
    private var rendererBox: LocalChunkRenderer?
    private var engineVoice: String?
    /// Model download progress (0…1) from the active host, main actor.
    var onModelProgress: ((Double) -> Void)?
    private let probeFallback = ProbePCMRenderer()

    private var paragraphs: [String] = []
    private var rate: Float = AVSpeechUtteranceDefaultSpeechRate
    private var voiceID: String?
    private var language: String = "en-US"

    /// Produce epoch — bump only on stop / new speak / seek. Never on pause/resume.
    private var epoch = 0
    private var nextProduceIndex = 0
    /// Next synth chunk of `nextProduceIndex` to enqueue (play-while-building).
    private var nextProduceChunk = 0
    /// Timing: when the current speak/seek asked for audio (first_audio), and open starve.
    private var speakRequestedAt: CFAbsoluteTime?
    private var starvedAt: CFAbsoluteTime?
    private var producerTask: Task<Void, Never>?
    /// User wants audio moving (false while paused). Independent of produce epoch.
    private var userWantsAudible = false
    /// Generation for starved-watchdog tasks; bumped whenever we leave play/resume paths.
    private var starveWatchGeneration = 0

    private(set) var isSpeaking = false
    private(set) var isPaused = false

    /// Units played while the app was backgrounded (debug: render mode / what Jimmy's test hit).
    struct BackgroundPlayStats: Equatable {
        var bakedParagraphs = 0
        var engineChunks = 0
        var appleFallbacks = 0
        var label: String { "baked \(bakedParagraphs) · chunks \(engineChunks) · Apple \(appleFallbacks)" }
    }
    var backgroundStats = BackgroundPlayStats()
    /// Why the unit now playing is Apple TTS (nil = the engine's own audio).
    private(set) var currentAppleFallbackReason: String?
    private var appleFallbackReasons: [Int: String] = [:]
    /// Apple-TTS units produced this session (engine couldn't render / backgrounded).
    private(set) var appleFallbackCount = 0

    var onParagraphIndexChange: ((Int) -> Void)?
    /// Session-level finished (all units played, producer exhausted).
    var onFinished: (() -> Void)?
    /// Prefer bake cache when present.
    var bakedURLProvider: ((Int) -> URL?)?
    /// Cache key (SavedArticle.id or ephemeral ArticleIdentity key). Always set while listening.
    var articleID: UUID?
    /// When true, GlobalSynthQueue marks TTSCache meta as ephemeral.
    var isEphemeralCache = false
    /// Await Ready CAF via GlobalSynthQueue (single Core ML worker). Preferred over local render.
    var unitEnsureProvider: ((Int, String) async throws -> URL)?
    /// Persist every successfully live-rendered unit into ArticleAudioCache (fallback).
    /// Return the cached URL when persistence succeeds.
    var onUnitRendered: ((Int, URL, TimeInterval) async -> URL?)?
    /// Chunk-level ensure via GlobalSynthQueue: (paragraph, chunk, text) → playable audio.
    var chunkEnsureProvider: ((Int, Int, String) async throws -> GlobalSynthQueue.ChunkResolution)?
    /// Synth chunk count for a paragraph's text (TextChunker plan).
    var chunkCountProvider: ((String) -> Int)?
    /// True while the single worker is rendering (a chunk of) this paragraph for this article —
    /// the starved watchdog must not treat that as a wedged producer.
    var isRenderingParagraph: ((Int) -> Bool)?
    /// Playhead origin for the current priority stretch (speak/seek start).
    private var priorityStart = 0
    /// Chunk durations of a stitched paragraph CAF (nil = single chunk / unknown).
    var chunkDurationsProvider: ((Int) -> [TimeInterval]?)?
    /// Sub-paragraph start (Nav I): how far into the first unit of this speak/seek to begin, as a
    /// fraction of its synth chunk. Consumed by the first enqueue of the start paragraph.
    private var pendingStartFraction: Double = 0
    /// Lead-in before an estimated sentence start (the in-chunk position is a character-based
    /// estimate; starting a hair early beats clipping the first word).
    static let subChunkLeadIn: TimeInterval = 0.25
    /// Synth chunk texts for a paragraph (the queue's cached plan) — underrun projection.
    var chunkTextsProvider: ((String) -> [String])?
    /// Is (paragraph, chunk) playable without waiting for a render?
    var chunkReadyProvider: ((Int, Int, String) -> Bool)?
    /// Is the single worker mid-call on something other than this paragraph?
    var workerBusyElsewhere: ((Int) -> Bool)?
    /// Durable "now playing" point for crash auto-resume (nil in tests that don't want it).
    var resumePointStore: ListenResumePointStore? = .shared
    /// Paragraphs spoken with Apple because rendering fell behind playback (debug / tests).
    private(set) var behindFallbackCount = 0

    /// The render ran behind playback: this paragraph plays with Apple (see `HeadStart`).
    struct RenderFellBehind: LocalizedError {
        var errorDescription: String? { "Kokoro rendering fell behind playback" }
    }

    var engineShortName: String { engines.shortName(engineID) }
    private var limits: TextChunker.Limits { engines.limits(for: engineID) }

    /// Switch backend. Drops (and unloads) the other engine's host so only one model set is
    /// resident. Same engine: just forwards a voice change.
    func setActiveLocalEngine(_ id: SpeechEngineID, voice: String?) {
        guard id.isLocal else { return }
        let voiceChanged = voice != engineVoice
        engineVoice = voice
        if let r = rendererBox, r.engineID == id {
            if voiceChanged, let voice { r.host.setVoice(voice) }
            engineID = id
            return
        }
        if let old = rendererBox {
            rendererBox = nil
            ListenDebugLog.shared.append("unload \(engines.shortName(old.engineID)) host → \(engines.shortName(id))")
            Task { await old.host.unload() }
        }
        engineID = id
    }

    private func currentRenderer() throws -> LocalChunkRenderer {
        if let rendererBox, rendererBox.engineID == engineID { return rendererBox }
        guard let descriptor = engines.descriptor(engineID), descriptor.kind == .onDevice,
              let host = engines.makeHost(for: engineID, voice: engineVoice)
        else {
            throw LocalSynthError.engineUnavailable(
                engines.blockReason(engineID) ?? "\(engines.displayName(engineID)) is not available on this device.")
        }
        host.onProgress = { [weak self] fraction in
            Task { @MainActor in self?.onModelProgress?(fraction) }
        }
        let renderer = LocalChunkRenderer(host: host, descriptor: descriptor)
        rendererBox = renderer
        return renderer
    }

    /// The live renderer if it is already built for `id` (probe reuses it: two loaded
    /// KokoroAneManager instances make stage predictions fail on device).
    func liveRenderer(for id: SpeechEngineID) -> LocalChunkRenderer? {
        guard let rendererBox, rendererBox.engineID == id else { return nil }
        return rendererBox
    }

    /// Routing label of the live host (debug).
    var hostRoutingLabel: String? { rendererBox?.host.routingLabel }

    /// The live host keeps rendering in the background (Kokoro ONNX CPU route).
    var hostRendersInBackground: Bool { rendererBox?.host.rendersInBackground ?? false }

    /// Article whose audio is playing right now (nil when paused / stopped).
    var playingArticleID: UUID? { (isSpeaking && !isPaused) ? articleID : nil }

    init(engines: EngineRegistry) {
        self.engines = engines
        self.engineID = engines.defaultLocalEngineID
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ReaderTTSLive", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.tempDir = dir

        player.onUnitStarted = { [weak self] item in
            let idx = item.paragraphIndex
            if let self, let id = self.articleID { self.resumePointStore?.save(article: id, paragraph: idx) }
            self?.noteUnitStartedForTiming(item)
            self?.noteUnitKind(item)
            self?.onParagraphIndexChange?(idx)
            self?.isSpeaking = true
            self?.isPaused = false
            // Start / keep producing the next units as soon as one begins playing.
            self?.ensureProducerRunning()
        }
        player.onUnitEnded = { [weak self] in
            // Buffer dipped — keep the fill loop alive while more units remain.
            self?.ensureProducerRunning()
        }
        player.onStarved = { [weak self] in
            self?.handleStarved()
        }
        player.onError = { error in
            print("[LocalPlay] unit error (fail-forward): \(error.localizedDescription)")
        }
        player.onFinished = { [weak self] in
            guard let self else { return }
            self.isSpeaking = false
            self.isPaused = false
            self.userWantsAudible = false
            self.onFinished?()
        }
    }

    var isAudible: Bool { player.isAudible }

    // MARK: - Listen debug
    var debugBufferedCount: Int { player.bufferedCount }
    var debugAwaitingMore: Bool { player.awaitingMore }
    var debugProducerActive: Bool { producerTask != nil }
    var debugEpoch: Int { epoch }
    var debugCurrentCAF: String { player.currentFileName ?? "—" }
    var debugSecondsSinceEnqueue: Double? { player.secondsSinceLastEnqueue }
    var debugLastHandoffGapMs: Double { player.lastHandoffGapMs }
    var debugLastHandoffWasPrimed: Bool { player.lastHandoffWasPrimed }
    var debugStarveEventCount: Int { player.starveEventCount }
    var debugNextProduceIndex: Int { nextProduceIndex }




    func prepareIfNeeded() async throws {
        try await currentRenderer().prepare()
    }

    func speak(paragraphs: [String], startingAt index: Int, rate: Float, voiceID: String?) async throws {
        try await speak(paragraphs: paragraphs, startingAt: index, chunk: 0, fractionInChunk: 0, rate: rate, voiceID: voiceID)
    }

    /// Start at synth chunk `chunk` of paragraph `index`, `fractionInChunk` (0…1) into it
    /// (scrubbed to a sentence). Unrendered: that chunk is rendered first.
    func speak(paragraphs: [String], startingAt index: Int, chunk: Int, fractionInChunk: Double,
               rate: Float, voiceID: String?) async throws {
        stopInternal(clearCallbacks: false)
        try await prepareIfNeeded()
        self.paragraphs = paragraphs
        self.rate = rate
        self.voiceID = voiceID
        let start = max(0, min(index, max(paragraphs.count - 1, 0)))
        nextProduceIndex = start
        priorityStart = start
        userWantsAudible = true
        isPaused = false
        isSpeaking = true
        nextProduceChunk = max(0, chunk)
        pendingStartFraction = min(0.99, max(0, fractionInChunk))
        epoch += 1
        let e = epoch
        player.awaitingMore = true
        speakRequestedAt = ListenTimingLog.now()
        starvedAt = nil
        ListenDebugLog.shared.append("speak start=\(start) c\(chunk) +\(Int(fractionInChunk * 100))% count=\(paragraphs.count) epoch=\(e)")
        ensureProducerRunning(epoch: e)
    }

    func pause() {
        resumePointStore?.clear()
        starvedAt = nil
        speakRequestedAt = nil
        userWantsAudible = false
        isPaused = true
        isSpeaking = false
        player.pause()
        // Producer may finish the in-flight unit and enqueue; player stays soft-paused.
    }

    func resume() {
        if let id = articleID, let p = player.currentParagraphIndex { resumePointStore?.save(article: id, paragraph: p) }
        userWantsAudible = true
        isPaused = false
        isSpeaking = true
        player.resume()
        // Same epoch — do not cancel in-flight produce or skip units.
        player.awaitingMore = nextProduceIndex < paragraphs.count
        ensureProducerRunning(epoch: epoch)
    }

    func stop() {
        stopInternal(clearCallbacks: false)
    }

    /// Back in the foreground: Apple units rendered ahead only because the engine was paused in
    /// the background (queued, not started) are dropped and production restarts at the first
    /// of them, so the engine's voice returns within one paragraph instead of after up to
    /// `maxBuffered` Apple paragraphs. Nothing is skipped: the dropped paragraphs are produced
    /// again, in order, while the current unit keeps playing.
    /// Returns the paragraph production restarts from (nil = nothing to reclaim).
    @discardableResult
    func reclaimBackgroundFallbacks() -> Int? {
        let reasons = appleFallbackReasons
        guard let first = player.dropQueued(fromFirstWhere: { item in
            (item.chunkIndex ?? 0) >= 10_000 && reasons[item.paragraphIndex] == "background"
        }) else { return nil }
        producerTask?.cancel()
        producerTask = nil
        epoch += 1 // an in-flight produce must not enqueue after the restart point
        nextProduceIndex = first.paragraphIndex
        nextProduceChunk = max(0, (first.chunkIndex ?? 10_000) - 10_000)
        player.awaitingMore = true
        ListenDebugLog.shared.append("foreground: re-rendering from p\(first.paragraphIndex) with \(engineShortName) (dropped queued Apple units)")
        ListenTimingLog.log("bg_fallback_reclaimed", [
            "key": ListenTimingLog.shortKey(articleID), "from_p": first.paragraphIndex, "c": nextProduceChunk,
        ])
        ensureProducerRunning(epoch: epoch)
        return first.paragraphIndex
    }

    func skip(by delta: Int) {
        let current = player.currentParagraphIndex ?? max(0, nextProduceIndex - 1)
        let next = max(0, min(paragraphs.count - 1, current + delta))
        seek(to: next)
    }

    /// `SpeechSynthesizing` conformance: the AVSpeech-scale rate → a playback multiplier.
    func setRate(_ rate: Float) {
        setPlaybackRate(rate / AVSpeechUtteranceDefaultSpeechRate)
    }

    /// Listen speed (Nav I): a time-stretch on the player, applied in place. Audio is always
    /// rendered at 1× (engine and Apple fallback alike), so nothing is re-rendered or re-queued
    /// and the current sentence just continues faster / slower.
    func setPlaybackRate(_ multiplier: Float) {
        player.setRate(multiplier)
    }

    var playbackRate: Float { player.playbackRate }
    /// Where the unit now playing is (scrubber within-paragraph progress).
    var currentPlaybackPosition: (item: ChunkPlaybackQueue.Item, time: TimeInterval, duration: TimeInterval)? {
        player.currentPosition
    }

    func setVoice(id: String?) {
        voiceID = id
        if isSpeaking || isPaused { seek(to: player.currentParagraphIndex ?? nextProduceIndex) }
    }

    /// One synth chunk → CAF (GlobalSynthQueue worker). Re-splits internally on overflow.
    func renderChunkToFile(text: String, destination: URL, seed: UInt64, context: [String: Any]) async throws -> TimeInterval {
        try await prepareIfNeeded()
        return try await currentRenderer().renderChunk(text: text, to: destination, seed: seed, context: context)
    }

    /// Apple TTS render of one chunk (never-skip fallback when the engine cannot synthesize it).
    func renderAppleFallback(text: String, destination: URL, rate: Float, voiceID: String?) async throws -> TimeInterval {
        try await probeFallback.render(text: text, to: destination, rate: rate, voiceID: voiceID, language: language)
    }

    /// Debug engine probe: one production call on the active host (same gate / compute units).
    /// Returns wall ms for the whole text and, separately, for its first synth chunk.
    func debugTimedSynth(text: String) async throws -> (wallMs: Int, firstChunkMs: Int, audioSeconds: Double, chunks: Int) {
        try await prepareIfNeeded()
        let host = try currentRenderer()
        let chunks = TextChunker.chunks(for: text, limits: limits)
        var total = 0.0
        var firstMs = 0
        let t0 = ListenTimingLog.now()
        for (i, chunk) in chunks.enumerated() {
            let url = tempDir.appendingPathComponent("probe-\(UUID().uuidString).caf")
            defer { try? FileManager.default.removeItem(at: url) }
            total += try await host.renderChunk(text: chunk, to: url, seed: 42, context: ["probe": true, "c": i])
            if i == 0 { firstMs = ListenTimingLog.ms(since: t0) }
        }
        return (ListenTimingLog.ms(since: t0), firstMs, total, chunks.count)
    }

    func renderParagraphToFile(text: String, destination: URL, rate: Float, voiceID: String?) async throws -> TimeInterval {
        try await prepareIfNeeded()
        return try await renderLive(text: text, to: destination, voiceID: voiceID, rate: rate, paragraphIndex: nil)
    }

    func resetHostPrepared() {
        rendererBox?.host.resetPrepared()
        rendererBox = nil
    }

    /// Drop the host entirely (delete model / switch to Apple).
    func unloadHost() {
        if let old = rendererBox {
            rendererBox = nil
            Task { await old.host.unload() }
        }
    }

    // MARK: - Private

    private func seek(to index: Int) {
        let next = max(0, min(paragraphs.count - 1, index))
        producerTask?.cancel()
        producerTask = nil
        player.clear()
        nextProduceIndex = next
        nextProduceChunk = 0
        pendingStartFraction = 0
        priorityStart = next
        speakRequestedAt = ListenTimingLog.now()
        starvedAt = nil
        onParagraphIndexChange?(next)
        epoch += 1
        let e = epoch
        userWantsAudible = true
        isPaused = false
        isSpeaking = true
        player.awaitingMore = true
        ensureProducerRunning(epoch: e)
    }

    private func stopInternal(clearCallbacks: Bool) {
        resumePointStore?.clear()
        currentAppleFallbackReason = nil
        appleFallbackReasons.removeAll()
        epoch += 1
        starveWatchGeneration += 1
        producerTask?.cancel()
        producerTask = nil
        player.clear()
        userWantsAudible = false
        isSpeaking = false
        isPaused = false
        nextProduceIndex = 0
        nextProduceChunk = 0
        pendingStartFraction = 0
        speakRequestedAt = nil
        starvedAt = nil
        _ = clearCallbacks
    }

    private func ensureProducerRunning(epoch forced: Int? = nil) {
        let e = forced ?? epoch
        guard producerTask == nil else { return }
        guard nextProduceIndex < paragraphs.count else {
            player.awaitingMore = false
            if !player.hasQueuedOrCurrent, !player.isAudible {
                if userWantsAudible || isSpeaking {
                    isSpeaking = false
                    userWantsAudible = false
                    onFinished?()
                }
            }
            return
        }
        player.awaitingMore = true
        producerTask = Task { [weak self] in
            await self?.runProducer(epoch: e)
        }
    }

    /// Empty queue while more units remain — re-kick fill and arm a watchdog so a wedged
    /// producer task cannot leave the session awaitingMore forever.
    private func handleStarved() {
        ListenDebugLog.shared.append("starved nextProduce=\(nextProduceIndex) c\(nextProduceChunk) buf=\(player.bufferedCount) epoch=\(epoch)")
        if starvedAt == nil, userWantsAudible { starvedAt = ListenTimingLog.now() }
        ensureProducerRunning()
        armStarveWatchdog()
    }

    /// Recover only genuinely stuck states. While the worker is actively rendering the unit the
    /// producer waits for, re-arm instead of cancelling (cancel/re-kick never skips, but it was
    /// churning epochs every 1.5 s during long renders).
    private func armStarveWatchdog() {
        starveWatchGeneration += 1
        let watch = starveWatchGeneration
        let e = epoch
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self else { return }
            guard self.starveWatchGeneration == watch, self.epoch == e else { return }
            guard self.userWantsAudible || self.isSpeaking || self.isPaused else { return }
            guard self.nextProduceIndex < self.paragraphs.count else {
                self.player.awaitingMore = false
                if !self.player.hasQueuedOrCurrent, !self.player.isAudible {
                    self.isSpeaking = false
                    self.userWantsAudible = false
                    self.onFinished?()
                }
                return
            }
            if self.player.bufferedCount == 0, self.producerTask != nil,
               self.isRenderingParagraph?(self.nextProduceIndex) == true {
                // Actively rendering the awaited unit — healthy, just slow. Keep watching.
                self.armStarveWatchdog()
                return
            }
            // Still starved (nothing Ready) — cancel wedged task and restart.
            // Bump epoch so an in-flight resolve cannot enqueue the same index after we restart.
            if self.player.bufferedCount == 0 {
                print("[LocalPlay] starved watchdog: re-kick produce at index \(self.nextProduceIndex)")
                self.producerTask?.cancel()
                self.producerTask = nil
                self.epoch += 1
                let restarted = self.epoch
                self.player.awaitingMore = true
                self.ensureProducerRunning(epoch: restarted)
            }
        }
    }

    private func runProducer(epoch e: Int) async {
        defer {
            if epoch == e { producerTask = nil }
        }
        player.awaitingMore = true

        while !Task.isCancelled, e == epoch {
            // Lane 1 — Immediate: fill the player from nextProduceIndex (playhead stretch).
            if paragraphs.indices.contains(nextProduceIndex), player.canAcceptMore {
                let index = nextProduceIndex
                // Already queued/playing (e.g. after a raced re-kick) — advance past it.
                if nextProduceChunk == 0, player.bufferedParagraphIndices.contains(index) {
                    nextProduceIndex = index + 1
                    continue
                }
                let text = paragraphs[index]
                // Baked paragraph (all chunks stitched) → play the whole CAF.
                if nextProduceChunk == 0, let baked = bakedURLProvider?(index), isUsableAudioFile(baked) {
                    nextProduceIndex = index + 1
                    let start = consumeStartTime(fileURL: baked, paragraph: index, chunk: 0, fileStartTime: 0, wholeParagraph: true)
                    player.enqueue(.init(paragraphIndex: index, fileURL: baked, startTime: start, isWholeParagraph: true))
                    continue
                }
                // Play-while-building: enqueue each synth chunk as soon as it is rendered.
                if let chunkEnsureProvider, let chunkCount = chunkCountProvider?(text) {
                    if chunkCount == 0 {
                        // Nothing speakable (e.g. "***"). Not a skip of real audio.
                        ListenDebugLog.shared.append("p\(index) has no speakable text")
                        nextProduceIndex = index + 1
                        nextProduceChunk = 0
                        continue
                    }
                    let k = min(nextProduceChunk, chunkCount - 1)
                    if projectsUnderrun(index: index, chunk: k, text: text) {
                        await fallbackToApple(index: index, fromChunk: k, text: text, error: RenderFellBehind(), epoch: e)
                        continue
                    }
                    do {
                        let resolution = try await chunkEnsureProvider(index, k, text)
                        guard e == epoch else { return }
                        switch resolution {
                        case .chunk(let url):
                            let start = consumeStartTime(fileURL: url, paragraph: index, chunk: k, fileStartTime: 0, wholeParagraph: false)
                            player.enqueue(.init(paragraphIndex: index, fileURL: url, chunkIndex: k, startTime: start))
                            if k + 1 >= chunkCount {
                                nextProduceIndex = index + 1
                                nextProduceChunk = 0
                            } else {
                                nextProduceChunk = k + 1
                            }
                        case .paragraph(let url, let startTime):
                            // Paragraph finished (scratch gone) — play the rest from the stitched CAF.
                            let start = consumeStartTime(fileURL: url, paragraph: index, chunk: k, fileStartTime: startTime, wholeParagraph: true)
                            player.enqueue(.init(paragraphIndex: index, fileURL: url, chunkIndex: k, startTime: start,
                                                 isWholeParagraph: true))
                            nextProduceIndex = index + 1
                            nextProduceChunk = 0
                        }
                    } catch is CancellationError {
                        return
                    } catch {
                        guard e == epoch else { return }
                        await fallbackToApple(index: index, fromChunk: k, text: text, error: error, epoch: e)
                    }
                    continue
                }
                do {
                    let url = try await resolveReadyURL(index: index, text: text, epoch: e)
                    guard e == epoch else { return }
                    nextProduceIndex = index + 1
                    pendingStartFraction = 0
                    // Dedupe: queue may already hold this index if another produce raced.
                    if !player.bufferedParagraphIndices.contains(index) {
                        player.enqueue(.init(paragraphIndex: index, fileURL: url))
                    }
                } catch is CancellationError {
                    return
                } catch {
                    guard e == epoch else { return }
                    await fallbackToApple(index: index, fromChunk: 0, text: text, error: error, epoch: e)
                }
                continue
            }

            // Batch / rest-of-article bake is owned by GlobalSynthQueue (article #1 plan).
            // Producer only fills the player buffer (immediate lane).
            if nextProduceIndex >= paragraphs.count {
                player.awaitingMore = false
                if !player.isAudible, player.bufferedCount == 0, userWantsAudible || isSpeaking {
                    isSpeaking = false
                    userWantsAudible = false
                    onFinished?()
                }
                return
            }
            // Buffer full — wait for drain / space.
            try? await Task.sleep(nanoseconds: 40_000_000)
        }
    }

    /// Start time for the first unit after a sub-paragraph speak (`pendingStartFraction` of chunk
    /// `chunk`), then 0 for every later unit. `fileStartTime` = where chunk `chunk` begins in the
    /// file (stitched paragraph) — the fraction is applied to that chunk's duration.
    private func consumeStartTime(fileURL: URL, paragraph: Int, chunk: Int, fileStartTime: TimeInterval,
                                  wholeParagraph: Bool) -> TimeInterval {
        let fraction = pendingStartFraction
        pendingStartFraction = 0
        guard fraction > 0 else { return fileStartTime }
        let chunkDuration: TimeInterval
        if wholeParagraph {
            let fileDuration = Self.audioDuration(fileURL)
            if let durations = chunkDurationsProvider?(paragraph), durations.indices.contains(chunk) {
                chunkDuration = durations[chunk]
            } else {
                chunkDuration = max(0, fileDuration - fileStartTime) // single chunk: the whole file
            }
        } else {
            chunkDuration = Self.audioDuration(fileURL)
        }
        return max(fileStartTime, fileStartTime + chunkDuration * fraction - Self.subChunkLeadIn)
    }

    private static func audioDuration(_ url: URL) -> TimeInterval {
        guard let f = try? AVAudioFile(forReading: url), f.fileFormat.sampleRate > 0 else { return 0 }
        return Double(f.length) / f.fileFormat.sampleRate
    }

    /// Head-start rule: on a route that keeps rendering while audio plays (ONNX CPU), if the
    /// measured render speed can't deliver the rest of this paragraph before the buffered audio
    /// runs out (plus a short tolerance), speak this paragraph with Apple and let the worker get
    /// ahead on the next ones. Never at the start of a play/jump (nothing audible yet — the short
    /// first chunk is fast) and only while the chunk isn't already rendered.
    private func projectsUnderrun(index: Int, chunk k: Int, text: String) -> Bool {
        guard hostRendersInBackground, player.isAudible,
              let ready = chunkReadyProvider, !ready(index, k, text) else { return false }
        let chunks = chunkTextsProvider?(text) ?? TextChunker.chunks(for: text, limits: limits)
        guard chunks.indices.contains(k) else { return false }
        let remaining = chunks[k...].reduce(0) { $0 + $1.count }
        let buffered = player.bufferedSecondsAhead
        let pace = RenderPace.shared.snapshot
        let behind = HeadStart.projectsUnderrun(
            remainingChars: remaining, firstChunkChars: chunks[k].count, bufferedAudio: buffered,
            pace: pace, rate: Double(player.playbackRate), workerBusyOther: workerBusyElsewhere?(index) ?? false)
        if behind {
            behindFallbackCount += 1
            ListenTimingLog.log("render_behind", [
                "key": ListenTimingLog.shortKey(articleID), "p": index, "c": k,
                "buffered_s": (buffered * 10).rounded() / 10, "speed": ((pace.speed ?? 0) * 100).rounded() / 100,
                "remaining_chars": remaining,
            ])
        }
        return behind
    }

    /// Never silently skip: the engine could not produce this paragraph (or its remaining chunks), so
    /// speak the remainder with Apple TTS as a one-off unit. Only if that fails too do we move on
    /// — and say so in the debug overlay + timing log.
    private func fallbackToApple(index: Int, fromChunk: Int, text: String, error: Error, epoch e: Int) async {
        pendingStartFraction = 0 // Apple units start at their chunk boundary
        let chunks = TextChunker.chunks(for: text, limits: limits)
        let remainder = fromChunk < chunks.count && fromChunk > 0
            ? chunks[fromChunk...].joined(separator: " ")
            : TextChunker.normalize(text)
        let background: Bool = {
            if case LocalSynthError.deferredInBackground = error { return true }
            return false
        }()
        let behind = error is RenderFellBehind
        appleFallbackReasons[index] = background ? "background" : (behind ? "behind" : "engine error")
        appleFallbackCount += 1
        ListenDebugLog.shared.append(background
            ? "p\(index) c\(fromChunk) not rendered yet, app in background → Apple TTS"
            : behind
            ? "p\(index) c\(fromChunk) \(engineShortName) behind playback → Apple TTS for this paragraph"
            : "p\(index) c\(fromChunk) \(engineShortName) failed → Apple TTS (\(error.localizedDescription))")
        let url = tempDir.appendingPathComponent("apple-\(e)-\(index)-\(fromChunk).caf")
        let t0 = ListenTimingLog.now()
        do {
            // 1× like every other unit: the player applies the listen speed (`setPlaybackRate`).
            _ = try await probeFallback.render(text: remainder, to: url, rate: AVSpeechUtteranceDefaultSpeechRate,
                                               voiceID: voiceID, language: language)
            guard e == epoch else { return }
            ListenTimingLog.log("fallback_apple", ["p": index, "c": fromChunk, "live": true,
                                                   "chars": remainder.count, "ms": ListenTimingLog.ms(since: t0),
                                                   "engine": engineShortName, "local_err": error.localizedDescription])
            if isUsableAudioFile(url) {
                player.enqueue(.init(paragraphIndex: index, fileURL: url, chunkIndex: 10_000 + fromChunk))
            }
        } catch {
            ListenDebugLog.shared.append("SKIP p\(index): \(engineShortName) and Apple TTS both failed (\(error.localizedDescription))")
            ListenTimingLog.log("skip", ["p": index, "err": error.localizedDescription])
        }
        guard e == epoch else { return }
        nextProduceIndex = index + 1
        nextProduceChunk = 0
    }

    private func noteUnitKind(_ item: ChunkPlaybackQueue.Item) {
        let isApple = (item.chunkIndex ?? 0) >= 10_000
        currentAppleFallbackReason = isApple ? (appleFallbackReasons[item.paragraphIndex] ?? "fallback") : nil
        guard AppRunState.shared.phase == .background else { return }
        if isApple {
            backgroundStats.appleFallbacks += 1
        } else if item.chunkIndex == nil || item.startTime > 0 {
            backgroundStats.bakedParagraphs += 1
        } else {
            backgroundStats.engineChunks += 1
        }
        ListenTimingLog.log("bg_unit", [
            "key": ListenTimingLog.shortKey(articleID), "p": item.paragraphIndex, "c": item.chunkIndex ?? -1,
            "kind": isApple ? "apple" : (item.chunkIndex == nil ? "baked" : "chunk"),
        ])
    }

    /// first_audio (after Play/seek) and buffering (Preparing next…) intervals.
    private func noteUnitStartedForTiming(_ item: ChunkPlaybackQueue.Item) {
        let from = item.chunkIndex == nil ? "baked" : "chunk"
        if let t = speakRequestedAt {
            ListenTimingLog.log("first_audio", [
                "key": ListenTimingLog.shortKey(articleID), "p": item.paragraphIndex,
                "c": item.chunkIndex ?? -1, "ms": ListenTimingLog.ms(since: t), "from": from,
            ])
            speakRequestedAt = nil
            starvedAt = nil
        } else if let t = starvedAt {
            ListenTimingLog.log("buffering", [
                "key": ListenTimingLog.shortKey(articleID), "p": item.paragraphIndex,
                "c": item.chunkIndex ?? -1, "dur_ms": ListenTimingLog.ms(since: t), "from": from,
            ])
            starvedAt = nil
        }
    }

    /// Next missing index per BakePriorityPlan.fromPlayhead(priorityStart), skipping the
    /// immediate head (`nextProduceIndex`) so we never dual-render one unit.
    private func nextBatchIndex() -> Int? {
        guard !paragraphs.isEmpty else { return nil }
        let buffered = player.bufferedParagraphIndices
        let missing = paragraphs.indices.filter { bakedURLProvider?($0) == nil }
        let order = BakePriorityPlan.fromPlayhead(priorityStart, paragraphCount: paragraphs.count)
            .orderedWork(missing: Array(missing))
        // Skip the immediate head and anything already in the player buffer.
        return order.first { $0 != nextProduceIndex && !buffered.contains($0) }
    }

    /// Prefer bake cache; else GlobalSynthQueue ensure; else live render + persist.
    private func resolveReadyURL(index: Int, text: String, epoch e: Int) async throws -> URL {
        if let baked = bakedURLProvider?(index), isUsableAudioFile(baked) {
            return baked
        }
        if let unitEnsureProvider {
            let url = try await unitEnsureProvider(index, text)
            guard isUsableAudioFile(url) else {
                throw NSError(
                    domain: "LocalModelSpeechEngine",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Queue ensure produced empty CAF at \(index)"]
                )
            }
            return url
        }
        let url = tempDir.appendingPathComponent("live-\(e)-\(index).caf")
        let duration = try await renderLive(
            text: text,
            to: url,
            voiceID: voiceID,
            rate: rate,
            paragraphIndex: index
        )
        guard isUsableAudioFile(url) else {
            throw NSError(
                domain: "LocalModelSpeechEngine",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Live render produced empty CAF at \(index)"]
            )
        }
        if let persisted = await onUnitRendered?(index, url, duration), isUsableAudioFile(persisted) {
            return persisted
        }
        return url
    }

    private func isUsableAudioFile(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        return size > 256
    }


    private func seed(for voiceID: String?, paragraphIndex: Int?) -> UInt64 {
        if let voiceID, !voiceID.isEmpty {
            var hasher = Hasher()
            hasher.combine(voiceID)
            hasher.combine(paragraphIndex ?? -1)
            return UInt64(bitPattern: Int64(hasher.finalize()))
        }
        return UInt64.random(in: 0..<UInt64.max)
    }

    private func renderLive(
        text: String,
        to destination: URL,
        voiceID: String?,
        rate: Float,
        paragraphIndex: Int?
    ) async throws -> TimeInterval {
        _ = rate
        return try await currentRenderer().render(
            text: text,
            to: destination,
            seed: seed(for: voiceID, paragraphIndex: paragraphIndex)
        )
    }
}
