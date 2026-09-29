import Foundation

/// Engine-agnostic render pipeline around one `LocalSynthHost`:
/// normalize → prepare → `SynthRenderGate` → call (with `EngineCrashGuard` if the engine is
/// crash-guarded) → on `LocalSynthError.inputTooLong` re-split (≈halves, down to the engine's
/// `minResplit`) and recurse → write 24 kHz mono CAF. Every model call is logged (`synth`).
final class LocalChunkRenderer: Sendable {
    let host: LocalSynthHost
    let descriptor: EngineDescriptor
    private let gate: SynthRenderGate
    private let crashGuard: EngineCrashGuard?
    /// Checked right before every model call: nothing starts while backgrounded.
    private let runState: AppRunState
    static let maxResplitDepth = 5

    init(host: LocalSynthHost, descriptor: EngineDescriptor,
         gate: SynthRenderGate = .shared, crashGuard: EngineCrashGuard = .shared,
         runState: AppRunState = .shared) {
        self.host = host
        self.descriptor = descriptor
        self.gate = gate
        self.runState = runState
        self.crashGuard = descriptor.crashGuarded ? crashGuard : nil
    }

    var engineID: SpeechEngineID { descriptor.id }

    func prepare() async throws {
        if !host.isPrepared { try await host.prepare() }
    }

    /// Synthesize ONE chunk (already sized by `TextChunker` with `descriptor.limits`) → CAF.
    func renderChunk(text: String, to destination: URL, seed: UInt64, context: [String: Any]) async throws -> TimeInterval {
        let trimmed = TextChunker.normalize(text)
        guard !trimmed.isEmpty else { throw LocalSynthError.emptyText }
        try await prepare()
        await gate.acquire()
        do {
            try Task.checkCancellation()
            var pcm = try await synthesizeResilient(trimmed, seed: seed, depth: 0, context: context)
            if host.trimsEdgeSilence {
                // Join pauses sized to the cut (sentence / clause / word / paragraph end).
                let boundary = ChunkEdgeTrim.boundary(after: trimmed, nextWord: context["nextWord"] as? String,
                                                      isLastInParagraph: context["last"] as? Bool ?? true)
                pcm.samples = ChunkEdgeTrim.trim(pcm.samples, sampleRate: pcm.sampleRate,
                                                 trailMs: ChunkEdgeTrim.trailMs(boundary))
            }
            try LocalPCMWriter.write(pcm.samples, sampleRate: pcm.sampleRate, to: destination)
            await gate.release()
            return pcm.duration
        } catch {
            await gate.release()
            throw error
        }
    }

    /// Arbitrary text (chunked with the engine's limits) → one CAF. Legacy live / probe path.
    func render(text: String, to destination: URL, seed: UInt64) async throws -> TimeInterval {
        let chunks = TextChunker.chunks(for: text, limits: descriptor.limits)
        guard !chunks.isEmpty else { throw LocalSynthError.emptyText }
        try await prepare()
        await gate.acquire()
        do {
            var all: [Float] = []
            var rate = 24_000
            for (i, chunk) in chunks.enumerated() {
                try Task.checkCancellation()
                var part = try await synthesizeResilient(chunk, seed: seed &+ UInt64(i), depth: 0, context: ["c": i])
                rate = part.sampleRate
                if host.trimsEdgeSilence {
                    let next = i + 1 < chunks.count ? chunks[i + 1].split(separator: " ").first.map(String.init) : nil
                    let b = ChunkEdgeTrim.boundary(after: chunk, nextWord: next, isLastInParagraph: i == chunks.count - 1)
                    part.samples = ChunkEdgeTrim.trim(part.samples, sampleRate: rate, trailMs: ChunkEdgeTrim.trailMs(b))
                }
                all.append(contentsOf: part.samples)
            }
            try LocalPCMWriter.write(all, sampleRate: rate, to: destination)
            await gate.release()
            return rate > 0 ? Double(all.count) / Double(rate) : 0
        } catch {
            await gate.release()
            throw error
        }
    }

    /// One call; on overflow split and recurse. Caller holds the gate.
    func synthesizeResilient(_ text: String, seed: UInt64, depth: Int, context: [String: Any]) async throws -> SynthesizedPCM {
        try Task.checkCancellation()
        // Last line of defense (the queue checks first): never start a Core ML call in the
        // background — no GPU there, and CPU fallback is the libBNNS crash path (#844). Hosts
        // that don't use Core ML at all (ONNX CPU route) keep rendering while audio plays.
        guard runState.allowsLocalModelCalls || host.rendersInBackground else {
            ListenTimingLog.log("synth_blocked_bg", ["engine": descriptor.shortName.lowercased(), "chars": text.count])
            throw LocalSynthError.deferredInBackground
        }
        let t0 = ListenTimingLog.now()
        var fields = context
        fields["engine"] = descriptor.shortName.lowercased()
        fields["chars"] = text.count
        fields["depth"] = depth
        if let route = host.routeTag { fields["route"] = route }
        fields["phase"] = runState.phase.rawValue
        let article = fields.removeValue(forKey: "article") as? String
        crashGuard?.beginCall(engine: descriptor.id, chars: text.count,
                              context: "\(context["key"] ?? "")/p\(context["p"] ?? -1)",
                              route: host.routeTag, article: article, paragraph: context["p"] as? Int,
                              phase: runState.phase.rawValue)
        do {
            let pcm = try await host.synthesizeOnce(text: text, seed: seed)
            crashGuard?.endCall()
            let wall = ListenTimingLog.now() - t0
            fields["wall_ms"] = ListenTimingLog.ms(since: t0)
            fields["audio_s"] = (pcm.duration * 100).rounded() / 100
            if wall > 0 { fields["rtf"] = (pcm.duration / wall * 100).rounded() / 100 }
            RenderPace.shared.record(audioSeconds: pcm.duration, wallSeconds: wall)
            fields["ok"] = true
            fields.merge(pcm.metrics) { a, _ in a }
            ListenTimingLog.log("synth", fields)
            return pcm
        } catch {
            crashGuard?.endCall()
            fields["wall_ms"] = ListenTimingLog.ms(since: t0)
            fields["ok"] = false
            fields["err"] = error.localizedDescription
            ListenTimingLog.log("synth", fields)
            guard case LocalSynthError.inputTooLong = error else { throw error }
            let pieces = TextChunker.resplit(text, minResplit: descriptor.limits.minResplit)
            guard pieces.count > 1, depth < Self.maxResplitDepth else { throw error }
            var merged = SynthesizedPCM(samples: [], sampleRate: 24_000)
            for (i, piece) in pieces.enumerated() {
                let part = try await synthesizeResilient(
                    piece, seed: seed &+ UInt64(i + 1) &* 7919, depth: depth + 1, context: context)
                merged.sampleRate = part.sampleRate
                merged.samples.append(contentsOf: part.samples)
            }
            return merged
        }
    }
}
