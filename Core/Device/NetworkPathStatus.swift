import Foundation
import Network

/// Live network path for large on-device model downloads: Wi‑Fi vs cellular / Low Data Mode.
/// `NWPathMonitor` on a dedicated queue; flags are read on any thread.
final class NetworkPathStatus: @unchecked Sendable {
    static let shared = NetworkPathStatus()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "reader.network-path")
    private let lock = NSLock()
    private var path: NWPath

    private init() {
        path = monitor.currentPath
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock()
            self.path = path
            self.lock.unlock()
        }
        monitor.start(queue: queue)
    }

    /// True when a large download should ask before using the current path (cellular or Low Data Mode).
    /// Wi‑Fi (and Ethernet) with Low Data Mode off does not prompt. Offline still returns false so
    /// the download's own error surfaces.
    var shouldPromptForLargeDownload: Bool {
        lock.lock()
        let p = path
        lock.unlock()
        guard p.status == .satisfied else { return false }
        return p.isExpensive || p.isConstrained
    }
}
