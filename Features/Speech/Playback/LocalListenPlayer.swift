import AVFoundation
import Foundation

/// The on-device engine's file player and producer. Each play binds one `ListenUnitSource`; the
/// producer fills `ChunkPlaybackQueue` from it in reading order: rendered paragraphs, then chunks
/// as they are rendered. Where the engine can't give the next audio (it stopped or failed), the
/// player plays what is queued and stops there (`onStalled`); in the background, where nothing on
/// screen can say "Preparing next…", it pauses where the audio runs out before the next chunk is
/// rendered (`ListenStall.cantKeepUp`). Never skipping text and never in another voice. It reports unit starts, stalls and the
/// article's end; `LocalListenEngine` turns those into session events. The model and the render queue live behind the source. See docs/LISTEN_PLAYBACK.md.
@MainActor
final class LocalListenPlayer {
    private let player: ChunkPlaybackQueue
    private let runState: AppRunState
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
    /// Generation for starved-watchdog tasks; bumped whenever we leave play/resume paths.
    private var starveWatchGeneration = 0
    /// A unit has played since the last play or resume: running dry now is a gap in what was
    /// audible, not the wait for the first audio.
    private var playedSinceResume = false

    /// What the listener wants of the player, independent of the produce epoch: audio moving
    /// (`playing`: sounding, or waiting for its next unit), held (`paused`), or nothing.
    enum State { case stopped, playing, paused }
    private(set) var state = State.stopped

    /// Units played while the app was backgrounded, by source (listen debug panel).
    struct BackgroundPlayStats: Equatable {
        var bakedParagraphs = 0
        var engineChunks = 0
        var label: String { "baked \(bakedParagraphs), chunks \(engineChunks)" }
    }
    var backgroundStats = BackgroundPlayStats()

    /// A unit of this paragraph started playing.
    var onUnitStarted: ((Int) -> Void)?
    /// The article played out (all units played, nothing more to produce). Once per play.
    var onFinished: (() -> Void)?
    /// The player ran dry with more to come: it waits for the next unit.
    var onStarved: (() -> Void)?
    /// C129: rendering is paused for Retry (the engine stopped twice); nothing new renders.
    var rendersPausedForRetry: () -> Bool = { false }
    /// Playback reached audio the engine can't give now and stopped there, everything queued
    /// before it played. The engine pauses.
    var onStalled: ((ListenStall) -> Void)?
    /// The producer stopped at audio it can't get; report it when the buffer drains.
    private var heldStall: ListenStall?
    /// Sub-paragraph start: how far into the first unit of this play/seek to begin, as a
    /// fraction of its synth chunk. Consumed by the first enqueue of the start paragraph.
    private var pendingStartFraction: Double = 0
    /// Lead-in before an estimated sentence start (the in-chunk position is a character-based
    /// estimate; starting a hair early beats clipping the first word).
    static let subChunkLeadIn: TimeInterval = 0.25

    /// The current play waits for its engine's model to load: it wants audio, has none queued,
    /// and the engine isn't the loaded one (`ListenUnitSource.waitsForVoice`).
    var isWaitingForVoice: Bool {
        state == .playing && player.bufferedCount == 0 && source?.waitsForVoice == true
    }

    /// Article whose audio is playing right now (nil when paused / stopped).
    var playingArticleID: UUID? { state == .playing ? source?.articleID : nil }

    /// `player` is injectable so tests can end units without waiting for real audio; `runState` is
    /// the render queue's (the background's gap pause, and its units counted for the debug panel).
    init(player injected: ChunkPlaybackQueue? = nil, runState: AppRunState = .shared) {
        self.player = injected ?? ChunkPlaybackQueue(maxBuffered: 8)
        self.runState = runState

        player.onUnitStarted = { [weak self] item in
            guard let self else { return }
            self.noteUnitStartedForTiming(item)
            self.noteUnitKind(item)
            self.state = .playing
            self.playedSinceResume = true
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
            ListenDebugLog.shared.append("unit error, playing on: \(error.localizedDescription)")
        }
        player.onFinished = { [weak self] in
            // The only place the article ends (see `ChunkPlaybackQueue.endOfInput`); once per play.
            guard let self, self.state == .playing else { return }
            self.state = .stopped
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

    // MARK: - Listen debug
    var debugEpoch: Int { epoch }
    var debugCurrentCAF: String { player.currentFileName ?? "—" }
    var debugSecondsSinceEnqueue: Double? { player.secondsSinceLastEnqueue }
    var debugLastHandoffGapMs: Double { player.lastHandoffGapMs }
    var debugLastHandoffWasPrimed: Bool { player.lastHandoffWasPrimed }
    var debugStarveEventCount: Int { player.starveEventCount }

    /// Play `source` from synth chunk `chunk` of paragraph `index`, `fractionInChunk` (0…1) into
    /// it (scrubbed to a sentence). Rendered there: it plays at once. Unrendered: its chunk is
    /// asked for, and the render queue's worker renders it first, loading the engine when it
    /// isn't loaded (`isWaitingForVoice` meanwhile).
    func play(_ source: ListenUnitSource, from index: Int, chunk: Int, fractionInChunk: Double) {
        stop()
        let paragraphs = source.paragraphs
        let start = max(0, min(index, max(paragraphs.count - 1, 0)))
        self.source = source
        nextProduceIndex = start
        state = .playing
        nextProduceChunk = max(0, chunk)
        pendingStartFraction = min(0.99, max(0, fractionInChunk))
        epoch += 1
        let e = epoch
        player.awaitingMore = true
        speakRequestedAt = ListenTimingLog.now()
        starvedAt = nil
        playedSinceResume = false
        ListenDebugLog.shared.append("speak start=\(start) c\(chunk) +\(Int(fractionInChunk * 100))% count=\(paragraphs.count) epoch=\(e)")
        ensureProducerRunning(epoch: e)
    }

    func pause() {
        heldStall = nil
        starvedAt = nil
        speakRequestedAt = nil
        state = .paused
        player.pause()
        // Producer may finish the in-flight unit and enqueue; player stays soft-paused.
    }

    func resume() {
        state = .playing
        playedSinceResume = false
        player.resume()
        // Same epoch — do not cancel in-flight produce or skip units.
        player.awaitingMore = nextProduceIndex < paragraphs.count
        ensureProducerRunning(epoch: epoch)
    }

    func stop() {
        source = nil
        heldStall = nil
        epoch += 1
        starveWatchGeneration += 1
        producerTask?.cancel()
        producerTask = nil
        player.clear()
        state = .stopped
        nextProduceIndex = 0
        nextProduceChunk = 0
        pendingStartFraction = 0
        speakRequestedAt = nil
        starvedAt = nil
    }

    /// Listen speed: a time-stretch on the player, applied in place. Audio is always
    /// rendered at 1×, so nothing is re-rendered or re-queued
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
        // Held at audio it can't get: what is queued plays out, then the stall is reported. Asking
        // again on every unit's end would only repeat the failed call.
        guard producerTask == nil, heldStall == nil else { return }
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
        if let stall = heldStall {
            heldStall = nil
            onStalled?(stall)
            return
        }
        // In the background the audio ran out before the next chunk was rendered: pause at the
        // gap. Its request stays pending, and ▶ plays on from it in the same voice.
        if runState.phase == .background, state == .playing, playedSinceResume {
            ListenTimingLog.log("playback_held", ["p": nextProduceIndex, "c": nextProduceChunk, "reason": "cant_keep_up",
                                                  "buffered": 0])
            onStalled?(.cantKeepUp)
            return
        }
        if starvedAt == nil, state == .playing { starvedAt = ListenTimingLog.now() }
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
            guard self.state != .stopped else { return }
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
                ListenDebugLog.shared.append("starved: producing again from p\(self.nextProduceIndex)")
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
                // Rendered paragraph (all chunks stitched) → play the CAF, from chunk
                // `nextProduceChunk`'s boundary. Needs no model.
                if let rendered = source.renderedParagraph(index) {
                    let k = nextProduceChunk
                    nextProduceIndex = index + 1
                    nextProduceChunk = 0
                    let fileStart = rendered.chunkDurations?.prefix(k).reduce(0, +) ?? 0
                    let start = consumeStartTime(fileDuration: rendered.duration, chunk: k, fileStartTime: fileStart,
                                                 wholeParagraph: true, chunkDurations: rendered.chunkDurations)
                    player.enqueue(.init(paragraphIndex: index, fileURL: rendered.url,
                                         source: k == 0 ? .baked : .stitched(fromChunk: k),
                                         duration: rendered.duration, startTime: start,
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
                // C129: rendering paused for Retry and this isn't rendered: play what is queued,
                // then pause here.
                if rendersPausedForRetry(), !source.isChunkReady(paragraph: index, chunk: k) {
                    hold(.engineStopped, paragraph: index, chunk: k)
                    return
                }
                do {
                    let resolution = try await source.chunk(paragraph: index, chunk: k)
                    guard e == epoch else { return }
                    let duration = await Self.duration(of: resolution.fileURL)
                    guard e == epoch else { return }
                    switch resolution {
                    case .chunk(let url):
                        let start = consumeStartTime(fileDuration: duration, chunk: k, fileStartTime: 0,
                                                     wholeParagraph: false, chunkDurations: nil)
                        player.enqueue(.init(paragraphIndex: index, fileURL: url, source: .chunk(k), duration: duration,
                                             startTime: start))
                        if k + 1 >= chunks.count {
                            nextProduceIndex = index + 1
                            nextProduceChunk = 0
                        } else {
                            nextProduceChunk = k + 1
                        }
                    case .paragraph(let url, let startTime):
                        // Paragraph finished (scratch gone) — play the rest from the stitched CAF.
                        let durations = source.chunkDurations(paragraph: index)
                        let start = consumeStartTime(fileDuration: duration, chunk: k, fileStartTime: startTime,
                                                     wholeParagraph: true, chunkDurations: durations)
                        player.enqueue(.init(paragraphIndex: index, fileURL: url, source: .stitched(fromChunk: k),
                                             duration: duration, startTime: start, chunkDurations: durations))
                        nextProduceIndex = index + 1
                        nextProduceChunk = 0
                    }
                } catch is CancellationError {
                    return
                } catch {
                    guard e == epoch else { return }
                    ListenDebugLog.shared.append("p\(index) c\(k) \(source.engineName) gave no audio: \(error.localizedDescription)")
                    hold(.engineStopped, paragraph: index, chunk: k)
                    return
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
    /// (`chunkDurations`, the paragraph file's index entry). `fileDuration`: the unit's file.
    private func consumeStartTime(fileDuration: TimeInterval, chunk: Int, fileStartTime: TimeInterval,
                                  wholeParagraph: Bool, chunkDurations: [TimeInterval]?) -> TimeInterval {
        let fraction = pendingStartFraction
        pendingStartFraction = 0
        guard fraction > 0 else { return fileStartTime }
        let chunkDuration: TimeInterval
        if wholeParagraph {
            if let durations = chunkDurations, durations.indices.contains(chunk) {
                chunkDuration = durations[chunk]
            } else {
                chunkDuration = max(0, fileDuration - fileStartTime) // single chunk: the whole file
            }
        } else {
            chunkDuration = fileDuration
        }
        return max(fileStartTime, fileStartTime + chunkDuration * fraction - Self.subChunkLeadIn)
    }

    /// A unit file's length, read off the main actor (`LocalPCMWriter.duration`).
    private static func duration(of url: URL) async -> TimeInterval {
        await Task.detached(priority: .userInitiated) { LocalPCMWriter.duration(of: url) }.value
    }

    /// The next audio (chunk `chunk` of `paragraph`) can't be had now: playback goes on through
    /// what is queued and stops there (`onStalled`, at once when nothing is queued). The produce
    /// cursor stays on it, so a resume asks for it again.
    private func hold(_ stall: ListenStall, paragraph: Int, chunk: Int) {
        ListenTimingLog.log("playback_held", ["p": paragraph, "c": chunk, "reason": String(describing: stall),
                                              "buffered": player.bufferedCount])
        if player.bufferedCount == 0 { onStalled?(stall) } else { heldStall = stall }
    }

    private func noteUnitKind(_ item: ChunkPlaybackQueue.Item) {
        guard runState.phase == .background else { return }
        switch item.source {
        case .baked, .stitched: backgroundStats.bakedParagraphs += 1
        case .chunk: backgroundStats.engineChunks += 1
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
