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
    /// The hosts let go, releasing their models (`LocalChunkRenderer.unload`). Every load waits
    /// for them first, so two hosts' models are never resident together (two ORT sessions are
    /// ≈1 GB).
    @ObservationIgnored private var retiring: Task<Void, Never>?
    @ObservationIgnored private let appleRenderer = AppleFallbackRenderer()

    init(engines: EngineRegistry) {
        self.engines = engines
        self.engineID = engines.defaultLocalEngineID
    }

    var engineShortName: String { engines.shortName(engineID) }
    /// Routing label of the live host (debug).
    var hostRoutingLabel: String? { renderer?.host.routingLabel }
    /// Route tag of the live host ("onnx", "coreml"; nil when none is built).
    var hostRouteTag: String? { renderer?.host.routeTag }
    /// The live host keeps rendering in the background (Kokoro ONNX CPU route).
    var rendersInBackground: Bool { renderer?.host.rendersInBackground ?? false }

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
        unloadHost()
        setState(.off)
    }

    /// The live listen could not start on the engine: drop its host and let Apple speak.
    func noteSpeakFailed(_ error: Error) {
        guard let id = state.readyEngineID else { return }
        unloadHost()
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

    /// Let the live host go: its load in flight stops, its models are released and the render in
    /// flight on it finishes; the next load or render waits for all of that, then builds a new one.
    private func unloadHost() {
        guard let old = renderer else { return }
        renderer = nil
        let earlier = retiring
        retiring = Task {
            await earlier?.value
            await old.unload()
        }
    }

    /// Let the live host go and wait until its models are released: for diagnostics that load
    /// models of their own. The next render builds and loads a new host.
    func releaseHost() async {
        unloadHost()
        await waitForRetiredHosts()
    }

    private func waitForRetiredHosts() async {
        while let pending = retiring {
            await pending.value
            if retiring == pending { retiring = nil }
        }
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

    /// Build and load the host if needed (no-op once loaded), once every host let go has
    /// released its models.
    func prepare() async throws {
        await waitForRetiredHosts()
        try await currentRenderer().prepare()
    }

    /// One synth chunk → CAF (render queue worker). Re-splits internally on overflow.
    func renderChunkToFile(text: String, destination: URL, request: ChunkRenderRequest) async throws -> TimeInterval {
        try await prepare()
        return try await currentRenderer().renderChunk(text: text, to: destination, request: request)
    }

    /// Apple TTS render of `text` (the engine couldn't produce it): `voiceID`, else the system
    /// voice for US English. Throws when Apple fails too, or stops responding.
    func renderAppleFallback(text: String, destination: URL, voiceID: String?) async throws -> TimeInterval {
        try await appleRenderer.render(text: text, to: destination, voiceID: voiceID)
    }
}
