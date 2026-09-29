import BackgroundTasks
import Darwin
import Foundation
import os
#if canImport(UIKit)
import UIKit
#endif

/// Debug-only process metrics for the CPU route benchmark / soak.
enum CPURouteMetrics {
    /// `phys_footprint` (what jetsam counts) and the process-lifetime peak, bytes.
    static func footprint() -> (current: UInt64, peak: UInt64) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return (0, 0) }
        return (info.phys_footprint, info.ledger_phys_footprint_peak > 0 ? UInt64(info.ledger_phys_footprint_peak) : 0)
    }

    /// Bytes the app can still allocate before hitting its jetsam limit (0 if unknown).
    static func availableMemory() -> UInt64 {
        #if os(iOS)
        return UInt64(os_proc_available_memory())
        #else
        return 0
        #endif
    }

    /// User + system CPU time of the whole process (all threads, incl. ORT's pool), seconds.
    static func cpuSeconds() -> Double {
        var r = rusage()
        getrusage(RUSAGE_SELF, &r)
        func s(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000 }
        return s(r.ru_utime) + s(r.ru_stime)
    }

    static func mb(_ bytes: UInt64) -> Double { (Double(bytes) / 1_048_576 * 10).rounded() / 10 }

    static var thermal: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    static var device: String { DeviceChipGate.machineIdentifier }

    static var os: String {
        #if canImport(UIKit)
        return "iOS \(UIDevice.current.systemVersion) (\(ProcessInfo.processInfo.operatingSystemVersionString))"
        #else
        return ProcessInfo.processInfo.operatingSystemVersionString
        #endif
    }

    static func qosLabel(_ q: DispatchQoS.QoSClass) -> String {
        switch q {
        case .userInteractive: return "userInteractive"
        case .userInitiated: return "userInitiated"
        case .default: return "default"
        case .utility: return "utility"
        case .background: return "background"
        default: return "unspecified"
        }
    }

    /// Run `body` synchronously on a global queue of `qos` (so ORT's pool, created inside,
    /// inherits that QoS) and await the result.
    static func onQueue<T>(_ qos: DispatchQoS.QoSClass, _ body: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: qos).async {
                cont.resume(with: Result { try body() })
            }
        }
    }
}

/// Polls `phys_footprint` every 100 ms while a render runs; reports the max and min headroom.
final class FootprintSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var maxBytes: UInt64 = 0
    private var minAvail: UInt64 = .max
    private var timer: DispatchSourceTimer?

    func start() {
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        t.schedule(deadline: .now(), repeating: .milliseconds(100))
        t.setEventHandler { [weak self] in self?.sample() }
        timer = t
        t.resume()
    }

    private func sample() {
        let fp = CPURouteMetrics.footprint().current
        let avail = CPURouteMetrics.availableMemory()
        lock.withLock {
            maxBytes = max(maxBytes, fp)
            if avail > 0 { minAvail = min(minAvail, avail) }
        }
    }

    func stop() -> (maxFootprint: UInt64, minAvailable: UInt64) {
        timer?.cancel()
        timer = nil
        sample()
        return lock.withLock { (maxBytes, minAvail == .max ? 0 : minAvail) }
    }
}

/// `Application Support/ListenTiming/cpubench.jsonl` — one JSON object per line (benchmark
/// configs, soak chunks, start/end markers). Pulled with the same devicectl command as timing.jsonl.
enum CPUBenchLog {
    private static let queue = DispatchQueue(label: "reader.cpubench-log", qos: .utility)
    static var fileURL: URL { ListenTimingLog.directory.appendingPathComponent("cpubench.jsonl") }

    static func append(_ event: String, _ fields: [String: Any]) {
        var obj = fields
        obj["ev"] = event
        obj["t"] = (Date().timeIntervalSince1970 * 1000).rounded() / 1000
        obj["iso"] = ISO8601DateFormatter().string(from: Date())
        queue.async {
            guard JSONSerialization.isValidJSONObject(obj),
                  let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else { return }
            let fm = FileManager.default
            try? fm.createDirectory(at: ListenTimingLog.directory, withIntermediateDirectories: true)
            if !fm.fileExists(atPath: fileURL.path) { fm.createFile(atPath: fileURL.path, contents: nil) }
            guard let h = try? FileHandle(forWritingTo: fileURL) else { return }
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: data + Data("\n".utf8))
        }
    }
}

/// Launch-time capability probes (debug panel + timing log).
@MainActor
enum CPURouteProbes {
    /// `BGTaskScheduler.supportedResources.contains(.gpu)`; nil below iOS 26.
    private(set) static var backgroundGPUSupported: Bool?
    private(set) static var backgroundGPULabel = "not checked"

    static func logAtLaunch() {
        if #available(iOS 26.0, *) {
            backgroundGPUSupported = BGTaskScheduler.supportedResources.contains(.gpu)
        }
        backgroundGPULabel = backgroundGPUSupported.map { $0 ? "yes" : "no" } ?? "n/a (iOS < 26)"
        ListenTimingLog.log("probe_bg_gpu", [
            "supported": backgroundGPUSupported.map { $0 as Any } ?? NSNull(),
            "device": CPURouteMetrics.device, "os": CPURouteMetrics.os,
        ])
        ListenDebugLog.shared.append("Probe: BGTaskScheduler.supportedResources.contains(.gpu) = \(backgroundGPULabel)")
    }
}
