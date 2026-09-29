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

/// Snapshot of Listen / local-engine / bake state for the debug overlay.
struct ListenDebugSnapshot: Equatable {
    var phase: String
    var phaseLabel: String
    var engine: String
    var isAudible: Bool
    var isSpeaking: Bool
    var isPaused: Bool
    var playhead: Int
    var paragraphCount: Int
    var bufferedCount: Int
    var awaitingMore: Bool
    var producerActive: Bool
    var epoch: Int
    var currentCAF: String
    var secondsSinceEnqueue: Double?
    var lastHandoffGapMs: Double
    var lastHandoffWasPrimed: Bool
    var starveEventCount: Int
    var bakePlan: String
    var bakePendingJobs: Int
    var bakeReadyCount: Int
    var bakeParagraphCount: Int
    /// e.g. "eph:a1b2c3d4" or "svd:a1b2c3d4"
    var articleIdentity: String
    var queuePrimary: String
    var demotedCount: Int
    var activeBakeUnit: String
    var nextMissingUnit: String
    var workerBusy: Bool
    var warmingLocal: Bool
    var lastBakeEvent: String
    /// e.g. "fr (auto) → Apple · Kokoro is English-only" / "en (auto) → local.kokoro".
    var language: String = ""
    /// "foreground · Kokoro Core ML (gpuAneVocoder)" / "background · no Core ML — baked audio + Apple fallback" / "Apple TTS …".
    var renderMode: String = ""
    /// Paragraphs after the playhead already rendered (how far ahead the queue is).
    var readyAhead: Int = 0
    /// Last background stretch: units played baked / as chunks / as Apple fallback, deferrals.
    var background: String = "—"
    var audioSession: String = ""
}
