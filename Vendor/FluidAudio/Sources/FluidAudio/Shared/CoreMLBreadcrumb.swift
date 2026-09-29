import Foundation

/// Reader patch (2026-09-25): crash attribution for Core ML predictions.
///
/// On iOS 26.4+ a Core ML prediction can die uncatchably inside libBNNS
/// (E5RT `BnnsCpuInferenceOperation`). E5RT executes on its own dispatch queue,
/// so the crash report does not show which model was running. Before each
/// prediction FluidAudio calls `mark(model:stage:detail:)`; the host app installs
/// a handler that durably records it (e.g. an atomically written file) so the
/// next launch can name the model and stage the process died in.
///
/// Instrumented: `G2PModel` (BART encoder / decoder, CPU-only) and every
/// `KokoroAneSynthesizer` stage. No handler installed = no cost beyond a lock.
public enum CoreMLBreadcrumb {
    public typealias Handler = @Sendable (_ model: String, _ stage: String, _ detail: String?) -> Void

    private static let box = HandlerBox()

    public static func setHandler(_ handler: Handler?) {
        box.set(handler)
    }

    public static func mark(model: String, stage: String, detail: String? = nil) {
        box.get()?(model, stage, detail)
    }
}

private final class HandlerBox: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: CoreMLBreadcrumb.Handler?

    func set(_ h: CoreMLBreadcrumb.Handler?) {
        lock.lock()
        handler = h
        lock.unlock()
    }

    func get() -> CoreMLBreadcrumb.Handler? {
        lock.lock()
        defer { lock.unlock() }
        return handler
    }
}
