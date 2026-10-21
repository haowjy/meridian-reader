#if DEBUG
import Foundation

/// Debug-only device timing for every registered on-device engine (production hosts via the
/// registry, shared `LocalChunkRenderer`, per-engine chunk limits, same gate).
///
/// Trigger: launch arg `-engineProbe` (e.g. `xcrun devicectl device process launch … -engineProbe`;
/// `LaunchOptions.engineProbe`) or Settings → Listen → Listen debug → Open full panel → "Run
/// engine probe" (every engine, no stress calls).
/// Output: `Documents/engine_probe.txt` (one line per step, written *before* each step so a
/// crash shows where it died) + `engine_probe` events in ListenTimingLog.
///
/// Builds its own host per engine once the app's own load has settled and its host has gone
/// (`LocalTTSCoordinator.withRenderingQuiet`): a second loaded copy of the same Core ML models
/// fails on device, and a second ORT session doubles the memory.
@MainActor
enum EngineLatencyProbe {
    private(set) static var isRunning = false

    struct Request: Equatable {
        /// `-probeOnly Kokoro[,Other]`: these engines (short names, any case); nil: every one.
        var engines: Set<String>? = nil
        /// `-probeStress [-probeStressN n]`: this many 150-character calls after the timed texts.
        var stressCalls: Int? = nil
    }

    static let texts: [(label: String, text: String)] = [
        ("60", "The rain had stopped by morning, and the streets were quiet."),
        ("150", "She folded the map twice and tucked it into her coat. Nobody at the station noticed her leave, which was exactly how she wanted it to be."),
        ("400", "The old lighthouse keeper kept a logbook for forty years, noting every ship, every storm, and every strange light on the water. When the town finally replaced him with an automatic lamp, he refused to leave the island. He said the sea still needed someone to watch it, even if the ships no longer did. Visitors who rowed out in summer found him mending nets and humming songs nobody else remembered."),
    ]

    private static var didAutoRun = false

    /// The launch's request, once per process.
    static func start(_ request: Request, coordinator: LocalTTSCoordinator) {
        guard !didAutoRun else { return }
        didAutoRun = true
        Task { await run(request, coordinator: coordinator) }
    }

    static var outputURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("engine_probe.txt")
    }

    static func run(_ request: Request = Request(), coordinator: LocalTTSCoordinator) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        let out = outputURL
        try? Data().write(to: out)
        func log(_ s: String) {
            let line = "\(ISO8601DateFormatter().string(from: Date())) \(s)"
            ListenDebugLog.shared.append("probe: \(s)")
            if let h = try? FileHandle(forWritingTo: out) {
                h.seekToEndOfFile(); h.write(Data((line + "\n").utf8)); try? h.synchronize(); try? h.close()
            }
        }
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        log("device=\(DeviceChipGate.machineIdentifier) os=\(os) build=\(LocalTTSCoordinator.buildConfiguration) lowPower=\(ProcessInfo.processInfo.isLowPowerModeEnabled) thermal=\(ProcessInfo.processInfo.thermalState.rawValue)")

        // The app's own load (prepare / first compile) settles first; then the bake worker
        // holds (it finishes its current chunk) and the app's host goes, so the probe's host is
        // the only one loaded and timings aren't interleaved.
        let waitStart = ListenTimingLog.now()
        await coordinator.withRenderingQuiet {
            log("app engine=\(coordinator.selectedEngineID.rawValue) quiet after \(ListenTimingLog.ms(since: waitStart)) ms (crash guard count=\(EngineCrashGuard.shared.crashCount))")
            let registry = coordinator.engines
            // Reverse descriptor order (recommended engine last).
            let descriptors = registry.localDescriptors.reversed().filter {
                registry.supports($0.id) && (request.engines?.contains($0.shortName.lowercased()) ?? true)
            }
            for descriptor in descriptors {
                await probe(descriptor, stressCalls: request.stressCalls, coordinator: coordinator, log: log)
            }
        }
        log("done")
    }

    /// One engine on a host of its own: init, the timed texts, the stress calls, then unload.
    private static func probe(_ descriptor: EngineDescriptor, stressCalls: Int?, coordinator: LocalTTSCoordinator,
                              log: (String) -> Void) async {
        let engine = descriptor.id
        let name = descriptor.shortName
        let installed = coordinator.isModelInstalled(engine)
        log("[\(name)] init start (models on disk=\(installed))")
        guard let limits = descriptor.onDevice?.limits,
              let made = coordinator.engines.makeHost(for: engine, voice: coordinator.voice(for: engine)),
              let host = LocalChunkRenderer(host: made, descriptor: descriptor) else {
            log("[\(name)] no host on this OS")
            return
        }
        if let routing = made.routingLabel { log("[\(name)] compute units=\(routing)") }
        let tInit = ListenTimingLog.now()
        do {
            try await host.prepare()
        } catch {
            log("[\(name)] init FAILED after \(ListenTimingLog.ms(since: tInit)) ms: \(error.localizedDescription)")
            return
        }
        let initMs = ListenTimingLog.ms(since: tInit)
        log("[\(name)] init_ms=\(initMs)")
        ListenTimingLog.log("engine_probe", ["engine": name, "step": "init", "ms": initMs, "on_disk": installed])

        let runs = texts + [("60-warm", texts[0].text)]
        for (label, text) in runs {
            let chunks = TextChunker.chunks(for: text, limits: limits)
            log("[\(name)] synth \(label) chars=\(text.count) chunks=\(chunks.count) start")
            let t0 = ListenTimingLog.now()
            var firstMs = 0
            var audio = 0.0
            do {
                for (i, chunk) in chunks.enumerated() {
                    let url = FileManager.default.temporaryDirectory
                        .appendingPathComponent("engine-probe-\(UUID().uuidString).caf")
                    defer { try? FileManager.default.removeItem(at: url) }
                    audio += try await host.renderChunk(text: chunk, to: url, request: ChunkRenderRequest(chunk: i))
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
        if let n = stressCalls {
            log("[\(name)] stress \(n)× 150-char calls start")
            let tS = ListenTimingLog.now()
            for i in 0..<n {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("engine-stress-\(i).caf")
                do {
                    _ = try await host.renderChunk(text: texts[1].text, to: url, request: ChunkRenderRequest(chunk: i))
                } catch {
                    log("[\(name)] stress call \(i) FAILED: \(error.localizedDescription)")
                }
                try? FileManager.default.removeItem(at: url)
                if i % 10 == 9 { log("[\(name)] stress \(i + 1)/\(n) ok (\(ListenTimingLog.ms(since: tS)) ms)") }
            }
        }
        await host.unload()
        log("[\(name)] unloaded")
    }
}
#endif
