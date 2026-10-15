import AVFoundation
import Foundation

/// The on-device engine's file player and producer. Each play binds one `ListenUnitSource`; the
/// producer fills `ChunkPlaybackQueue` from it in reading order: rendered paragraphs, chunks as
/// they are rendered, and Apple renders where the engine can't keep up (never a silent skip). It
/// reports unit starts and the article's end; `LocalListenEngine` turns those into session
/// events. The model and the render queue live behind the source. See docs/LISTEN_PLAYBACK.md.
@MainActor
final class LocalListenPlayer {
    private let player: ChunkPlaybackQueue
    private let tempDir: URL
    /// Audio of the current play (nil: stopped).
    private var source: ListenUnitSource?
    private var paragraphs: [String] { source?.paragraphs ?? [] }

    /// Produce epoch — bump only on stop / new play / seek. Never on pause/resume.
    private var epoch = 0
    private var nextProduceIndex = 0
    /// Next synth chunk of `nextProduceIndex` to enqueue (play-while-building).
    private var nextProduceChunk = 0
    /// Timing: when the current play/seek asked for audio (first_audio), and open starve.
    private var speakRequestedAt: CFAbsoluteTime?
    private var starvedAt: CFAbsoluteTime?
    private var producerTask: Task<Void, Never>?
    /// User wants audio moving (false while paused). Independent of produce epoch.
    private var userWantsAudible = false
    /// Generation for starved-watchdog tasks; bumped whenever we leave play/resume paths.
    private var starveWatchGeneration = 0

    private(set) var isSpeaking = false
    private(set) var isPaused = false

    /// Units played while the app was backgrounded, by source (listen debug panel).
    struct BackgroundPlayStats: Equatable {
        var bakedParagraphs = 0
        var engineChunks = 0
        var appleFallbacks = 0
        var label: String { "baked \(bakedParagraphs) · chunks \(engineChunks) · Apple \(appleFallbacks)" }
    }
    var backgroundStats = BackgroundPlayStats()
    /// Why the unit now playing is Apple TTS (nil = the engine's own audio).
    private(set) var currentAppleFallbackReason: FallbackReason?

    /// A unit of this paragraph started playing.
    var onUnitStarted: ((Int) -> Void)?
    /// The article played out (all units played, nothing more to produce). Once per play.
    var onFinished: (() -> Void)?
    /// The player ran dry with more to come: it waits for the next unit.
    var onStarved: (() -> Void)?
    /// Sub-paragraph start: how far into the first unit of this play/seek to begin, as a
    /// fraction of its synth chunk. Consumed by the first enqueue of the start paragraph.
    private var pendingStartFraction: Double = 0
    /// Lead-in before an estimated sentence start (the in-chunk position is a character-based
    /// estimate; starting a hair early beats clipping the first word).
    static let subChunkLeadIn: TimeInterval = 0.25

    /// The render ran behind playback: this paragraph plays with Apple (see `HeadStart`).
    struct RenderFellBehind: LocalizedError {
        var errorDescription: String? { "Kokoro rendering fell behind playback" }
    }

    /// Article whose audio is playing right now (nil when paused / stopped).
    var playingArticleID: UUID? { (isSpeaking && !isPaused) ? source?.articleID : nil }

    /// Where Apple fallback units are written (`tmp/ReaderTTSLive`), never cached: each file is
    /// deleted once its unit leaves the player (played out, dropped, stopped), or at once when it
    /// isn't queued. The first player of a process empties the folder of what an earlier process
    /// left (iOS empties `tmp` only when storage runs low, and never while the app runs).
    private static let fallbackDirectory: URL = {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("ReaderTTSLive", isDirectory: true)
        try? fm.removeItem(at: dir)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// `player` is injectable so tests can end units without waiting for real audio.
    init(player injected: ChunkPlaybackQueue? = nil) {
        self.player = injected ?? ChunkPlaybackQueue(maxBuffered: 8)
        self.tempDir = Self.fallbackDirectory

        player.onUnitStarted = { [weak self] item in
            guard let self else { return }
            self.noteUnitStartedForTiming(item)
            self.noteUnitKind(item)
            self.isSpeaking = true
            self.isPaused = false
            self.onUnitStarted?(item.paragraphIndex)
            // Start / keep producing the next units as soon as one begins playing.
            self.ensureProducerRunning()
        }
        player.onUnitEnded = { [weak self] in
            // Buffer dipped — (re)start the fill loop while more units remain.
            self?.ensureProducerRunning()
        }
        player.onStarved = { [weak self] in
            self?.handleStarved()
        }
        player.onError = { error in
            print("[LocalPlay] unit error (fail-forward): \(error.localizedDescription)")
        }
        player.onItemDone = { item in
            if case .appleFallback = item.source { Self.deleteFallbackFile(item.fileURL) }
        }
        player.onFinished = { [weak self] in
            // The only place the article ends (see `ChunkPlaybackQueue.endOfInput`); once per play.
            guard let self, self.userWantsAudible || self.isSpeaking else { return }
            self.isSpeaking = false
            self.isPaused = false
            self.userWantsAudible = false
            self.onFinished?()
        }
    }

    var isAudible: Bool { player.isAudible }
    /// Units in the player: the one playing plus those queued.
    var bufferedUnitCount: Int { player.bufferedCount }
    /// The producer has more to enqueue for this play.
    var awaitingMore: Bool { player.awaitingMore }
    /// The producer is filling the buffer (or waiting for a render) right now.
    var isProducing: Bool { producerTask != nil }
    /// The next paragraph the producer will enqueue.
    var nextParagraphToProduce: Int { nextProduceIndex }

    /// Listening time the player can play from here without another render, in seconds at the
    /// listen speed: the rest of the unit playing, the units queued, then the paragraphs after them
    /// already rendered, up to the first that isn't (one with nothing speakable is no gap). Counts
    /// up to `limit`; 0 when stopped. The render queue's background bursts start and stop on it.
    func readyAheadSeconds(upTo limit: TimeInterval) -> TimeInterval {
        guard let source else { return 0 }
        let rate = Double(max(player.playbackRate, 0.1))
        var audio = player.bufferedSecondsAhead
        var index = nextProduceIndex
        if nextProduceChunk > 0 {
            // Mid-paragraph: the rest of it counts once it is stitched (chunk durations known).
            guard let durations = source.renderedParagraph(index)?.chunkDurations,
                  durations.count > nextProduceChunk else { return audio / rate }
            audio += durations[nextProduceChunk...].reduce(0, +)
            index += 1
        }
        while index < source.paragraphs.count, audio / rate < limit {
            if let rendered = source.renderedParagraph(index) {
                audio += rendered.duration
            } else if !source.chunks(paragraph: index).isEmpty {
                break
            }
            index += 1
        }
        return audio / rate
    }

    // MARK: - Listen debug
    var debugEpoch: Int { epoch }
    var debugCurrentCAF: String { player.currentFileName ?? "—" }
    var debugSecondsSinceEnqueue: Double? { player.secondsSinceLastEnqueue }
    var debugLastHandoffGapMs: Double { player.lastHandoffGapMs }
    var debugLastHandoffWasPrimed: Bool { player.lastHandoffWasPrimed }
    var debugStarveEventCount: Int { player.starveEventCount }

    /// Play `source` from synth chunk `chunk` of paragraph `index`, `fractionInChunk` (0…1) into
    /// it (scrubbed to a sentence). Unrendered: that chunk is rendered first. Returns without
    /// starting when another `play` or a `stop` arrives while the model loads: that call owns
    /// the player now.
    func play(_ source: ListenUnitSource, from index: Int, chunk: Int, fractionInChunk: Double) async throws {
        stop()
        let request = epoch
        try await source.prepare()
        guard request == epoch else { return }
        self.source = source
        let paragraphs = source.paragraphs
        let start = max(0, min(index, max(paragraphs.count - 1, 0)))
        nextProduceIndex = start
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
        starvedAt = nil
        speakRequestedAt = nil
        userWantsAudible = false
        isPaused = true
        isSpeaking = false
        player.pause()
        // Producer may finish the in-flight unit and enqueue; player stays soft-paused.
    }

    func resume() {
        userWantsAudible = true
        isPaused = false
        isSpeaking = true
        player.resume()
        // Same epoch — do not cancel in-flight produce or skip units.
        player.awaitingMore = nextProduceIndex < paragraphs.count
        ensureProducerRunning(epoch: epoch)
    }

    func stop() {
        source = nil
        currentAppleFallbackReason = nil
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
    }

    /// Back in the foreground: Apple units rendered ahead only because the engine was paused in
    /// the background (queued, not started) are dropped and production restarts at the first
    /// of them, so the engine's voice returns within one paragraph instead of after up to
    /// `maxBuffered` Apple paragraphs. Nothing is skipped: the dropped paragraphs are produced
    /// again, in order, while the current unit keeps playing.
    func reclaimBackgroundFallbacks() {
        guard let source, let first = player.dropQueued(fromFirstWhere: { item in
            if case .appleFallback(_, .background) = item.source { return true }
            return false
        }) else { return }
        producerTask?.cancel()
        producerTask = nil
        epoch += 1 // an in-flight produce must not enqueue after the restart point
        nextProduceIndex = first.paragraphIndex
        nextProduceChunk = first.source.startChunk ?? 0
        player.awaitingMore = true
        ListenDebugLog.shared.append("foreground: re-rendering from p\(first.paragraphIndex) with \(source.engineName) (dropped queued Apple units)")
        ListenTimingLog.log("bg_fallback_reclaimed", [
            "key": ListenTimingLog.shortKey(source.articleID), "from_p": first.paragraphIndex, "c": nextProduceChunk,
        ])
        source.focus(paragraph: first.paragraphIndex)
        ensureProducerRunning(epoch: epoch)
    }

    /// Listen speed: a time-stretch on the player, applied in place. Audio is always
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

    // MARK: - Private

    private func ensureProducerRunning(epoch forced: Int? = nil) {
        let e = forced ?? epoch
        guard producerTask == nil else { return }
        guard let source, nextProduceIndex < source.paragraphs.count else {
            player.endOfInput()
            return
        }
        player.awaitingMore = true
        producerTask = Task { [weak self] in
            await self?.runProducer(epoch: e, source: source)
        }
    }

    /// Empty queue while more units remain — re-kick fill and arm a watchdog so a wedged
    /// producer task cannot leave the session awaitingMore forever.
    private func handleStarved() {
        ListenDebugLog.shared.append("starved nextProduce=\(nextProduceIndex) c\(nextProduceChunk) buf=\(player.bufferedCount) epoch=\(epoch)")
        if starvedAt == nil, userWantsAudible { starvedAt = ListenTimingLog.now() }
        ensureProducerRunning()
        armStarveWatchdog()
        onStarved?()
    }

    /// Recover only genuinely stuck states. While the worker is actively rendering the unit the
    /// producer waits for, re-arm instead of cancelling (cancel/re-kick never skips, but would
    /// churn epochs every 1.5 s during a long render).
    private func armStarveWatchdog() {
        starveWatchGeneration += 1
        let watch = starveWatchGeneration
        let e = epoch
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self else { return }
            guard self.starveWatchGeneration == watch, self.epoch == e else { return }
            guard self.userWantsAudible || self.isSpeaking || self.isPaused else { return }
            guard let source = self.source, self.nextProduceIndex < source.paragraphs.count else {
                self.player.endOfInput()
                return
            }
            if self.player.bufferedCount == 0, self.producerTask != nil,
               source.workerStatus(paragraph: self.nextProduceIndex) == .renderingThisParagraph {
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

    private func runProducer(epoch e: Int, source: ListenUnitSource) async {
        defer {
            if epoch == e { producerTask = nil }
        }
        player.awaitingMore = true
        let paragraphs = source.paragraphs

        while !Task.isCancelled, e == epoch {
            // Lane 1 — Immediate: fill the player from nextProduceIndex (playhead stretch).
            if paragraphs.indices.contains(nextProduceIndex), player.canAcceptMore {
                let index = nextProduceIndex
                // Already queued/playing (e.g. after a raced re-kick) — advance past it.
                if nextProduceChunk == 0, player.bufferedParagraphIndices.contains(index) {
                    nextProduceIndex = index + 1
                    continue
                }
                // Rendered paragraph (all chunks stitched) → play the whole CAF.
                if nextProduceChunk == 0, let rendered = source.renderedParagraph(index) {
                    nextProduceIndex = index + 1
                    let start = consumeStartTime(fileURL: rendered.url, chunk: 0, fileStartTime: 0,
                                                 wholeParagraph: true, chunkDurations: rendered.chunkDurations)
                    player.enqueue(.init(paragraphIndex: index, fileURL: rendered.url, source: .baked, startTime: start,
                                         chunkDurations: rendered.chunkDurations))
                    continue
                }
                // Play-while-building: enqueue each synth chunk as soon as it is rendered.
                let chunks = source.chunks(paragraph: index)
                if chunks.isEmpty {
                    // Nothing speakable (e.g. "***"). Not a skip of real audio.
                    ListenDebugLog.shared.append("p\(index) has no speakable text")
                    nextProduceIndex = index + 1
                    nextProduceChunk = 0
                    continue
                }
                let k = min(nextProduceChunk, chunks.count - 1)
                if projectsUnderrun(source, index: index, chunk: k, chunks: chunks) {
                    await fallbackToApple(source, index: index, fromChunk: k, error: RenderFellBehind(), epoch: e)
                    continue
                }
                do {
                    let resolution = try await source.chunk(paragraph: index, chunk: k)
                    guard e == epoch else { return }
                    switch resolution {
                    case .chunk(let url):
                        let start = consumeStartTime(fileURL: url, chunk: k, fileStartTime: 0,
                                                     wholeParagraph: false, chunkDurations: nil)
                        player.enqueue(.init(paragraphIndex: index, fileURL: url, source: .chunk(k), startTime: start))
                        if k + 1 >= chunks.count {
                            nextProduceIndex = index + 1
                            nextProduceChunk = 0
                        } else {
                            nextProduceChunk = k + 1
                        }
                    case .paragraph(let url, let startTime):
                        // Paragraph finished (scratch gone) — play the rest from the stitched CAF.
                        let durations = source.chunkDurations(paragraph: index)
                        let start = consumeStartTime(fileURL: url, chunk: k, fileStartTime: startTime,
                                                     wholeParagraph: true, chunkDurations: durations)
                        player.enqueue(.init(paragraphIndex: index, fileURL: url, source: .stitched(fromChunk: k),
                                             startTime: start, chunkDurations: durations))
                        nextProduceIndex = index + 1
                        nextProduceChunk = 0
                    }
                } catch is CancellationError {
                    return
                } catch {
                    guard e == epoch else { return }
                    await fallbackToApple(source, index: index, fromChunk: k, error: error, epoch: e)
                }
                continue
            }

            // Rendering the rest of the article is the render queue's job; the producer only
            // fills the player buffer.
            if nextProduceIndex >= paragraphs.count {
                player.endOfInput()
                return
            }
            // Buffer full: stop. The next unit to end (`onUnitEnded`) starts the producer again,
            // so a long baked listen costs no wake-ups while the buffer is full.
            return
        }
    }

    /// Start time for the first unit after a sub-paragraph speak (`pendingStartFraction` of chunk
    /// `chunk`), then 0 for every later unit. `fileStartTime` = where chunk `chunk` begins in the
    /// file (stitched paragraph) — the fraction is applied to that chunk's duration
    /// (`chunkDurations`, the paragraph file's index entry).
    private func consumeStartTime(fileURL: URL, chunk: Int, fileStartTime: TimeInterval,
                                  wholeParagraph: Bool, chunkDurations: [TimeInterval]?) -> TimeInterval {
        let fraction = pendingStartFraction
        pendingStartFraction = 0
        guard fraction > 0 else { return fileStartTime }
        let chunkDuration: TimeInterval
        if wholeParagraph {
            if let durations = chunkDurations, durations.indices.contains(chunk) {
                chunkDuration = durations[chunk]
            } else {
                chunkDuration = max(0, Self.audioDuration(fileURL) - fileStartTime) // single chunk: the whole file
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
    private func projectsUnderrun(_ source: ListenUnitSource, index: Int, chunk k: Int, chunks: [String]) -> Bool {
        guard source.rendersInBackground, player.isAudible, chunks.indices.contains(k),
              !source.isChunkReady(paragraph: index, chunk: k) else { return false }
        let remaining = chunks[k...].reduce(0) { $0 + $1.count }
        let buffered = player.bufferedSecondsAhead
        let pace = RenderPace.shared.snapshot
        let behind = HeadStart.projectsUnderrun(
            remainingChars: remaining, firstChunkChars: chunks[k].count, bufferedAudio: buffered,
            pace: pace, rate: Double(player.playbackRate),
            workerBusyOther: source.workerStatus(paragraph: index) == .busyElsewhere)
        if behind {
            ListenTimingLog.log("render_behind", [
                "key": ListenTimingLog.shortKey(source.articleID), "p": index, "c": k,
                "buffered_s": (buffered * 10).rounded() / 10, "speed": ((pace.speed ?? 0) * 100).rounded() / 100,
                "remaining_chars": remaining,
            ])
        }
        return behind
    }

    /// Never silently skip: the engine could not produce this paragraph (or its remaining chunks), so
    /// speak the remainder with Apple TTS as a one-off unit. Only if that fails too do we move on
    /// — and say so in the debug overlay + timing log.
    private func fallbackToApple(_ source: ListenUnitSource, index: Int, fromChunk: Int, error: Error, epoch e: Int) async {
        pendingStartFraction = 0 // Apple units start at their chunk boundary
        let chunks = source.chunks(paragraph: index)
        let remainder = fromChunk < chunks.count && fromChunk > 0
            ? chunks[fromChunk...].joined(separator: " ")
            : TextChunker.normalize(source.paragraphs[index])
        let engine = source.engineName
        let reason: FallbackReason
        if case LocalSynthError.deferredInBackground = error {
            reason = .background
        } else if error is RenderFellBehind {
            reason = .behind
        } else {
            reason = .engineError
        }
        switch reason {
        case .background:
            ListenDebugLog.shared.append("p\(index) c\(fromChunk) not rendered yet, app in background → Apple TTS")
        case .behind:
            ListenDebugLog.shared.append("p\(index) c\(fromChunk) \(engine) behind playback → Apple TTS for this paragraph")
        case .engineError:
            ListenDebugLog.shared.append("p\(index) c\(fromChunk) \(engine) failed → Apple TTS (\(error.localizedDescription))")
        }
        if reason != .background, index + 1 < source.paragraphs.count {
            // Apple speaks this paragraph: the worker moves on to the next one now, instead of
            // finishing this one (which no longer plays) and falling behind again there. This one
            // is rendered later, from the top.
            source.focus(paragraph: index + 1)
        }
        let url = tempDir.appendingPathComponent("apple-\(e)-\(index)-\(fromChunk).caf")
        let t0 = ListenTimingLog.now()
        do {
            try await source.renderApple(remainder, to: url)
            guard e == epoch else {
                Self.deleteFallbackFile(url)
                return
            }
            ListenTimingLog.log("fallback_apple", ["p": index, "c": fromChunk, "live": true,
                                                   "chars": remainder.count, "ms": ListenTimingLog.ms(since: t0),
                                                   "engine": engine, "local_err": error.localizedDescription])
            let queued = ArticleAudioCache.hasAudio(at: url)
                && player.enqueue(.init(paragraphIndex: index, fileURL: url,
                                        source: .appleFallback(fromChunk: fromChunk, reason: reason)))
            if !queued { Self.deleteFallbackFile(url) }
        } catch {
            Self.deleteFallbackFile(url)
            ListenDebugLog.shared.append("SKIP p\(index): \(engine) and Apple TTS both failed (\(error.localizedDescription))")
            ListenTimingLog.log("skip", ["p": index, "err": error.localizedDescription])
        }
        guard e == epoch else { return }
        nextProduceIndex = index + 1
        nextProduceChunk = 0
    }

    private static func deleteFallbackFile(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func noteUnitKind(_ item: ChunkPlaybackQueue.Item) {
        if case .appleFallback(_, let reason) = item.source {
            currentAppleFallbackReason = reason
        } else {
            currentAppleFallbackReason = nil
        }
        guard AppRunState.shared.phase == .background else { return }
        switch item.source {
        case .baked, .stitched: backgroundStats.bakedParagraphs += 1
        case .chunk: backgroundStats.engineChunks += 1
        case .appleFallback: backgroundStats.appleFallbacks += 1
        }
        ListenTimingLog.log("bg_unit", [
            "key": ListenTimingLog.shortKey(source?.articleID), "p": item.paragraphIndex, "c": item.source.startChunk ?? -1,
            "kind": item.source.timingKind,
        ])
    }

    /// first_audio (after Play/seek) and buffering (Preparing next…) intervals.
    private func noteUnitStartedForTiming(_ item: ChunkPlaybackQueue.Item) {
        let from = item.source.timingKind
        if let t = speakRequestedAt {
            ListenTimingLog.log("first_audio", [
                "key": ListenTimingLog.shortKey(source?.articleID), "p": item.paragraphIndex,
                "c": item.source.startChunk ?? -1, "ms": ListenTimingLog.ms(since: t), "from": from,
            ])
            speakRequestedAt = nil
            starvedAt = nil
        } else if let t = starvedAt {
            ListenTimingLog.log("buffering", [
                "key": ListenTimingLog.shortKey(source?.articleID), "p": item.paragraphIndex,
                "c": item.source.startChunk ?? -1, "dur_ms": ListenTimingLog.ms(since: t), "from": from,
            ])
            starvedAt = nil
        }
    }
}
