import Foundation
import Observation

/// The on-device engine's model side, owned by `LocalTTSCoordinator`: its lifecycle
/// (`LocalEngineState`), the one resident host behind the shared `LocalChunkRenderer`, and the
/// Apple renderer for text the engine can't produce in time. The render queue renders through it
/// (`SynthChunkRendering`); the listen player never touches the model, it plays rendered files.
@MainActor
@Observable
final class LocalSynthService: SynthChunkRendering {
    /// Changed only by `setState(_:)`, which then calls `onStateChange`.
    private(set) var state: LocalEngineState = .off
    /// After every state change (including download progress while warming).
    @ObservationIgnored var onStateChange: (() -> Void)?

    @ObservationIgnored private let engines: EngineRegistry
    /// Engine whose host renders: the last one loaded (the default local engine before any load).
    @ObservationIgnored private(set) var engineID: SpeechEngineID
    @ObservationIgnored private var engineVoice: String?
    /// Host + renderer for `engineID` (nil until first use, and after an unload).
    @ObservationIgnored private var renderer: LocalChunkRenderer?
    @ObservationIgnored private let appleRenderer = ProbePCMRenderer()

    init(engines: EngineRegistry) {
        self.engines = engines
        self.engineID = engines.defaultLocalEngineID
    }

    var engineShortName: String { engines.shortName(engineID) }
    /// Routing label of the live host (debug).
    var hostRoutingLabel: String? { renderer?.host.routingLabel }
    /// The live host keeps rendering in the background (Kokoro ONNX CPU route).
    var rendersInBackground: Bool { renderer?.host.rendersInBackground ?? false }

    /// The live renderer if it is already built for `id`. The latency probe and the CPU bench
    /// reuse it: two loaded Kokoro Core ML instances make predictions fail on device.
    func liveRenderer(for id: SpeechEngineID) -> LocalChunkRenderer? {
        guard let renderer, renderer.engineID == id else { return nil }
        return renderer
    }

    // MARK: - Lifecycle

    /// Load `id`'s host (cancelling any other load; the other engine's host is unloaded so only
    /// one model set is resident) and move to `.ready` / `.failed` when it settles. The returned
    /// task is the load; it is also held in `.warming`. A superseded load is cancelled by whoever
    /// replaced it and then leaves the state alone.
    @discardableResult
    func load(_ id: SpeechEngineID, voice: String?) -> Task<Void, Never> {
        cancelLoad()
        use(id, voice: voice)
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.prepare()
                guard !Task.isCancelled else { return }
                self.setState(.ready(id))
            } catch {
                guard !Task.isCancelled else { return }
                self.setState(error is CancellationError
                    ? .off : .failed(id, message: self.friendlyError(error, engine: id)))
            }
        }
        setState(.warming(id, progress: nil, task: task))
        return task
    }

    /// Drop the live host and load `id` again (route or thread change). Cached audio stays.
    @discardableResult
    func reload(_ id: SpeechEngineID, voice: String?) -> Task<Void, Never> {
        cancelLoad()
        unloadHost()
        return load(id, voice: voice)
    }

    /// Apple selected, or the model deleted: stop any load and drop the host.
    func turnOff() {
        cancelLoad()
        setState(.off)
        unloadHost()
    }

    /// `id` can't run on this device.
    func markUnavailable(_ id: SpeechEngineID) {
        cancelLoad()
        setState(.failed(id, message: engines.blockReason(id) ?? "\(engines.displayName(id)) is not available on this device."))
    }

    /// Settings: stop the model download / load in flight; Apple speaks.
    func cancelDownload() {
        guard case .warming = state else { return }
        cancelLoad()
        resetHost()
        setState(.off)
    }

    /// The live listen could not start on the engine: drop its host and let Apple speak.
    func noteSpeakFailed(_ error: Error) {
        guard let id = state.readyEngineID else { return }
        resetHost()
        setState(.failed(id, message: friendlyError(error, engine: id)))
    }

    /// The selected voice of the loaded engine changed.
    func setVoice(_ voice: String, for id: SpeechEngineID) {
        guard id == engineID else { return }
        use(id, voice: voice)
    }

    private func cancelLoad() {
        if case .warming(_, _, let task) = state { task.cancel() }
    }

    private func setState(_ new: LocalEngineState) {
        state = new
        onStateChange?()
    }

    /// Point the service at `id`. Same engine: forward a voice change to its host. Another engine:
    /// unload the old host (the next render or load builds the new one).
    private func use(_ id: SpeechEngineID, voice: String?) {
        guard engines.isOnDevice(id) else { return }
        let voiceChanged = voice != engineVoice
        engineVoice = voice
        if let renderer, renderer.engineID == id {
            if voiceChanged, let voice { renderer.host.setVoice(voice) }
            engineID = id
            return
        }
        if let old = renderer {
            ListenDebugLog.shared.append("unload \(engines.shortName(old.engineID)) host → \(engines.shortName(id))")
        }
        unloadHost()
        engineID = id
    }

    private func unloadHost() {
        guard let old = renderer else { return }
        renderer = nil
        Task { await old.host.unload() }
    }

    private func resetHost() {
        renderer?.host.resetPrepared()
        renderer = nil
    }

    private func friendlyError(_ error: Error, engine: SpeechEngineID) -> String {
        if let reason = engines.blockReason(engine) { return reason }
        let text = error.localizedDescription
        if text.isEmpty { return "\(engines.displayName(engine)) failed to load. Tap to retry." }
        return "\(engines.shortName(engine)): \(text)"
    }

    // MARK: - Rendering

    private func currentRenderer() throws -> LocalChunkRenderer {
        if let renderer, renderer.engineID == engineID { return renderer }
        guard let descriptor = engines.descriptor(engineID),
              let host = engines.makeHost(for: engineID, voice: engineVoice),
              let made = LocalChunkRenderer(host: host, descriptor: descriptor)
        else {
            throw LocalSynthError.engineUnavailable(
                engines.blockReason(engineID) ?? "\(engines.displayName(engineID)) is not available on this device.")
        }
        host.onProgress = { [weak self] fraction in
            Task { @MainActor in self?.noteLoadProgress(fraction) }
        }
        renderer = made
        return made
    }

    private func noteLoadProgress(_ fraction: Double) {
        guard case .warming(let id, _, let task) = state else { return }
        setState(.warming(id, progress: fraction, task: task))
    }

    /// Build and load the host if needed (no-op once loaded).
    func prepare() async throws {
        try await currentRenderer().prepare()
    }

    /// One synth chunk → CAF (render queue worker). Re-splits internally on overflow.
    func renderChunkToFile(text: String, destination: URL, context: [String: Any],
                           priority: RenderPriority) async throws -> TimeInterval {
        try await prepare()
        return try await currentRenderer().renderChunk(text: text, to: destination, context: context, priority: priority)
    }

    /// Apple TTS render of `text` (the engine couldn't produce it): `voiceID`, else the system
    /// voice for US English.
    func renderAppleFallback(text: String, destination: URL, voiceID: String?) async throws -> TimeInterval {
        try await appleRenderer.render(text: text, to: destination, voiceID: voiceID, language: "en-US")
    }
}
