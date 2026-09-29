import Foundation

/// Live render speed of the active local engine (audio seconds per wall second, "× real time"),
/// fed by every successful model call (`LocalChunkRenderer`). Thread-safe.
final class RenderPace: @unchecked Sendable {
    static let shared = RenderPace()

    private let lock = NSLock()
    private var ewmaSpeed: Double?
    private var ewmaChunkWall: Double?
    private var samples = 0
    /// Smoothing: recent calls dominate (thermal throttling / background clamps show up fast).
    private let alpha = 0.3

    struct Snapshot: Equatable, Sendable {
        /// × real time (nil until 2 calls were measured).
        var speed: Double?
        /// Typical wall seconds per call.
        var chunkWall: Double?
        var samples: Int
    }

    func record(audioSeconds: Double, wallSeconds: Double) {
        guard audioSeconds > 0.2, wallSeconds > 0 else { return }
        let s = audioSeconds / wallSeconds
        lock.withLock {
            ewmaSpeed = ewmaSpeed.map { $0 + alpha * (s - $0) } ?? s
            ewmaChunkWall = ewmaChunkWall.map { $0 + alpha * (wallSeconds - $0) } ?? wallSeconds
            samples += 1
        }
    }

    func reset() {
        lock.withLock { ewmaSpeed = nil; ewmaChunkWall = nil; samples = 0 }
    }

    var snapshot: Snapshot {
        lock.withLock { Snapshot(speed: samples >= 2 ? ewmaSpeed : nil, chunkWall: ewmaChunkWall, samples: samples) }
    }
}

/// Head-start rule (research 2026-09-24). Rendering at `speed`× real time while playback
/// consumes audio at `rate`×: to play `A` seconds of not-yet-rendered audio without a gap you
/// need a buffer of `B = A·(1 − speed/rate)` (0 when speed ≥ rate) plus the time to render the
/// first piece. Pure; unit-tested.
enum HeadStart {
    /// Seconds of audio per text character (Kokoro p95 ≈ 0.064 s/char, measured on device).
    static let audioSecondsPerChar = 0.064
    /// Tolerated gap before we switch a paragraph to Apple (a brief "Preparing next…" beats a
    /// voice change).
    static let toleranceSeconds = 2.0

    static func requiredBuffer(remainingAudio: Double, speed: Double, rate: Double, firstPieceAudio: Double) -> Double {
        guard speed > 0, rate > 0 else { return .infinity }
        let deficit = max(0, remainingAudio * (1 - speed / rate))
        // Rendering the first piece takes firstPieceAudio/speed wall seconds, during which
        // playback eats rate× that much buffered audio.
        return deficit + firstPieceAudio / speed * rate
    }

    /// Would rendering the rest of this paragraph starve playback by more than `tolerance`?
    /// - bufferedAudio: audio already queued ahead of the playhead (seconds).
    /// - workerBusyOther: the single worker is mid-call on something else (adds one call).
    static func projectsUnderrun(
        remainingChars: Int, firstChunkChars: Int, bufferedAudio: Double,
        pace: RenderPace.Snapshot, rate: Double, workerBusyOther: Bool,
        tolerance: Double = toleranceSeconds
    ) -> Bool {
        guard let speed = pace.speed, speed > 0 else { return false } // unknown pace: just wait
        let remaining = Double(remainingChars) * audioSecondsPerChar
        let first = Double(firstChunkChars) * audioSecondsPerChar
        var need = requiredBuffer(remainingAudio: remaining, speed: speed, rate: rate, firstPieceAudio: first)
        if workerBusyOther { need += (pace.chunkWall ?? first / speed) * rate }
        return need > bufferedAudio + tolerance
    }
}
