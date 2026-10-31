import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// The app's phase (active / inactive / background), mirrored from `UIApplication`. The render
/// policy reads it (`RenderSituation.phase`): fewer threads in the background, and calls there
/// only while audio plays; the crash guard records it in each call's marker.
///
/// - `active`: on screen.
/// - `inactive` (Control Center, call banner, app switcher; also on the way to background): as
///   in front.
/// - `background`: the app runs only while audio plays (or a short `BackgroundGrace`).
///
/// Thread-safe: read off the main actor too.
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
/// foreground (a model call + its CAF write) finishes instead of being suspended mid-way.
@MainActor
final class BackgroundGrace {
    let name: String
    private var id: UIBackgroundTaskIdentifier = .invalid

    init(name: String) {
        self.name = name
    }

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
