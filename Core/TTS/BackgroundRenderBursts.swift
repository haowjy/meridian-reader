import Foundation

/// When bake-ahead of the playing article may render while the app is in the background, on a
/// route that renders there (Kokoro's ONNX CPU route; `RenderAdmission`).
///
/// Rendering a whole article back to back in the background got the app killed: about a minute of
/// ONNX at 3 threads, at 1.0–1.3 GB, after the phone locked. Listening needs only enough audio
/// ahead of the playhead to ride out a slow render. So in the background bake-ahead runs in
/// bursts, measured in listening time ready ahead (seconds of rendered audio at the listen speed,
/// `SynthQueueContext.readyAheadSeconds`): a burst starts below `lowWater` and stops at
/// `highWater`; in between, whatever is happening carries on (hysteresis, so it doesn't flap chunk
/// by chunk). Between bursts the worker is idle; playback wakes it (`GlobalSynthQueue.playbackAdvanced`).
/// A listener's chunk (the player is waiting for it) renders regardless.
struct BackgroundRenderWatermarks: Equatable {
    /// A burst starts below this much listening ahead. 4 min leaves a single ONNX thread (the
    /// background thread count, `KokoroRouteSettings.backgroundThreads`) time to catch up before
    /// the player runs dry and a paragraph goes to Apple.
    /// `-bgRender.lowWaterSeconds <s>` (a debug launch) lowers it so a simulator test sees bursts
    /// and download turns alternate within a short page; the high-water mark is then twice it.
    static var lowWater: TimeInterval { debugLowWater ?? 4 * 60 }
    /// A burst stops once this much listening is ready ahead: each burst adds about 4 min.
    static var highWater: TimeInterval { debugLowWater.map { $0 * 2 } ?? 8 * 60 }

    private static var debugLowWater: TimeInterval? {
        #if DEBUG
        let s = UserDefaults.standard.double(forKey: "bgRender.lowWaterSeconds")
        return s > 0 ? s : nil
        #else
        return nil
        #endif
    }

    private(set) var isBursting = false

    enum Change: Equatable {
        case started
        case stoppedAtHighWater
    }

    /// The listening time ready ahead now; returns what changed.
    mutating func update(readyAhead: TimeInterval) -> Change? {
        if isBursting, readyAhead >= Self.highWater {
            isBursting = false
            return .stoppedAtHighWater
        }
        if !isBursting, readyAhead < Self.lowWater {
            isBursting = true
            return .started
        }
        return nil
    }

    /// The burst ended for another reason (foreground, nothing left to render, playback paused).
    /// Returns whether one was running.
    mutating func end() -> Bool {
        defer { isBursting = false }
        return isBursting
    }
}

/// The render queue's background bursts: the watermarks plus the timing-log lines that show them
/// on a device (`bg_render_burst_start` / `bg_render_burst_stop`, with the listening time ready
/// ahead, and for a stop the reason, chunks rendered, wall and process CPU seconds).
@MainActor
final class BackgroundRenderBursts {
    private var watermarks = BackgroundRenderWatermarks()
    private var current: (wall: CFAbsoluteTime, cpu: TimeInterval, chunks: Int)?

    var isBursting: Bool { watermarks.isBursting }

    /// Before a bake-ahead chunk of the playing article in the background: start or stop a burst
    /// on the listening time ready ahead now (`RenderAdmission` then reads `isBursting`).
    func update(readyAhead: TimeInterval) {
        switch watermarks.update(readyAhead: readyAhead) {
        case .started?:
            current = (ListenTimingLog.now(), ProcessCPUTime.seconds, 0)
            ListenTimingLog.log("bg_render_burst_start", [
                "ready_ahead_s": Self.rounded(readyAhead), "low_water_s": BackgroundRenderWatermarks.lowWater,
                "reason": "below_low_water",
            ])
        case .stoppedAtHighWater?:
            logStop(reason: "high_water", readyAhead: readyAhead)
        case nil:
            break
        }
    }

    /// A chunk rendered (counted only during a burst).
    func noteChunkRendered() {
        guard isBursting else { return }
        current?.chunks += 1
    }

    /// The burst ends without reaching the high-water mark: the app came to the front, the worker
    /// parked or ran out of work. `readyAhead` is read only when a burst was running.
    func end(reason: String, readyAhead: () -> TimeInterval) {
        guard watermarks.end() else { return }
        logStop(reason: reason, readyAhead: readyAhead())
    }

    private func logStop(reason: String, readyAhead: TimeInterval) {
        var fields: [String: Any] = ["ready_ahead_s": Self.rounded(readyAhead), "reason": reason]
        if let current {
            let wall = ListenTimingLog.now() - current.wall
            let cpu = ProcessCPUTime.seconds - current.cpu
            fields["chunks"] = current.chunks
            fields["wall_s"] = Self.rounded(wall)
            fields["cpu_s"] = Self.rounded(cpu)
            // Process CPU over wall time, 100 = one core busy: what iOS's background CPU limit reads.
            if wall > 0 { fields["cpu_pct"] = Int((cpu / wall * 100).rounded()) }
        }
        current = nil
        ListenTimingLog.log("bg_render_burst_stop", fields)
    }

    private static func rounded(_ seconds: TimeInterval) -> Double { (seconds * 10).rounded() / 10 }
}

/// CPU time this process has used, user + system, all threads (ORT's pool included), in seconds.
enum ProcessCPUTime {
    static var seconds: TimeInterval {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func s(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000 }
        return s(usage.ru_utime) + s(usage.ru_stime)
    }
}
