import Foundation

/// FIFO async mutex for on-device model work, one per lane (`of(_:)`): live listening, rendering
/// ahead, model loads and the diagnostics never run two calls on one lane at once (concurrent
/// E5RT/BNNS use is a known corruption trigger, FluidAudio #661).
actor SynthRenderGate {
    /// The gate of `lane`.
    static func of(_ lane: Lane) -> SynthRenderGate { gates[lane]! }

    /// One per declared lane, for the life of the process.
    private static let gates = Dictionary(uniqueKeysWithValues: Lane.allCases.map { ($0, SynthRenderGate()) })

    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !busy {
            busy = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            busy = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
