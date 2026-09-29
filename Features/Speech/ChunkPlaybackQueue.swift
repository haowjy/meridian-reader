import AVFoundation
import Foundation

/// Dumb local-engine unit player. Plays Ready CAF files only. Pause keeps `currentTime`.
/// Prefetches the next `AVAudioPlayer` while the current unit plays so handoff is
/// near-zero for baked (and buffered live) paragraphs. See docs/LISTEN_PLAYBACK.md.
@MainActor
final class ChunkPlaybackQueue: NSObject, AVAudioPlayerDelegate {
    struct Item {
        let paragraphIndex: Int
        let fileURL: URL
        /// Synth chunk within the paragraph (nil = whole baked paragraph CAF).
        var chunkIndex: Int? = nil
        /// Start offset into `fileURL` (resume at a chunk boundary of a stitched paragraph).
        var startTime: TimeInterval = 0
        /// `fileURL` is the whole stitched paragraph (baked CAF), even when `chunkIndex` is set.
        var isWholeParagraph = false

        /// Same audio? A whole-paragraph item overlaps every chunk of that paragraph.
        func overlaps(_ other: Item) -> Bool {
            guard paragraphIndex == other.paragraphIndex else { return false }
            guard let a = chunkIndex, let b = other.chunkIndex else { return true }
            return a == b
        }
    }

    private var queue: [Item] = []
    private var player: AVAudioPlayer?
    private var current: Item?
    /// Prefetched next player (prepared while current plays).
    private var primedPlayer: AVAudioPlayer?
    private var primedItem: Item?
    private let maxBuffered: Int
    private var softPaused = false
    /// Listen speed (Nav I). Applied in place with `AVAudioPlayer.enableRate` / `rate`, a
    /// pitch-preserving time stretch: changing it never re-queues, restarts or re-renders
    /// anything — the current unit keeps going from the same spot at the new speed.
    private(set) var playbackRate: Float = 1

    /// Producer still expects to enqueue more. Empty queue + !awaitingMore ⇒ finished.
    var awaitingMore = false

    var onUnitStarted: ((Item) -> Void)?
    var onFinished: (() -> Void)?
    var onStarved: (() -> Void)?
    var onError: ((Error) -> Void)?
    /// Fired when a Ready unit finishes (successfully or not) so the producer can refill.
    var onUnitEnded: (() -> Void)?

    // MARK: - Gap / debug telemetry (Listen debug panel)

    private(set) var lastEnqueueAt: Date?
    private(set) var lastHandoffGapMs: Double = 0
    private(set) var lastStarveAt: Date?
    private(set) var starveEventCount = 0
    private var unitEndedAt: Date?
    /// True when finish arrived and next CAF was already primed.
    private(set) var lastHandoffWasPrimed = false

    /// Deeper than early redesign (3): local synth can exceed short-paragraph duration,
    /// so keep more Ready CAF ahead of the playhead to avoid audible gaps.
    init(maxBuffered: Int = 8) {
        self.maxBuffered = maxBuffered
    }

    var bufferedCount: Int { queue.count + (current == nil ? 0 : 1) }

    /// Seconds of audio queued ahead of the playhead (rest of the current unit + queued units).
    var bufferedSecondsAhead: TimeInterval {
        var total = 0.0
        if let player, current != nil { total += max(0, player.duration - player.currentTime) }
        for item in queue { total += max(0, fileDuration(item.fileURL) - item.startTime) }
        return total
    }

    private var durationCache: [String: TimeInterval] = [:]

    private func fileDuration(_ url: URL) -> TimeInterval {
        if let d = durationCache[url.path] { return d }
        guard let f = try? AVAudioFile(forReading: url), f.fileFormat.sampleRate > 0 else { return 0 }
        let d = Double(f.length) / f.fileFormat.sampleRate
        if durationCache.count > 256 { durationCache.removeAll() }
        durationCache[url.path] = d
        return d
    }
    var canAcceptMore: Bool { bufferedCount < maxBuffered }
    var isAudible: Bool { player?.isPlaying == true }
    var isSoftPaused: Bool { softPaused }
    var currentParagraphIndex: Int? { current?.paragraphIndex }
    var hasQueuedOrCurrent: Bool { current != nil || !queue.isEmpty }
    var currentFileName: String? { current?.fileURL.lastPathComponent }
    var secondsSinceLastEnqueue: Double? {
        guard let lastEnqueueAt else { return nil }
        return Date().timeIntervalSince(lastEnqueueAt)
    }

    func enqueue(_ item: Item) {
        // Never play the same paragraph/chunk twice in one stretch (producer races / re-kicks).
        if let current, current.overlaps(item) { return }
        if queue.contains(where: { $0.overlaps(item) }) { return }
        queue.append(item)
        lastEnqueueAt = Date()
        ListenDebugLog.shared.append(
            "enqueue p\(item.paragraphIndex)\(item.chunkIndex.map { "c\($0)" } ?? "") buf=\(bufferedCount) primed=\(primedPlayer != nil)"
        )
        if current == nil, !softPaused {
            playNext()
        } else {
            primeUpcomingIfNeeded()
        }
    }

    /// Indices already Ready in the player (current + buffered).
    var bufferedParagraphIndices: Set<Int> {
        var ids = Set(queue.map(\.paragraphIndex))
        if let current { ids.insert(current.paragraphIndex) }
        return ids
    }

    /// Change speed in place: the playing unit continues mid-sentence at `rate`; the primed and
    /// later units start at it. Survives `clear()` (speed is a setting, not queue state).
    func setRate(_ rate: Float) {
        let clamped = min(2, max(0.5, rate))
        playbackRate = clamped
        if let player { applyRate(player) }
        if let primedPlayer { applyRate(primedPlayer) }
    }

    /// `enableRate` must be set before `prepareToPlay` / `play`; `rate` can change any time.
    private func applyRate(_ p: AVAudioPlayer) {
        if !p.enableRate { p.enableRate = true }
        if p.rate != playbackRate { p.rate = playbackRate }
    }

    /// Rate of the unit playing now (nil when nothing is loaded) — tests / debug.
    var currentPlayerRate: Float? { player?.rate }
    /// Where the current unit is: item, seconds into the file, file duration (nil when idle).
    var currentPosition: (item: Item, time: TimeInterval, duration: TimeInterval)? {
        guard let player, let current else { return nil }
        return (current, player.currentTime, player.duration)
    }

    func pause() {
        softPaused = true
        player?.pause()
    }

    func resume() {
        softPaused = false
        if let player, current != nil {
            player.play()
        } else if current == nil {
            playNext()
        }
    }

    /// Remove queued (not yet playing) items from the first one matching `predicate` onward.
    /// Returns that first removed item. The current unit keeps playing.
    @discardableResult
    func dropQueued(fromFirstWhere predicate: (Item) -> Bool) -> Item? {
        guard let i = queue.firstIndex(where: predicate) else { return nil }
        let first = queue[i]
        queue.removeSubrange(i...)
        if i == 0 { discardPrime() } // the primed player was built for queue.first
        return first
    }

    func clear() {
        softPaused = false
        awaitingMore = false
        player?.stop()
        player = nil
        current = nil
        discardPrime()
        queue.removeAll()
        unitEndedAt = nil
        durationCache.removeAll()
    }

    private func discardPrime() {
        primedPlayer?.stop()
        primedPlayer = nil
        primedItem = nil
    }

    /// Build + `prepareToPlay` the next CAF while the current one is still audible.
    private func primeUpcomingIfNeeded() {
        guard primedPlayer == nil, let peek = queue.first else { return }
        do {
            let p = try AVAudioPlayer(contentsOf: peek.fileURL)
            guard p.duration > 0.05 else { return }
            p.delegate = self
            applyRate(p)
            if peek.startTime > 0 { p.currentTime = min(peek.startTime, max(0, p.duration - 0.05)) }
            p.prepareToPlay()
            primedPlayer = p
            primedItem = peek
        } catch {
            // Leave unprimed; playNext will surface the error.
            ListenDebugLog.shared.append("prime fail p\(peek.paragraphIndex): \(error.localizedDescription)")
        }
    }

    private func playNext() {
        guard !softPaused else { return }
        guard !queue.isEmpty else {
            current = nil
            player = nil
            discardPrime()
            if awaitingMore {
                starveEventCount += 1
                lastStarveAt = Date()
                ListenDebugLog.shared.append("STARVE awaitingMore=true buf=0")
                onStarved?()
            } else {
                onFinished?()
            }
            return
        }

        // Prefer a primed player that still matches queue head — avoids disk+decode on the
        // finish callback (the main inter-paragraph silence for baked articles).
        let head = queue[0]
        let usedPrime: Bool
        let p: AVAudioPlayer
        let item: Item
        if let primedPlayer, let primedItem, primedItem.paragraphIndex == head.paragraphIndex,
           primedItem.chunkIndex == head.chunkIndex, primedItem.startTime == head.startTime,
           primedItem.fileURL == head.fileURL {
            queue.removeFirst()
            item = primedItem
            p = primedPlayer
            self.primedPlayer = nil
            self.primedItem = nil
            usedPrime = true
        } else {
            discardPrime()
            item = queue.removeFirst()
            do {
                p = try AVAudioPlayer(contentsOf: item.fileURL)
                applyRate(p)
                if item.startTime > 0 { p.currentTime = min(item.startTime, max(0, p.duration - 0.05)) }
            } catch {
                onError?(error)
                current = nil
                player = nil
                onUnitEnded?()
                playNext()
                return
            }
            usedPrime = false
        }

        guard p.duration > 0.05 else {
            onError?(NSError(
                domain: "ChunkPlaybackQueue",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Empty or corrupt CAF at paragraph \(item.paragraphIndex)"]
            ))
            current = nil
            player = nil
            onUnitEnded?()
            playNext()
            return
        }

        if let unitEndedAt {
            lastHandoffGapMs = Date().timeIntervalSince(unitEndedAt) * 1000
            lastHandoffWasPrimed = usedPrime
            ListenDebugLog.shared.append(
                String(format: "handoff p%d gap=%.0fms primed=%@", item.paragraphIndex, lastHandoffGapMs, usedPrime ? "yes" : "no")
            )
        }
        unitEndedAt = nil

        current = item
        p.delegate = self
        applyRate(p) // speed may have changed since the prime
        player = p
        onUnitStarted?(item)
        if softPaused { return }
        p.play()
        primeUpcomingIfNeeded()
    }

    /// Finish path — prefer sync MainActor handoff so we do not yield a runloop tick of silence.
    private func handleUnitFinished() {
        unitEndedAt = Date()
        current = nil
        player = nil
        onUnitEnded?()
        playNext()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // AVAudioPlayerDelegate is invoked on the main thread; avoid `Task { @MainActor }`
        // which schedules asynchronously and creates a measurable inter-paragraph gap.
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                self.handleUnitFinished()
            }
        } else {
            Task { @MainActor in
                self.handleUnitFinished()
            }
        }
    }
}
