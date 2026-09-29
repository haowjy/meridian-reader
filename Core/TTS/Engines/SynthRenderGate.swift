import Foundation

/// FIFO async mutex for on-device model work. `shared` is app-wide: live listen, background
/// bake, model loads and the engine probe never run two Core ML renders at once (concurrent
/// E5RT/BNNS use is a known corruption trigger, FluidAudio #661).
actor SynthRenderGate {
    static let shared = SynthRenderGate()

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
