import Foundation
import Network

/// Live network path for large on-device model downloads: Wi‑Fi vs cellular / Low Data Mode.
/// `NWPathMonitor` on a dedicated queue; flags are read on any thread. The monitor's path before
/// its first update says nothing (it reads unsatisfied), so a decision waits for that update.
final class NetworkPathStatus: @unchecked Sendable {
    static let shared = NetworkPathStatus()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "reader.network-path")
    private let lock = NSLock()
    /// nil until the monitor's first update.
    private var path: NWPath?
    /// Decisions waiting for the first update, each resumed exactly once: by the update or by its
    /// own timeout, whichever comes first takes it out.
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock()
            self.path = path
            let ready = self.waiters.values
            self.waiters = [:]
            self.lock.unlock()
            for waiter in ready { waiter.resume() }
        }
        monitor.start(queue: queue)
    }

    /// Why a large download asks before using the current path.
    enum LargeDownloadCaution: Equatable {
        /// Low Data Mode is on (on Wi‑Fi or cellular): the user asked apps to use less data.
        case lowDataMode
        /// Cellular (or another expensive path, a hotspot).
        case cellular
        /// The path didn't report in time: it may be either, so it asks.
        case unknown
    }

    /// Why a large download should ask before using the current path; nil on Wi‑Fi (and
    /// Ethernet) with Low Data Mode off. Offline is nil too, so the download's own error surfaces.
    /// Waits for the monitor's first update, up to `timeout` (a cancelled caller stops waiting at
    /// once); a path still unknown then asks (`unknown`).
    func largeDownloadCaution(timeout: Duration = .seconds(1)) async -> LargeDownloadCaution? {
        if let path = currentPath { return Self.caution(of: path) }
        await firstUpdate(timeout: timeout)
        guard let path = currentPath else { return .unknown }
        return Self.caution(of: path)
    }

    private var currentPath: NWPath? {
        lock.lock()
        defer { lock.unlock() }
        return path
    }

    /// Returns at the monitor's first update (at once when it came), after `timeout`, or when the
    /// caller is cancelled.
    private func firstUpdate(timeout: Duration) async {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (waiter: CheckedContinuation<Void, Never>) in
                lock.lock()
                if path != nil || Task.isCancelled {
                    lock.unlock()
                    waiter.resume()
                    return
                }
                waiters[id] = waiter
                lock.unlock()
                let (seconds, attoseconds) = timeout.components
                queue.asyncAfter(deadline: .now() + Double(seconds) + Double(attoseconds) / 1e18) { [weak self] in
                    self?.resumeWaiter(id)
                }
            }
        } onCancel: {
            resumeWaiter(id)
        }
    }

    /// A waiter's timeout or cancel: resumes it unless the update (or the other) already did.
    private func resumeWaiter(_ id: UUID) {
        lock.lock()
        let waiter = waiters.removeValue(forKey: id)
        lock.unlock()
        waiter?.resume()
    }

    private static func caution(of path: NWPath) -> LargeDownloadCaution? {
        guard path.status == .satisfied else { return nil }
        if path.isConstrained { return .lowDataMode }
        return path.isExpensive ? .cellular : nil
    }
}
