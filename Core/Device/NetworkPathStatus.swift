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

    /// Why a large download asks before using the current path.
    enum LargeDownloadCaution: Equatable {
        /// Low Data Mode is on (on Wi‑Fi or cellular): the user asked apps to use less data.
        case lowDataMode
        /// Cellular (or another expensive path, a hotspot).
        case cellular
    }

    /// Why a large download should ask before using the current path; nil on Wi‑Fi (and
    /// Ethernet) with Low Data Mode off. Offline is nil too, so the download's own error surfaces.
    var largeDownloadCaution: LargeDownloadCaution? {
        lock.lock()
        let p = path
        lock.unlock()
        guard p.status == .satisfied else { return nil }
        if p.isConstrained { return .lowDataMode }
        return p.isExpensive ? .cellular : nil
    }
}
