import Foundation

/// The CPU host's ONNX session, built at the thread count a call asks for. ONNX Runtime fixes a
/// session's intra-op thread count when the session is created (no per-run setting), so a call
/// asking for another count rebuilds the session first: `KokoroCPUHost` asks per call, from the
/// app phase (`KokoroRouteSettings.onnxThreads`), so the switch happens between chunks, under the
/// render gate. The old session is released before the new one is built: the model is never
/// resident twice. Generic over the session so the switching is unit-tested without the model.
final class KokoroONNXSessionSlot<Session: AnyObject>: @unchecked Sendable {
    typealias Make = @Sendable (_ threads: Int) async throws -> Session

    private let lock = NSLock()
    private let make: Make
    private var session: Session?
    private var builtThreads = 0

    init(make: @escaping Make) {
        self.make = make
    }

    /// Thread count of the session held now (nil: none).
    var threads: Int? { lock.withLock { session == nil ? nil : builtThreads } }

    /// Build the session at `threads` (the host's load), replacing any held one.
    func load(threads: Int) async throws {
        drop()
        let built = try await make(threads)
        lock.withLock {
            session = built
            builtThreads = threads
        }
    }

    func drop() {
        lock.withLock { session = nil }
    }

    /// The session for a call at `threads`, rebuilt first when it was built with another count.
    /// `rebuiltFrom` is the old count after a rebuild. Throws when nothing is loaded, or when the
    /// rebuild fails (the slot is then empty until the next `load`).
    func session(threads wanted: Int) async throws -> (session: Session, rebuiltFrom: Int?) {
        if let current = lock.withLock({ builtThreads == wanted ? session : nil }) { return (current, nil) }
        // Let go of the old session here, holding no reference to it, before building the new one.
        let old: Int = try lock.withLock {
            guard session != nil else { throw LocalSynthError.engineUnavailable("ONNX session not loaded") }
            session = nil
            return builtThreads
        }
        let built = try await make(wanted)
        lock.withLock {
            session = built
            builtThreads = wanted
        }
        return (built, old)
    }
}
