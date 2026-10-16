import Foundation
import Observation

/// Small MainActor ring buffer for Listen / local-engine diagnostics.
/// Open: Settings → Listen → enable Listen debug (Debug chip on bar), long-press play/pause, or Open full panel.
@MainActor
@Observable
final class ListenDebugLog {
    static let shared = ListenDebugLog()

    private let capacity = 30
    private(set) var lines: [String] = []

    func append(_ message: String) {
        let stamp = Self.timeFormatter.string(from: Date())
        lines.append("\(stamp) \(message)")
        if lines.count > capacity {
            lines.removeFirst(lines.count - capacity)
        }
    }

    func clear() { lines.removeAll() }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
}
