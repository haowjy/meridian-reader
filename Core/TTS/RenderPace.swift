import Foundation

/// Live render speed of the active local engine (audio seconds per wall second, "× real time"),
/// fed by every listener's model call (`LocalChunkRenderer`), for the debug panel. Thread-safe.
final class RenderPace: @unchecked Sendable {
    static let shared = RenderPace()

    private let lock = NSLock()
    private var ewmaSpeed: Double?
    private var samples = 0
    /// Smoothing: recent calls dominate (thermal throttling / background clamps show up fast).
    private let alpha = 0.3

    struct Snapshot: Equatable, Sendable {
        /// × real time (nil until 2 calls were measured).
        var speed: Double?
        var samples: Int
    }

    func record(audioSeconds: Double, wallSeconds: Double) {
        guard audioSeconds > 0.2, wallSeconds > 0 else { return }
        let s = audioSeconds / wallSeconds
        lock.withLock {
            ewmaSpeed = ewmaSpeed.map { $0 + alpha * (s - $0) } ?? s
            samples += 1
        }
    }

    func reset() {
        lock.withLock { ewmaSpeed = nil; samples = 0 }
    }

    var snapshot: Snapshot {
        lock.withLock { Snapshot(speed: samples >= 2 ? ewmaSpeed : nil, samples: samples) }
    }
}
