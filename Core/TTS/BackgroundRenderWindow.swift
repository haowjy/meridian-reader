import Foundation

/// What rendering in the background costs, in the timing log: one `bg_render_window` line per
/// minute in the background with calls in it (and one when the app comes back), with wall and
/// process CPU seconds, `cpu_pct` (100 = one core busy), the footprint, the chunks rendered, their
/// audio and the routes they ran on.
@MainActor
final class BackgroundRenderWindow {
    static let length: TimeInterval = 60

    private var opened: (wall: CFAbsoluteTime, cpu: TimeInterval)?
    private var chunks = 0
    private var audio: TimeInterval = 0
    private var routes: Set<String> = []

    /// A window opens when the app goes to the background; the open one is logged when it comes back.
    func phaseChanged(to phase: AppRunState.Phase) {
        if phase == .background {
            if opened == nil { open() }
        } else {
            close(reason: "front")
        }
    }

    /// A chunk was rendered: counted in the open window, which is logged once it is a minute long.
    func noteChunk(route: String, audioSeconds: TimeInterval) {
        guard let opened else { return }
        chunks += 1
        audio += audioSeconds
        routes.insert(route)
        guard ListenTimingLog.now() - opened.wall >= Self.length else { return }
        close(reason: "minute")
        open()
    }

    private func open() {
        opened = (ListenTimingLog.now(), ProcessCPUTime.seconds)
        chunks = 0
        audio = 0
        routes = []
    }

    private func close(reason: String) {
        guard let opened else { return }
        self.opened = nil
        guard chunks > 0 else { return }
        let wall = ListenTimingLog.now() - opened.wall
        let cpu = ProcessCPUTime.seconds - opened.cpu
        var fields: [String: Any] = [
            "reason": reason, "wall_s": Self.rounded(wall), "cpu_s": Self.rounded(cpu), "chunks": chunks,
            "audio_s": Self.rounded(audio), "mem_mb": ProcessMemory.footprintMB,
            "route": routes.sorted().joined(separator: "+"),
        ]
        if wall > 0 {
            fields["cpu_pct"] = Int((cpu / wall * 100).rounded())
            fields["rtf"] = Self.rounded(audio / wall)
        }
        ListenTimingLog.log("bg_render_window", fields)
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
