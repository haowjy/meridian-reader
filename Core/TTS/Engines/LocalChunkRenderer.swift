import Foundation

/// One chunk for `LocalChunkRenderer`: where it sits, for the join trim, the crash marker and the
/// timing log.
struct ChunkRenderRequest: Sendable {
    /// The article and paragraph the chunk is part of; nil for the engine probe's text.
    var article: UUID? = nil
    var paragraph: Int? = nil
    var chunk: Int
    var isLastInParagraph = true
    /// The next chunk's first word: a cut before "and/but/which…" is a clause join (`ChunkEdgeTrim`).
    var nextWord: String? = nil
    var priority: RenderPriority = .listener
    /// The render queue's front job.
    var isPrimary = false
    /// C138: the engine voice to speak in (the article's own); nil: the host's current voice.
    var voice: String? = nil

    /// What every timing-log line about this chunk carries.
    var logFields: [String: Any] {
        guard let article else { return ["probe": true, "c": chunk] }
        return ["key": ListenTimingLog.shortKey(article), "p": paragraph ?? -1, "c": chunk,
                "primary": isPrimary, "bake_ahead": priority == .bakeAhead]
    }
}

/// Engine-agnostic render pipeline around one `LocalSynthHost`:
/// shared normalize → prepare → `SynthRenderGate` → call (with `EngineCrashGuard` if the engine is
/// crash-guarded) → on `LocalSynthError.inputTooLong` re-split (≈halves, down to the engine's
/// `minResplit`) and recurse → write 24 kHz mono CAF. Every model call is logged (`synth`).
/// Host-specific spoken-text tweaks (`LocalSynthHost.spokenText(forChunk:)`) run here at render
/// so planned chunks still reassemble to normalize(paragraph).
final class LocalChunkRenderer: Sendable {
    let host: LocalSynthHost
    let descriptor: EngineDescriptor
    private let limits: TextChunker.Limits
    private let gate: SynthRenderGate
    private let crashGuard: EngineCrashGuard?
    /// Checked right before every model call: nothing starts while backgrounded.
    private let runState: AppRunState
    static let maxResplitDepth = 5

    /// nil for an engine that isn't on-device (no `OnDeviceTraits`).
    init?(host: LocalSynthHost, descriptor: EngineDescriptor,
          gate: SynthRenderGate = .shared, crashGuard: EngineCrashGuard = .shared,
          runState: AppRunState = .shared) {
        guard let traits = descriptor.onDevice else { return nil }
        self.host = host
        self.descriptor = descriptor
        self.limits = traits.limits
        self.gate = gate
        self.runState = runState
        self.crashGuard = traits.crashNotice != nil ? crashGuard : nil
    }

    var engineID: SpeechEngineID { descriptor.id }

    func prepare() async throws {
        if !host.isPrepared { try await host.prepare() }
    }

    /// Release the host's models for good (`LocalSynthHost.unload`), then wait out the model
    /// call in flight on it (it holds the gate), so nothing uses them once this returns.
    func unload() async {
        await host.unload()
        await gate.acquire()
        await gate.release()
    }

    /// Synthesize ONE chunk (already sized by `TextChunker` with the engine's limits) → CAF.
    func renderChunk(text: String, to destination: URL, request: ChunkRenderRequest) async throws -> TimeInterval {
        let trimmed = TTSTextNormalize.normalize(text)
        guard !trimmed.isEmpty else { throw LocalSynthError.emptyText }
        try await prepare()
        await gate.acquire()
        do {
            try Task.checkCancellation()
            let boundary = ChunkEdgeTrim.boundary(after: trimmed, nextWord: request.nextWord,
                                                  isLastInParagraph: request.isLastInParagraph)
            // Host may tweak spoken text (e.g. close open-ended cuts); edge trim stays audio-only.
            let spoken = host.spokenText(forChunk: trimmed)
            var pcm = try await synthesizeResilient(spoken, depth: 0, request: request)
            if host.trimsEdgeSilence {
                // Join pauses sized to the cut (sentence / clause / word / paragraph end).
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

    /// One call; on overflow split and recurse. Caller holds the gate.
    func synthesizeResilient(_ text: String, depth: Int, request: ChunkRenderRequest) async throws -> SynthesizedPCM {
        try Task.checkCancellation()
        // Last line of defense (the queue decides first): the hard rule of `RenderAdmission`.
        guard RenderAdmission.modelCallsAllowed(phase: runState.phase, rendersInBackground: host.rendersInBackground) else {
            ListenTimingLog.log("synth_blocked_bg", ["engine": descriptor.shortName.lowercased(), "chars": text.count])
            throw LocalSynthError.deferredInBackground
        }
        // C138: the article's voice, set under the gate right before every call.
        if let voice = request.voice { host.setVoice(voice) }
        let t0 = ListenTimingLog.now()
        let phase = runState.phase
        var fields = request.logFields
        if let voice = request.voice { fields["voice"] = voice }
        fields["engine"] = descriptor.shortName.lowercased()
        fields["chars"] = text.count
        fields["depth"] = depth
        if let route = host.routeTag { fields["route"] = route }
        fields["phase"] = phase.rawValue
        crashGuard?.beginCall(engine: descriptor.id, chars: text.count, route: host.routeTag,
                              article: request.article, paragraph: request.paragraph, phase: phase)
        let priority = request.priority
        do {
            let pcm = try await host.synthesizeOnce(text: text, priority: priority)
            crashGuard?.endCall()
            let wall = ListenTimingLog.now() - t0
            fields["wall_ms"] = ListenTimingLog.ms(since: t0)
            fields["audio_s"] = (pcm.duration * 100).rounded() / 100
            if wall > 0 { fields["rtf"] = (pcm.duration / wall * 100).rounded() / 100 }
            // The pace feeds the listener's head-start rule: bake-ahead runs at a lower QoS and
            // would make the worker look slower than it is for a listener.
            if priority == .listener { RenderPace.shared.record(audioSeconds: pcm.duration, wallSeconds: wall) }
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
            let pieces = TextChunker.resplit(text, minResplit: limits.minResplit)
            guard pieces.count > 1, depth < Self.maxResplitDepth else { throw error }
            var merged = SynthesizedPCM(samples: [], sampleRate: 24_000)
            for piece in pieces {
                let part = try await synthesizeResilient(piece, depth: depth + 1, request: request)
                merged.sampleRate = part.sampleRate
                merged.samples.append(contentsOf: part.samples)
            }
            return merged
        }
    }
}
