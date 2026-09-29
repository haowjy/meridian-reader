import AVFoundation
import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// Debug-only on-device benchmark + background soak for the Kokoro **CPU route** (ONNX Runtime,
/// CPU execution provider) — Kokoro's main route since 2026-09-24 (`KokoroCPUHost`). Use it to
/// pick the thread count (`KokoroRouteSettings.cpuThreads`).
///
/// Settings → Listen → Listen debug → Open full panel → "CPU route benchmark".
/// - Frontend: FluidAudio's phonemizer without Core ML (`KokoroAneCPUFrontend` via
///   `KokoroCPUHost`) + `vocab.json` + `af_heart` pack (style row `pack[len-1]`). Phonemes are
///   cached; the soak never phonemizes.
/// - Benchmark: threads 1/2/3/4 @ `.userInitiated`, 3 @ `.utility`, and 3 @ `.userInitiated`
///   with ORT spinning off. Bake queue paused and `SynthRenderGate` held → never overlaps a
///   Kokoro Core ML call.
/// - Soak: 3 threads @ `.userInitiated`, renders the 501/190-token inputs in a loop for N min
///   while Listen playback or a silent audio loop keeps the app alive in the background.
/// - Results: on screen + `Application Support/ListenTiming/cpubench.jsonl`; sample WAV
///   `ListenTiming/cpubench-sample-501tok-onnx-gain0.69.wav`.
@MainActor
@Observable
final class CPURouteBench {
    static let shared = CPURouteBench()

    struct Config {
        let threads: Int
        let qos: DispatchQoS.QoSClass
        let spinning: Bool
        var label: String {
            "\(threads)T \(CPURouteMetrics.qosLabel(qos))\(spinning ? "" : " nospin")"
        }
    }

    static let configs: [Config] = [
        Config(threads: 1, qos: .userInitiated, spinning: true),
        Config(threads: 2, qos: .userInitiated, spinning: true),
        Config(threads: 3, qos: .userInitiated, spinning: true),
        Config(threads: 4, qos: .userInitiated, spinning: true),
        Config(threads: 3, qos: .utility, spinning: true),
        Config(threads: 3, qos: .userInitiated, spinning: false),
    ]
    /// The config whose 501-token render is saved as the A/B sample.
    static let sampleConfigIndex = 2

    struct Row: Identifiable, Equatable {
        let id = UUID()
        var label: String
        var loadMs: Int
        var coldMs: Int
        var x190: Double
        var x501: Double
        var cpuPerAudio501: Double
        var peakMB: Double
        var thermal: String
        var error: String?
    }

    struct Inputs {
        var long: KokoroCPUInputs
        var short: KokoroCPUInputs
        var phonemesSource: String
        var matchesMac: Bool
    }

    private struct Timed {
        var samples: [Float]
        var wall: Double
        var cpu: Double
        var audio: Double { Double(samples.count) / Double(KokoroCPUAudio.sampleRate) }
        var xRealtime: Double { wall > 0 ? audio / wall : 0 }
    }

    private(set) var rows: [Row] = []
    private(set) var status = "Idle"
    private(set) var isRunning = false
    var soakMinutes = 15
    private(set) var soakRunning = false
    private(set) var soakStatus = "Off"
    private(set) var isPlayingSample = false
    private(set) var sampleExists = FileManager.default.fileExists(atPath: CPURouteBench.sampleURL.path)

    private var cachedInputs: Inputs?
    private var soakTask: Task<Void, Never>?
    private var keepAlive: AVAudioPlayer?
    private var samplePlayer: AVAudioPlayer?
    private let playerDelegate = PlayerDelegate()

    static var sampleURL: URL {
        ListenTimingLog.directory.appendingPathComponent("cpubench-sample-501tok-onnx-gain0.69.wav")
    }

    private static var phonemeCacheURL: URL {
        CPURouteModelStore.directory.deletingLastPathComponent().appendingPathComponent("phonemes-cache.json")
    }

    // MARK: - Benchmark

    func runBenchmark(coordinator: LocalTTSCoordinator) async {
        guard !isRunning, !soakRunning, !EngineLatencyProbe.isRunning else { return }
        guard CPURouteModelStore.fileLooksInstalled else {
            status = "Download the CPU model first."
            return
        }
        isRunning = true
        rows = []
        defer { isRunning = false }
        let runID = String(UUID().uuidString.prefix(8))

        // One heavy job at a time: let any engine prepare finish, then hold the bake worker.
        status = "Waiting for Kokoro prepare / bake worker…"
        let waitStart = ListenTimingLog.now()
        while coordinator.pendingEngineID != nil, ListenTimingLog.ms(since: waitStart) < 5 * 60_000 {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        coordinator.synthQueue.isPausedForProbe = true
        defer { coordinator.synthQueue.isPausedForProbe = false }
        while coordinator.synthQueue.isWorkerRunning, ListenTimingLog.ms(since: waitStart) < 7 * 60_000 {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        let waitedMs = ListenTimingLog.ms(since: waitStart)

        let inputs: Inputs
        do {
            status = "Phonemizing (FluidAudio)…"
            inputs = try await prepareInputs(coordinator: coordinator)
        } catch {
            status = "Inputs failed: \(error.localizedDescription)"
            CPUBenchLog.append("cpubench_error", ["run": runID, "stage": "inputs", "err": error.localizedDescription])
            return
        }

        var base = baseFields(runID: runID, inputs: inputs)
        base["bake_wait_ms"] = waitedMs
        CPUBenchLog.append("cpubench_start", base)
        ListenTimingLog.log("cpubench", ["op": "start", "run": runID])
        ListenDebugLog.shared.append("CPU bench \(runID): start (\(inputs.long.tokenCount)+\(inputs.short.tokenCount) tokens, phonemes \(inputs.phonemesSource))")

        let modelURL = CPURouteModelStore.ensurePatchedModel().url
        for (index, config) in Self.configs.enumerated() {
            status = "Running \(index + 1)/\(Self.configs.count): \(config.label)…"
            do {
                let (fields, row, longSamples) = try await Self.measure(config, inputs: inputs, modelURL: modelURL)
                rows.append(row)
                var obj = base
                obj.merge(fields) { _, new in new }
                obj["app_state"] = AppRunState.shared.phase.rawValue
                CPUBenchLog.append("cpubench_run", obj)
                ListenDebugLog.shared.append(String(format: "CPU bench %@: 501 %.2f× 190 %.2f× load %dms", config.label, row.x501, row.x190, row.loadMs))
                if index == Self.sampleConfigIndex {
                    saveSample(longSamples, runID: runID)
                }
            } catch {
                rows.append(Row(label: config.label, loadMs: 0, coldMs: 0, x190: 0, x501: 0, cpuPerAudio501: 0,
                                peakMB: 0, thermal: CPURouteMetrics.thermal, error: error.localizedDescription))
                CPUBenchLog.append("cpubench_error", ["run": runID, "config": config.label, "err": error.localizedDescription])
            }
        }
        let best = rows.filter { $0.error == nil }.max { $0.x501 < $1.x501 }
        CPUBenchLog.append("cpubench_end", ["run": runID, "thermal": CPURouteMetrics.thermal,
                                            "best": best?.label ?? "—", "best_x501": best?.x501 ?? 0])
        ListenTimingLog.log("cpubench", ["op": "end", "run": runID])
        status = "Done (\(runID)) · best \(best.map { String(format: "%@ %.2f×", $0.label, $0.x501) } ?? "—") · thermal \(CPURouteMetrics.thermal)"
    }

    private func baseFields(runID: String, inputs: Inputs) -> [String: Any] {
        [
            "run": runID, "device": CPURouteMetrics.device, "os": CPURouteMetrics.os,
            "build": LocalTTSCoordinator.buildConfiguration,
            "ort": KokoroONNXSession.runtimeVersion, "model": "onnx-community/Kokoro-82M-v1.0-ONNX model_fp16.onnx",
            "voice": KokoroHost.defaultVoice, "low_power": ProcessInfo.processInfo.isLowPowerModeEnabled,
            "tokens_501": inputs.long.tokenCount, "tokens_190": inputs.short.tokenCount,
            "phonemes_501": inputs.long.phonemeCount, "phonemes_190": inputs.short.phonemeCount,
            "style_row_501": inputs.long.styleRow, "style_row_190": inputs.short.styleRow,
            "phonemes_source": inputs.phonemesSource, "phonemes_match_mac": inputs.matchesMac,
            "bg_gpu_supported": CPURouteProbes.backgroundGPUSupported.map { $0 as Any } ?? NSNull(),
            "cpu_count": ProcessInfo.processInfo.activeProcessorCount,
        ]
    }

    /// One config: load a fresh session (on the config's QoS), a cold 190-token render, then warm
    /// 190 and 501 renders. Holds `SynthRenderGate` throughout so no Core ML call overlaps.
    private nonisolated static func measure(_ config: Config, inputs: Inputs, modelURL: URL) async throws
        -> (fields: [String: Any], row: Row, longSamples: [Float]) {
        await SynthRenderGate.shared.acquire()
        let sampler = FootprintSampler()
        sampler.start()
        let thermalStart = CPURouteMetrics.thermal
        do {
            let (session, loadMs) = try await CPURouteMetrics.onQueue(config.qos) { () throws -> (KokoroONNXSession, Int) in
                let t0 = ListenTimingLog.now()
                let s = try KokoroONNXSession(modelURL: modelURL, threads: config.threads, allowSpinning: config.spinning)
                return (s, ListenTimingLog.ms(since: t0))
            }
            let cold = try await timed(session, inputs.short, qos: config.qos)
            let warm190 = try await timed(session, inputs.short, qos: config.qos)
            let warm501 = try await timed(session, inputs.long, qos: config.qos)
            let mem = sampler.stop()
            await SynthRenderGate.shared.release()
            let fp = CPURouteMetrics.footprint()
            func r2(_ v: Double) -> Double { (v * 100).rounded() / 100 }
            func r3(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }
            let fields: [String: Any] = [
                "config": config.label, "threads": config.threads, "qos": CPURouteMetrics.qosLabel(config.qos),
                "spinning": config.spinning, "load_ms": loadMs,
                "cold_190_ms": Int(cold.wall * 1000), "warm_190_ms": Int(warm190.wall * 1000), "warm_501_ms": Int(warm501.wall * 1000),
                "audio_190_s": r2(warm190.audio), "audio_501_s": r2(warm501.audio),
                "rtf_190": r3(warm190.wall / max(warm190.audio, 0.001)), "rtf_501": r3(warm501.wall / max(warm501.audio, 0.001)),
                "x_realtime_190": r2(warm190.xRealtime), "x_realtime_501": r2(warm501.xRealtime),
                "cpu_s_per_audio_s_190": r3(warm190.cpu / max(warm190.audio, 0.001)),
                "cpu_s_per_audio_s_501": r3(warm501.cpu / max(warm501.audio, 0.001)),
                "thermal_start": thermalStart, "thermal_end": CPURouteMetrics.thermal,
                "phys_footprint_mb": CPURouteMetrics.mb(fp.current),
                "phys_footprint_max_mb": CPURouteMetrics.mb(mem.maxFootprint),
                "phys_footprint_lifetime_peak_mb": CPURouteMetrics.mb(fp.peak),
                "available_min_mb": CPURouteMetrics.mb(mem.minAvailable),
                "rms_501_raw": r3(Double(KokoroCPUAudio.rms(warm501.samples))),
            ]
            let row = Row(label: config.label, loadMs: loadMs, coldMs: Int(cold.wall * 1000),
                          x190: r2(warm190.xRealtime), x501: r2(warm501.xRealtime),
                          cpuPerAudio501: r2(warm501.cpu / max(warm501.audio, 0.001)),
                          peakMB: CPURouteMetrics.mb(mem.maxFootprint), thermal: CPURouteMetrics.thermal)
            return (fields, row, warm501.samples)
        } catch {
            _ = sampler.stop()
            await SynthRenderGate.shared.release()
            throw error
        }
    }

    private nonisolated static func timed(_ session: KokoroONNXSession, _ inputs: KokoroCPUInputs,
                                          qos: DispatchQoS.QoSClass) async throws -> Timed {
        try await CPURouteMetrics.onQueue(qos) {
            let cpu0 = CPURouteMetrics.cpuSeconds()
            let t0 = CFAbsoluteTimeGetCurrent()
            let samples = try session.run(inputs)
            return Timed(samples: samples, wall: CFAbsoluteTimeGetCurrent() - t0, cpu: CPURouteMetrics.cpuSeconds() - cpu0)
        }
    }

    // MARK: - Inputs (foreground only)

    /// Phonemes (cached on disk after the first on-device run), vocab ids and `af_heart` rows.
    /// Uses the live CPU-route host's Core-ML-free frontend, else a temporary `KokoroCPUHost`
    /// (frontend only; its ONNX session is never loaded).
    private func prepareInputs(coordinator: LocalTTSCoordinator) async throws -> Inputs {
        if let cachedInputs { return cachedInputs }
        let text = KokoroCPUBenchText.long
        var temporary: LocalSynthHost?
        let frontend: KokoroCPURouteFrontend
        if let live = coordinator.localEngineInstance.liveRenderer(for: .kokoro)?.host as? KokoroCPURouteFrontend {
            frontend = live
        } else {
            let made = KokoroCPUHost(voice: KokoroHost.defaultVoice)
            temporary = made
            frontend = made
        }

        var cache = (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: Self.phonemeCacheURL))) ?? [:]
        var longPh: String
        var source: String
        if let hit = cache[text] {
            longPh = hit
            source = "fluidaudio-device-cached"
        } else if AppRunState.shared.phase == .active {
            do {
                longPh = try await frontend.cpuRoutePhonemes(for: text)
                source = "fluidaudio-device"
                cache[text] = longPh
                try? FileManager.default.createDirectory(at: Self.phonemeCacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? JSONEncoder().encode(cache).write(to: Self.phonemeCacheURL)
            } catch {
                longPh = KokoroCPUBenchText.longPhonemesMac
                source = "builtin-mac (device G2P failed: \(error.localizedDescription))"
            }
            if let temporary { await temporary.unload() }
        } else {
            longPh = KokoroCPUBenchText.longPhonemesMac
            source = "builtin-mac (backgrounded)"
        }
        let shortPh = KokoroCPUTensorBuilder.shortCase(fromLongPhonemes: longPh)
        let pack = try await frontend.cpuRouteVoicePack(KokoroHost.defaultVoice)
        let long = try KokoroCPUTensorBuilder.build(
            tokenIDs: try await frontend.cpuRouteTokenIDs(for: longPh), phonemeCount: longPh.count, voicePack: pack)
        let short = try KokoroCPUTensorBuilder.build(
            tokenIDs: try await frontend.cpuRouteTokenIDs(for: shortPh), phonemeCount: shortPh.count, voicePack: pack)
        let inputs = Inputs(long: long, short: short, phonemesSource: source,
                            matchesMac: longPh == KokoroCPUBenchText.longPhonemesMac)
        cachedInputs = inputs
        return inputs
    }

    // MARK: - Sample WAV

    private func saveSample(_ samples: [Float], runID: String) {
        guard !samples.isEmpty else { return }
        let data = KokoroCPUAudio.wavData(samples, gain: KokoroCPUAudio.coreMLMatchGain)
        do {
            try FileManager.default.createDirectory(at: ListenTimingLog.directory, withIntermediateDirectories: true)
            try data.write(to: Self.sampleURL, options: .atomic)
            sampleExists = true
            CPUBenchLog.append("cpubench_sample", [
                "run": runID, "file": Self.sampleURL.lastPathComponent, "gain": Double(KokoroCPUAudio.coreMLMatchGain),
                "rms_raw": Double(KokoroCPUAudio.rms(samples)),
                "rms_saved": Double(KokoroCPUAudio.rms(samples.map { $0 * KokoroCPUAudio.coreMLMatchGain })),
                "audio_s": Double(samples.count) / Double(KokoroCPUAudio.sampleRate),
            ])
        } catch {
            ListenDebugLog.shared.append("CPU bench: sample save failed: \(error.localizedDescription)")
        }
    }

    func toggleSample() {
        if let p = samplePlayer, p.isPlaying {
            p.stop()
            isPlayingSample = false
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
            try session.setActive(true)
            let p = try AVAudioPlayer(contentsOf: Self.sampleURL)
            playerDelegate.onFinish = { [weak self] in Task { @MainActor in self?.isPlayingSample = false } }
            p.delegate = playerDelegate
            p.play()
            samplePlayer = p
            isPlayingSample = true
        } catch {
            ListenDebugLog.shared.append("CPU bench: can't play sample: \(error.localizedDescription)")
        }
    }

    // MARK: - Soak (lock-screen test)

    func startSoak(speech: SpeechController) {
        guard !soakRunning, !isRunning else { return }
        guard CPURouteModelStore.fileLooksInstalled else {
            soakStatus = "Download the CPU model first."
            return
        }
        guard AppRunState.shared.phase == .active else {
            soakStatus = "Start the soak with the app in the foreground."
            return
        }
        soakRunning = true
        let minutes = soakMinutes
        soakTask = Task { await self.runSoak(speech: speech, minutes: minutes) }
    }

    func stopSoak() {
        soakTask?.cancel()
        soakStatus = "Stopping after the current chunk…"
    }

    private func runSoak(speech: SpeechController, minutes: Int) async {
        let runID = "soak-" + String(UUID().uuidString.prefix(6))
        #if canImport(UIKit)
        UIDevice.current.isBatteryMonitoringEnabled = true
        #endif
        var reason = "completed"
        var chunks = 0
        var totalAudio = 0.0
        var totalWall = 0.0
        var bgChunks = 0
        var bgAudio = 0.0
        var bgWall = 0.0
        let start = ListenTimingLog.now()
        do {
            soakStatus = "Preparing inputs…"
            let inputs = try await prepareInputs(coordinator: speech.localTTS)
            let modelURL = CPURouteModelStore.ensurePatchedModel().url
            let loadStart = ListenTimingLog.now()
            let session = try await CPURouteMetrics.onQueue(.userInitiated) {
                try KokoroONNXSession(modelURL: modelURL, threads: 3, allowSpinning: true)
            }
            let loadMs = ListenTimingLog.ms(since: loadStart)
            let keep = startKeepAlive(speech: speech)
            var base = baseFields(runID: runID, inputs: inputs)
            base["minutes"] = minutes
            base["load_ms"] = loadMs
            base["keepalive"] = keep
            base["threads"] = 3
            base["qos"] = "userInitiated"
            CPUBenchLog.append("cpubench_soak_start", base)
            ListenTimingLog.log("cpubench", ["op": "soak_start", "run": runID, "minutes": minutes, "keepalive": keep])
            ListenDebugLog.shared.append("CPU soak \(runID): \(minutes) min, keep-alive \(keep) — lock the phone now")

            let deadline = start + Double(minutes) * 60
            var window: [(audio: Double, wall: Double)] = []
            var prevEnd = ListenTimingLog.now()
            while !Task.isCancelled, ListenTimingLog.now() < deadline {
                let inp = chunks % 2 == 0 ? inputs.long : inputs.short
                let gateStart = ListenTimingLog.now()
                await SynthRenderGate.shared.acquire()
                let gateMs = ListenTimingLog.ms(since: gateStart)
                let phaseBefore = AppRunState.shared.phase.rawValue
                let r: Timed
                do {
                    r = try await Self.timed(session, inp, qos: .userInitiated)
                    await SynthRenderGate.shared.release()
                } catch {
                    await SynthRenderGate.shared.release()
                    throw error
                }
                let phase = AppRunState.shared.phase.rawValue
                let gapMs = Int((gateStart - prevEnd) * 1000)
                prevEnd = ListenTimingLog.now()
                chunks += 1
                totalAudio += r.audio
                totalWall += r.wall
                if phase == "background" && phaseBefore == "background" {
                    bgChunks += 1; bgAudio += r.audio; bgWall += r.wall
                }
                window.append((r.audio, r.wall))
                if window.count > 5 { window.removeFirst() }
                let rolling = window.reduce(0) { $0 + $1.audio } / max(window.reduce(0) { $0 + $1.wall }, 0.001)
                let fp = CPURouteMetrics.footprint()
                var battery: Any = NSNull()
                #if canImport(UIKit)
                if UIDevice.current.batteryLevel >= 0 { battery = Double(UIDevice.current.batteryLevel) }
                #endif
                let keepNow = speech.isPlaying ? "listen" : (keepAlive?.isPlaying == true ? "silent" : "none")
                CPUBenchLog.append("cpubench_soak_chunk", [
                    "run": runID, "i": chunks, "tokens": inp.tokenCount,
                    "audio_s": (r.audio * 100).rounded() / 100, "wall_ms": Int(r.wall * 1000),
                    "x_realtime": (r.xRealtime * 100).rounded() / 100,
                    "rtf": ((r.wall / max(r.audio, 0.001)) * 1000).rounded() / 1000,
                    "x_realtime_rolling5": (rolling * 100).rounded() / 100,
                    "x_realtime_cumulative": ((totalAudio / max(totalWall, 0.001)) * 100).rounded() / 100,
                    "cpu_s_per_audio_s": ((r.cpu / max(r.audio, 0.001)) * 1000).rounded() / 1000,
                    "app_state": phase, "app_state_at_start": phaseBefore,
                    "thermal": CPURouteMetrics.thermal, "phys_footprint_mb": CPURouteMetrics.mb(fp.current),
                    "available_mb": CPURouteMetrics.mb(CPURouteMetrics.availableMemory()),
                    "elapsed_s": Int(ListenTimingLog.now() - start), "gate_wait_ms": gateMs, "gap_ms": gapMs,
                    "keepalive": keepNow, "battery": battery,
                    "low_power": ProcessInfo.processInfo.isLowPowerModeEnabled,
                ])
                let remaining = max(0, Int(deadline - ListenTimingLog.now()))
                soakStatus = String(format: "#%d %@ · %.2f× (rolling %.2f×) · %@ · %.0f MB · %d:%02d left",
                                    chunks, phase, r.xRealtime, rolling, CPURouteMetrics.thermal,
                                    CPURouteMetrics.mb(fp.current), remaining / 60, remaining % 60)
            }
            if Task.isCancelled { reason = "stopped" }
        } catch {
            reason = "error: \(error.localizedDescription)"
        }
        stopKeepAlive(speech: speech)
        #if canImport(UIKit)
        UIDevice.current.isBatteryMonitoringEnabled = false
        #endif
        let summary: [String: Any] = [
            "run": runID, "reason": reason, "chunks": chunks, "elapsed_s": Int(ListenTimingLog.now() - start),
            "audio_s": Int(totalAudio), "x_realtime_cumulative": ((totalAudio / max(totalWall, 0.001)) * 100).rounded() / 100,
            "bg_chunks": bgChunks, "bg_x_realtime": bgWall > 0 ? ((bgAudio / bgWall) * 100).rounded() / 100 : 0,
            "thermal_end": CPURouteMetrics.thermal,
        ]
        CPUBenchLog.append("cpubench_soak_end", summary)
        ListenTimingLog.log("cpubench", ["op": "soak_end", "run": runID, "reason": reason, "chunks": chunks])
        ListenDebugLog.shared.append("CPU soak \(runID) \(reason): \(chunks) chunks, \(bgChunks) in background")
        soakStatus = String(format: "Ended (%@): %d chunks, %.2f× overall, %d in background (%.2f×)",
                            reason, chunks, totalAudio / max(totalWall, 0.001), bgChunks, bgWall > 0 ? bgAudio / bgWall : 0)
        soakRunning = false
        soakTask = nil
    }

    /// Normal Listen playback already keeps the app alive; otherwise loop silence on Listen's
    /// own session config (`.playback` / `.spokenAudio`, UIBackgroundModes audio).
    private func startKeepAlive(speech: SpeechController) -> String {
        if speech.isPlaying { return "listen" }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
            try session.setActive(true)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("cpubench-silence.wav")
            try KokoroCPUAudio.wavData([Float](repeating: 0, count: KokoroCPUAudio.sampleRate)).write(to: url)
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1
            p.play()
            keepAlive = p
            return "silent"
        } catch {
            return "none (\(error.localizedDescription))"
        }
    }

    private func stopKeepAlive(speech: SpeechController) {
        guard let p = keepAlive else { return }
        p.stop()
        keepAlive = nil
        if !speech.isActive, samplePlayer?.isPlaying != true {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}

private final class PlayerDelegate: NSObject, AVAudioPlayerDelegate {
    var onFinish: (() -> Void)?
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { onFinish?() }
}
