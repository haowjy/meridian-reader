import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Debug-only device timing for every registered on-device engine (production hosts via the
/// registry, shared `LocalChunkRenderer`, per-engine chunk limits, same gate).
/// Limit engines with `-probeOnly Kokoro[,Other]` (short names; legacy `-kokoroOnly`).
///
/// Trigger: launch arg `-engineProbe` (e.g. `xcrun devicectl device process launch … -engineProbe`)
/// or Settings → Listen → Listen debug → Open full panel → "Run engine probe".
/// Output: `Documents/engine_probe.txt` (one line per step, written *before* each step so a
/// crash shows where it died) + `engine_probe` events in ListenTimingLog.
///
/// Uses its own host instance per engine, except for the app's live engine (reused — a second
/// instance of the same Core ML models fails on device). Waits for any in-flight app engine
/// prepare first so timings are not distorted by a concurrent download/compile.
@MainActor
enum EngineLatencyProbe {
    private(set) static var isRunning = false
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-engineProbe") }

    static let texts: [(label: String, text: String)] = [
        ("60", "The rain had stopped by morning, and the streets were quiet."),
        ("150", "She folded the map twice and tucked it into her coat. Nobody at the station noticed her leave, which was exactly how she wanted it to be."),
        ("400", "The old lighthouse keeper kept a logbook for forty years, noting every ship, every storm, and every strange light on the water. When the town finally replaced him with an automatic lamp, he refused to leave the island. He said the sea still needed someone to watch it, even if the ships no longer did. Visitors who rowed out in summer found him mending nets and humming songs nobody else remembered."),
    ]

    private static var didAutoRun = false

    static func runIfRequested(coordinator: LocalTTSCoordinator) {
        guard isRequested, !didAutoRun else { return }
        didAutoRun = true
        Task { await run(coordinator: coordinator) }
    }

    static var outputURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("engine_probe.txt")
    }

    static func run(coordinator: LocalTTSCoordinator) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        let out = outputURL
        try? Data().write(to: out)
        func log(_ s: String) {
            let line = "\(ISO8601DateFormatter().string(from: Date())) \(s)"
            print("[EngineProbe] \(line)")
            ListenDebugLog.shared.append("probe: \(s)")
            if let h = try? FileHandle(forWritingTo: out) {
                h.seekToEndOfFile(); h.write(Data((line + "\n").utf8)); try? h.synchronize(); try? h.close()
            }
        }
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        log("device=\(DeviceChipGate.machineIdentifier) os=\(os) build=\(LocalTTSCoordinator.buildConfiguration) lowPower=\(ProcessInfo.processInfo.isLowPowerModeEnabled) thermal=\(ProcessInfo.processInfo.thermalState.rawValue)")

        // Let the app's own engine prepare (download / first compile) finish first.
        let waitStart = ListenTimingLog.now()
        while coordinator.pendingEngineID != nil, ListenTimingLog.ms(since: waitStart) < 15 * 60_000 {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        log("app engine=\(coordinator.selectedEngineID.rawValue) ready=\(coordinator.localHostReady) waited_ms=\(ListenTimingLog.ms(since: waitStart))")
        // Hold the bake worker (it finishes its current chunk) so timings aren't interleaved.
        coordinator.synthQueue.isPausedForProbe = true
        defer { coordinator.synthQueue.isPausedForProbe = false }
        while coordinator.synthQueue.isWorkerRunning, ListenTimingLog.ms(since: waitStart) < 16 * 60_000 {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        log("bake worker paused (crash guard count=\(EngineCrashGuard.shared.crashCount))")

        let args = ProcessInfo.processInfo.arguments
        var only: Set<String>? = nil
        if let i = args.firstIndex(of: "-probeOnly"), i + 1 < args.count {
            only = Set(args[i + 1].split(separator: ",").map { $0.lowercased() })
        } else if args.contains("-kokoroOnly") {
            only = ["kokoro"]
        }
        let registry = coordinator.engines
        // Reverse descriptor order (recommended engine last, as before).
        let descriptors = registry.localDescriptors.reversed().filter {
            registry.supports($0.id) && (only?.contains($0.shortName.lowercased()) ?? true)
        }

        for descriptor in descriptors {
            let engine = descriptor.id
            let name = descriptor.shortName
            let installed = coordinator.isModelInstalled(engine)
            log("[\(name)] init start (models on disk=\(installed))")
            // Same engine as the live app host → reuse it. A second model instance of the same
            // engine (e.g. two KokoroAneManagers) makes Core ML predictions fail on device.
            let live = coordinator.localEngineInstance.liveRenderer(for: engine)
            let host: LocalChunkRenderer
            if let live {
                host = live
                log("[\(name)] reusing app host (live engine)")
            } else {
                guard let made = registry.makeHost(for: engine, voice: coordinator.voice(for: engine)) else {
                    log("[\(name)] no host on this OS")
                    continue
                }
                host = LocalChunkRenderer(host: made, descriptor: descriptor)
            }
            if let routing = host.host.routingLabel { log("[\(name)] compute units=\(routing)") }
            let tInit = ListenTimingLog.now()
            do {
                try await host.prepare()
            } catch {
                log("[\(name)] init FAILED after \(ListenTimingLog.ms(since: tInit)) ms: \(error.localizedDescription)")
                continue
            }
            let initMs = ListenTimingLog.ms(since: tInit)
            log("[\(name)] init_ms=\(initMs)")
            ListenTimingLog.log("engine_probe", ["engine": name, "step": "init", "ms": initMs, "on_disk": installed])

            let runs = texts + [("60-warm", texts[0].text)]
            for (label, text) in runs {
                let chunks = TextChunker.chunks(for: text, limits: descriptor.limits)
                log("[\(name)] synth \(label) chars=\(text.count) chunks=\(chunks.count) start")
                let t0 = ListenTimingLog.now()
                var firstMs = 0
                var audio = 0.0
                do {
                    for (i, chunk) in chunks.enumerated() {
                        let url = FileManager.default.temporaryDirectory
                            .appendingPathComponent("engine-probe-\(UUID().uuidString).caf")
                        defer { try? FileManager.default.removeItem(at: url) }
                        audio += try await host.renderChunk(
                            text: chunk, to: url, seed: 42, context: ["probe": true, "c": i])
                        if i == 0 { firstMs = ListenTimingLog.ms(since: t0) }
                    }
                    let wall = ListenTimingLog.ms(since: t0)
                    let rtfx = wall > 0 ? audio / (Double(wall) / 1000) : 0
                    log(String(format: "[%@] synth %@ chars=%d first_audio_ms=%d wall_ms=%d audio_s=%.2f rtfx=%.2f",
                               name, label, text.count, firstMs, wall, audio, rtfx))
                    ListenTimingLog.log("engine_probe", [
                        "engine": name, "step": label, "chars": text.count, "chunks": chunks.count,
                        "first_ms": firstMs, "wall_ms": wall, "audio_s": (audio * 100).rounded() / 100,
                    ])
                } catch {
                    log("[\(name)] synth \(label) FAILED after \(ListenTimingLog.ms(since: t0)) ms: \(error.localizedDescription)")
                }
            }
            if args.contains("-probeStress") {
                let n: Int = {
                    if let i = args.firstIndex(of: "-probeStressN"), i + 1 < args.count, let v = Int(args[i + 1]) { return v }
                    return 20
                }()
                log("[\(name)] stress \(n)× 150-char calls start")
                let tS = ListenTimingLog.now()
                for i in 0..<n {
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("engine-stress-\(i).caf")
                    do {
                        _ = try await host.renderChunk(text: texts[1].text, to: url, seed: 42, context: ["probe": true, "c": i])
                    } catch {
                        log("[\(name)] stress call \(i) FAILED: \(error.localizedDescription)")
                    }
                    try? FileManager.default.removeItem(at: url)
                    if i % 10 == 9 { log("[\(name)] stress \(i + 1)/\(n) ok (\(ListenTimingLog.ms(since: tS)) ms)") }
                }
            }
            if live == nil {
                await host.host.unload()
                log("[\(name)] unloaded")
            }
        }
        log("done")
    }
}
