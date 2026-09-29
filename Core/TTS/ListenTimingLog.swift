import Foundation

/// Append-only JSONL timing log for Listen / local-engine latency analysis.
///
/// File: `Application Support/ListenTiming/timing.jsonl` (rotates to `timing.1.jsonl` at ~2 MB,
/// so at most ~4 MB on disk). Always on — events are small and infrequent (per synth call,
/// per play/buffering transition). Pull it off the phone with:
///
///     xcrun devicectl device copy from --device <id> --domain-type appDataContainer \
///       --domain-identifier com.jimmyyao.Reader \
///       --source "Library/Application Support/ListenTiming" --destination ./ListenTiming
///
/// Each line: `{"t": <unix seconds>, "ev": "<event>", ...fields}`. Events:
/// `app_launch`, `kokoro_init_start/end`, `reader_open`, `play`, `first_audio`,
/// `synth` (one engine call: chars, wall_ms, audio_s, ok, err), `chunk_ready`, `paragraph_ready`,
/// `unit_wait` (producer waited for a chunk: wait_ms, worker_busy_other, other_key/p),
/// `buffering` (Preparing next interval: p, dur_ms), `fallback_apple`, `skip`, `engine_probe`, `retired_engine_cleanup`.
enum ListenTimingLog {
    private static let queue = DispatchQueue(label: "reader.listen-timing", qos: .utility)
    private static let maxBytes: UInt64 = 2 * 1024 * 1024

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("ListenTiming", isDirectory: true)
    }

    static var fileURL: URL { directory.appendingPathComponent("timing.jsonl") }

    /// Monotonic-ish wall clock in seconds for durations.
    static func now() -> CFAbsoluteTime { CFAbsoluteTimeGetCurrent() }

    static func ms(since start: CFAbsoluteTime) -> Int {
        Int(((CFAbsoluteTimeGetCurrent() - start) * 1000).rounded())
    }

    static func log(_ event: String, _ fields: [String: Any] = [:]) {
        var obj = fields
        obj["t"] = (Date().timeIntervalSince1970 * 1000).rounded() / 1000
        obj["ev"] = event
        queue.async {
            guard JSONSerialization.isValidJSONObject(obj),
                  let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
            else { return }
            write(data + Data("\n".utf8))
        }
    }

    private static func write(_ line: Data) {
        let fm = FileManager.default
        let url = fileURL
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        if let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.uint64Value,
           size > maxBytes {
            let rotated = directory.appendingPathComponent("timing.1.jsonl")
            try? fm.removeItem(at: rotated)
            try? fm.moveItem(at: url, to: rotated)
        }
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: line)
    }

    static func shortKey(_ id: UUID?) -> String {
        id.map { String($0.uuidString.prefix(8)) } ?? "—"
    }
}
