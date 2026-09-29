import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Foreground / background state that gates on-device Core ML synthesis.
///
/// iOS forbids GPU work in the background, and on iOS 26.4+ *every* Kokoro compute routing
/// still runs BNNS CPU ops that can crash (FluidAudio #844 — cpuOnly, cpuAndGPU and
/// ANE-with-CPU-tail all crashed; ANE-only is not available for all stages). So there is no
/// background-safe compute setting to switch to: **no local model call starts while the app is
/// in the background**. Listening continues from baked audio, and paragraphs that aren't
/// rendered yet are spoken with Apple TTS (see `GlobalSynthQueue`, docs/LISTEN_PLAYBACK.md).
///
/// - `active`: everything runs (live chunks + bake-ahead).
/// - `inactive` (Control Center, call banner, app switcher; also on the way to background):
///   only chunks a listener is waiting for; bake-ahead waits.
/// - `background`: no Core ML at all; live requests are deferred (→ Apple fallback).
///
/// Thread-safe: `LocalChunkRenderer` checks it off the main actor right before each call.
final class AppRunState: @unchecked Sendable {
    enum Phase: String, Sendable {
        case active, inactive, background
    }

    static let shared = AppRunState()
    /// Posted on the main thread with `object` = the instance whose phase changed.
    static let didChange = Notification.Name("AppRunState.didChange")

    private let lock = NSLock()
    private var _phase: Phase

    init(phase: Phase = .active) {
        _phase = phase
    }

    var phase: Phase { lock.withLock { _phase } }
    /// A local Core ML synthesis call may start now (never in the background).
    var allowsLocalModelCalls: Bool { phase != .background }
    /// Bake-ahead work (nobody waiting on it) may start a chunk now.
    var allowsBakeAhead: Bool { phase == .active }

    func set(_ new: Phase) {
        let changed: Bool = lock.withLock {
            defer { _phase = new }
            return _phase != new
        }
        guard changed else { return }
        let post = { NotificationCenter.default.post(name: Self.didChange, object: self) }
        if Thread.isMainThread { post() } else { DispatchQueue.main.async(execute: post) }
    }

    #if canImport(UIKit)
    private var tokens: [NSObjectProtocol] = []

    /// Mirror `UIApplication` state (once, at launch).
    @MainActor
    func observeApplication() {
        guard tokens.isEmpty else { return }
        switch UIApplication.shared.applicationState {
        case .active: set(.active)
        case .inactive: set(.inactive)
        case .background: set(.background)
        @unknown default: break
        }
        let nc = NotificationCenter.default
        let pairs: [(Notification.Name, Phase)] = [
            (UIApplication.didBecomeActiveNotification, .active),
            (UIApplication.willResignActiveNotification, .inactive),
            (UIApplication.didEnterBackgroundNotification, .background),
            (UIApplication.willEnterForegroundNotification, .inactive),
        ]
        tokens = pairs.map { name, phase in
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.set(phase) }
        }
    }
    #endif
}

#if canImport(UIKit)
/// `beginBackgroundTask` wrapper: a short grace period so work in flight when the app leaves the
/// foreground (a Core ML chunk + its CAF write, or an Apple-fallback render while the player is
/// starved) finishes instead of being suspended mid-way. Does NOT permit GPU work.
@MainActor
final class BackgroundGrace {
    let name: String
    private var id: UIBackgroundTaskIdentifier = .invalid

    init(name: String) {
        self.name = name
    }

    var isHeld: Bool { id != .invalid }

    func begin() {
        guard id == .invalid else { return }
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
        ListenTimingLog.log("bg_grace_begin", ["name": name, "ok": id != .invalid])
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
        ListenTimingLog.log("bg_grace_end", ["name": name])
    }
}
#endif
