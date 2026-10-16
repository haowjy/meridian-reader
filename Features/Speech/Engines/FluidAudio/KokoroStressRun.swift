#if DEBUG
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// `-KokoroStress coreml|onnx` (Debug hooks only): renders a fixed corpus of
/// `KokoroStressCorpus.calls` Kokoro calls through one route with the app in front, to count
/// crashes and compare speed.
///
/// - Hosts: `coreml` = `KokoroHost` alone (no ONNX fallback; `-kokoroUnits` still applies),
///   `onnx` = `KokoroCPUHost` at the front thread count. The app's own Kokoro host is unloaded
///   first and the render queue is paused; every call holds `SynthRenderGate`.
/// - Output: `Documents/KokoroStress/<route>.jsonl`. A `begin` line is written and synced before
///   each call, an `end` line (wall ms, audio s, RTF, ms per audio second) after it, so a hard
///   crash leaves its call index. Launched again with the same argument, the run counts that crash
///   (with the Core ML breadcrumb's stage) and goes on with the next call, until the corpus is done
///   or `crashLimit` crashes. Then `Documents/KokoroStress/<route>-summary.json`.
/// - `-KokoroStressCalls N` shortens or lengthens the corpus; `-KokoroStressFresh` starts over.
///   A finished run starts over by itself.
/// - Calls start only while the app is active; the screen stays awake while it runs.
@MainActor
enum KokoroStressRun {
    static let crashLimit = 5

    enum Route: String { case coreml, onnx }

    /// What the launch asked for (`LaunchOptions.kokoroStress`).
    struct Request: Equatable {
        var route: Route
        var calls: Int = KokoroStressCorpus.calls
        var fresh = false
    }

    private static var didRun = false

    /// Once per process.
    static func start(_ request: Request, coordinator: LocalTTSCoordinator) {
        guard !didRun else { return }
        didRun = true
        Task { await run(request, coordinator: coordinator) }
    }

    static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KokoroStress", isDirectory: true)
    }

    static func run(_ request: Request, coordinator: LocalTTSCoordinator) async {
        let log = KokoroStressLog(url: directory.appendingPathComponent("\(request.route.rawValue).jsonl"))
        let summaryURL = directory.appendingPathComponent("\(request.route.rawValue)-summary.json")
        var history = log.read()
        if request.fresh || history.done || history.corpusCalls != request.calls {
            log.reset()
            try? FileManager.default.removeItem(at: summaryURL)
            history = KokoroStressHistory()
        }
        let runID = String(UUID().uuidString.prefix(8))
        if let crashed = history.inFlight {
            var fields: [String: Any] = ["ev": "crash", "i": crashed.index, "run": crashed.run, "found_by": runID]
            if let crumb = CoreMLBreadcrumbFile.shared.read(), crumb.at.timeIntervalSince1970 >= crashed.t {
                fields["coreml_stage"] = "\(crumb.model)/\(crumb.stage)"
            }
            log.append(fields)
            history = log.read()
        }
        CoreMLBreadcrumbFile.shared.clear()
        let corpus = KokoroStressCorpus.chunks(count: request.calls)
        if history.crashes.count >= crashLimit {
            finish(log: log, summaryURL: summaryURL, request: request, status: "stopped_at_crash_limit")
            return
        }

        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }
        #endif
        // The app's own Kokoro host goes first: Core ML twice fails on device, and ONNX twice
        // doubles the memory.
        await coordinator.withRenderingQuiet {
            let voice = KokoroHost.defaultVoice
            let host: LocalSynthHost
            switch request.route {
            case .coreml:
                host = KokoroHost(voice: voice, unitsLabel: coordinator.engines.provider(FluidAudioProvider.self)?.coreMLUnits)
            case .onnx: host = KokoroCPUHost(voice: voice, threads: KokoroRouteSettings().cpuThreads)
            }
            let start = history.nextIndex
            log.append([
                "ev": "start", "run": runID, "route": request.route.rawValue, "corpus_calls": request.calls,
                "from": start, "units": host.routingLabel ?? "", "voice": voice,
                "device": DeviceChipGate.machineIdentifier, "os": ProcessInfo.processInfo.operatingSystemVersionString,
                "build": LocalTTSCoordinator.buildConfiguration, "optimized": !_isDebugAssertConfiguration(),
                "thermal": ProcessInfo.processInfo.thermalState.rawValue,
                "low_power": ProcessInfo.processInfo.isLowPowerModeEnabled, "cores": ProcessInfo.processInfo.activeProcessorCount,
            ])
            say("\(request.route.rawValue) run \(runID): calls \(start)..<\(request.calls), \(history.crashes.count) crashes so far")

            let t0 = ListenTimingLog.now()
            do {
                try await host.prepare()
            } catch {
                log.append(["ev": "prepare_failed", "run": runID, "err": error.localizedDescription])
                say("prepare failed: \(error.localizedDescription)")
                return
            }
            let prepareMs = ListenTimingLog.ms(since: t0)
            log.append(["ev": "prepared", "run": runID, "ms": prepareMs, "units": host.routingLabel ?? ""])

            for index in start..<corpus.count {
                await waitUntilActive(log: log, run: runID)
                let chunk = corpus[index]
                log.append(["ev": "begin", "run": runID, "i": index, "chars": chunk.text.count, "para": chunk.paragraph,
                            "t": Date().timeIntervalSince1970])
                await SynthRenderGate.shared.acquire()
                let tCall = ListenTimingLog.now()
                var fields: [String: Any] = ["ev": "end", "run": runID, "i": index, "chars": chunk.text.count]
                do {
                    let pcm = try await host.synthesizeOnce(text: chunk.text, priority: .listener)
                    let wallMs = (ListenTimingLog.now() - tCall) * 1000
                    fields["ok"] = true
                    fields["wall_ms"] = Int(wallMs.rounded())
                    fields["audio_s"] = (pcm.duration * 1000).rounded() / 1000
                    if pcm.duration > 0 {
                        fields["rtf"] = (wallMs / 1000 / pcm.duration * 1000).rounded() / 1000
                        fields["ms_per_audio_s"] = Int((wallMs / pcm.duration).rounded())
                    }
                    for key in ["stages_ms", "onnx_ms", "g2p_ms", "threads", "phonemes", "tokens"] {
                        if let v = pcm.metrics[key] { fields[key] = v }
                    }
                } catch {
                    fields["ok"] = false
                    fields["wall_ms"] = ListenTimingLog.ms(since: tCall)
                    fields["err"] = error.localizedDescription
                }
                await SynthRenderGate.shared.release()
                fields["thermal"] = ProcessInfo.processInfo.thermalState.rawValue
                fields["mem_mb"] = ProcessMemory.footprintMB
                if index == start { fields["first_audio_ms"] = ListenTimingLog.ms(since: t0) }
                log.append(fields)
                if index % 20 == 19 || index == start { say("\(request.route.rawValue) \(index + 1)/\(corpus.count)") }
            }
            await host.unload()
            finish(log: log, summaryURL: summaryURL, request: request, status: "complete")
        }
    }

    private static func waitUntilActive(log: KokoroStressLog, run: String) async {
        guard AppRunState.shared.phase != .active else { return }
        log.append(["ev": "paused", "run": run, "phase": AppRunState.shared.phase.rawValue])
        while AppRunState.shared.phase != .active {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        log.append(["ev": "resumed", "run": run])
    }

    private static func finish(log: KokoroStressLog, summaryURL: URL, request: Request, status: String) {
        let summary = log.read().summary(route: request.route.rawValue, corpusCalls: request.calls, status: status)
        if let data = try? JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: summaryURL, options: .atomic)
        }
        log.append(["ev": "done", "status": status])
        say("done: \(status) \(summary)")
    }

    private static func say(_ s: String) {
        ListenDebugLog.shared.append("stress: \(s)")
    }
}

/// The stress corpus: paragraphs of 1 to 10 sentences from the demo book and the engine probe's
/// texts, cut by the ONNX route's chunker (≤ 280 characters; a paragraph's first chunk short, as
/// in playback). Deterministic, so every run renders the same calls in the same order.
enum KokoroStressCorpus {
    static let calls = 320

    struct Chunk: Equatable {
        var text: String
        var paragraph: Int
    }

    static let sentencesPerParagraph = [1, 3, 2, 5, 1, 4, 8, 2, 6, 1, 3, 10]

    static var sentences: [String] {
        let paragraphs = DemoBook.chapters.flatMap(\.paragraphs) + DemoBook.loosePage.paragraphs
            + EngineLatencyProbe.texts.map(\.text)
        return paragraphs.flatMap { paragraph in
            var out: [String] = []
            paragraph.enumerateSubstrings(in: paragraph.startIndex..., options: .bySentences) { s, _, _, _ in
                if let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty { out.append(s) }
            }
            return out
        }
    }

    static func chunks(count: Int) -> [Chunk] {
        let pool = sentences
        var out: [Chunk] = []
        var next = 0
        var paragraph = 0
        while out.count < count {
            let n = sentencesPerParagraph[paragraph % sentencesPerParagraph.count]
            let text = (0..<n).map { pool[(next + $0) % pool.count] }.joined(separator: " ")
            next += n
            out += TextChunker.chunks(for: text, limits: .kokoroCPU).map { Chunk(text: $0, paragraph: paragraph) }
            paragraph += 1
        }
        return Array(out.prefix(count))
    }
}

/// What a stress log holds so far.
struct KokoroStressHistory {
    struct InFlight { var index: Int; var run: String; var t: Double }

    var events: [[String: Any]] = []

    var done: Bool { events.contains { $0["ev"] as? String == "done" } }
    var corpusCalls: Int? { events.last { $0["ev"] as? String == "start" }?["corpus_calls"] as? Int }
    var ends: [[String: Any]] { events.filter { $0["ev"] as? String == "end" } }
    var crashes: [[String: Any]] { events.filter { $0["ev"] as? String == "crash" } }

    /// A call begun and neither ended nor already counted as a crash: the process died in it.
    var inFlight: InFlight? {
        guard let last = events.last(where: { ["begin", "end", "crash"].contains($0["ev"] as? String) }),
              last["ev"] as? String == "begin", let i = last["i"] as? Int else { return nil }
        return InFlight(index: i, run: last["run"] as? String ?? "", t: last["t"] as? Double ?? 0)
    }

    /// The call after the last one ended or crashed.
    var nextIndex: Int {
        let done = (ends + crashes).compactMap { $0["i"] as? Int }
        return (done.max() ?? -1) + 1
    }

    func summary(route: String, corpusCalls: Int, status: String) -> [String: Any] {
        let ok = ends.filter { $0["ok"] as? Bool == true }
        let wallMs = ok.compactMap { ($0["wall_ms"] as? NSNumber)?.doubleValue }.reduce(0, +)
        let audioS = ok.compactMap { ($0["audio_s"] as? NSNumber)?.doubleValue }.reduce(0, +)
        let perAudio = ok.compactMap { ($0["ms_per_audio_s"] as? NSNumber)?.doubleValue }.sorted()
        func pct(_ p: Double) -> Double { perAudio.isEmpty ? 0 : perAudio[min(perAudio.count - 1, Int(Double(perAudio.count) * p))] }
        func bucket(_ range: Range<Int>) -> [String: Any] {
            let rows = ok.filter { range.contains($0["chars"] as? Int ?? -1) }
            let w = rows.compactMap { ($0["wall_ms"] as? NSNumber)?.doubleValue }.reduce(0, +)
            let a = rows.compactMap { ($0["audio_s"] as? NSNumber)?.doubleValue }.reduce(0, +)
            return ["calls": rows.count, "ms_per_audio_s": a > 0 ? Int((w / a).rounded()) : 0,
                    "mean_wall_ms": rows.isEmpty ? 0 : Int((w / Double(rows.count)).rounded())]
        }
        let starts = events.filter { $0["ev"] as? String == "start" }
        let launches: [[String: Any]] = starts.map { start in
            let run = start["run"] as? String ?? ""
            let prepared = events.first { $0["ev"] as? String == "prepared" && $0["run"] as? String == run }
            let first = ends.first { $0["run"] as? String == run }
            return ["run": run, "from": start["from"] ?? 0, "prepare_ms": prepared?["ms"] ?? NSNull(),
                    "first_call_wall_ms": first?["wall_ms"] ?? NSNull(),
                    "first_audio_ms": first?["first_audio_ms"] ?? NSNull()]
        }
        return [
            "route": route, "status": status, "corpus_calls": corpusCalls,
            "units": starts.last?["units"] ?? "", "device": starts.last?["device"] ?? "", "os": starts.last?["os"] ?? "",
            "optimized": starts.last?["optimized"] ?? NSNull(),
            "calls_attempted": ends.count + crashes.count, "calls_ok": ok.count, "calls_failed": ends.count - ok.count,
            "crashes": crashes.count,
            "crash_calls": crashes.map { ["i": $0["i"] ?? -1, "coreml_stage": $0["coreml_stage"] ?? NSNull()] },
            "audio_s": (audioS * 10).rounded() / 10, "wall_s": (wallMs / 100).rounded() / 10,
            "x_realtime": wallMs > 0 ? (audioS / (wallMs / 1000) * 100).rounded() / 100 : 0,
            "rtf": audioS > 0 ? (wallMs / 1000 / audioS * 1000).rounded() / 1000 : 0,
            "ms_per_audio_s": audioS > 0 ? Int((wallMs / audioS).rounded()) : 0,
            "ms_per_audio_s_p50": Int(pct(0.5).rounded()), "ms_per_audio_s_p90": Int(pct(0.9).rounded()),
            "by_chars": ["lt100": bucket(0..<100), "100to199": bucket(100..<200), "200plus": bucket(200..<10_000)],
            "launches": launches,
            "max_mem_mb": ends.compactMap { $0["mem_mb"] as? Int }.max() ?? -1,
            "max_thermal": ends.compactMap { $0["thermal"] as? Int }.max() ?? -1,
        ]
    }
}

/// Append-only JSON lines, each synced to disk before the call it announces.
struct KokoroStressLog {
    let url: URL

    func append(_ fields: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]) else { return }
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            fm.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data + Data("\n".utf8))
        try? handle.synchronize()
    }

    func read() -> KokoroStressHistory {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return KokoroStressHistory() }
        let events = text.split(separator: "\n").compactMap {
            try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
        }
        return KokoroStressHistory(events: events)
    }

    func reset() {
        try? FileManager.default.removeItem(at: url)
    }
}
#endif
