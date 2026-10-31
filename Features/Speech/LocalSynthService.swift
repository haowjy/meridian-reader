import Foundation
import Observation

/// The on-device engine's model side, owned by `LocalTTSCoordinator`: its lifecycle
/// (`LocalEngineState`) and the one resident host behind the shared `LocalChunkRenderer`. The
/// render queue's worker is the only one that loads a host (`makeResident`, through the
/// coordinator) and renders through it (`SynthChunkRendering`); the listen player never touches
/// the model, it plays rendered files.
@MainActor
@Observable
final class LocalSynthService: SynthChunkRendering {
    /// Changed only by `setState(_:)`, which then calls `onStateChange`.
    private(set) var state: LocalEngineState = .off
    /// After every state change (including prepare progress while warming).
    @ObservationIgnored var onStateChange: (() -> Void)?

    @ObservationIgnored private let engines: EngineRegistry
    /// Where a guarded engine's calls leave their in-flight marker: the coordinator's, which reads
    /// it at the next launch.
    @ObservationIgnored private let crashGuard: EngineCrashGuard
    /// Engine whose host renders: the last one loaded (the default local engine before any load).
    @ObservationIgnored private(set) var engineID: SpeechEngineID
    @ObservationIgnored private var engineVoice: String?
    /// Host + renderer for `engineID` (nil until first use, and after an unload).
    @ObservationIgnored private var renderer: LocalChunkRenderer?
    /// The hosts let go, releasing their models (`LocalChunkRenderer.unload`). Every load waits
    /// for them first, so two hosts' models are never resident together (two ORT sessions are
    /// ≈1 GB).
    @ObservationIgnored private var retiring: Task<Void, Never>?

    init(engines: EngineRegistry, crashGuard: EngineCrashGuard) {
        self.engines = engines
        self.crashGuard = crashGuard
        self.engineID = engines.defaultEngine.id
    }

    var engineShortName: String { engines.shortName(engineID) }
    /// The engine whose host is loaded (`ready`; nil while none is, or one is loading).
    var residentEngineID: SpeechEngineID? { state.readyEngineID }
    /// Routing label of the live host (debug).
    var hostRoutingLabel: String? { renderer?.host.routingLabel }
    /// The live host keeps rendering in the background.
    var rendersInBackground: Bool { renderer?.host.rendersInBackground ?? false }

    // MARK: - Lifecycle

    /// Make `id`'s host the resident one: nothing to do when it is loaded, the load in flight
    /// awaited when it is loading (never a second load of it), else loaded (`load`). Throws when
    /// it ends anything but loaded: failed, cancelled (Settings' cancel), or replaced.
    /// The load runs at `priority`'s task priority (a listener's: `.userInitiated`; a preload's or
    /// bake-ahead's: `.utility`), and so does the host's load under it (`SingleFlightLoad`).
    func makeResident(_ id: SpeechEngineID, voice: String?, priority: RenderPriority) async throws {
        switch state {
        case .ready(id): return
        case .warming(id, _, let task): await task.value
        default: await load(id, voice: voice, priority: priority).value
        }
        switch state {
        case .ready(id): return
        case .failed(id, let message): throw LocalSynthError.engineUnavailable(message)
        default: throw LocalSynthError.engineUnavailable("\(engines.shortName(id)) didn’t load.")
        }
    }

    /// Load `id`'s host (cancelling any other load; the other engine's host is unloaded so only
    /// one model set is resident) and move to `.ready` / `.failed` when it settles. The returned
    /// task is the load; it is also held in `.warming`. A superseded load is cancelled by whoever
    /// replaced it and then leaves the state alone.
    private func load(_ id: SpeechEngineID, voice: String?, priority: RenderPriority) -> Task<Void, Never> {
        cancelLoad()
        use(id, voice: voice)
        let task = Task(priority: priority.taskPriority) { @MainActor [weak self] in
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

    /// Stop any load and drop the host (its model deleted; the render queue's `dropHost`). The
    /// next render that needs it loads a fresh one.
    func turnOff() {
        cancelLoad()
        setState(.off)
        unloadHost()
    }

    /// Settings: stop the model download / load in flight.
    func cancelDownload() {
        guard case .warming = state else { return }
        cancelLoad()
        unloadHost()
        setState(.off)
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
        guard engines.contains(id) else { return }
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
    /// models of their own. The render queue's next work loads a new host.
    func releaseHost() async {
        turnOff()
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
        if text.isEmpty { return "\(engines.shortName(engine)) couldn’t load. Pick one of its voices to try again." }
        return "\(engines.shortName(engine)): \(text)"
    }

    // MARK: - Rendering

    private func currentRenderer() throws -> LocalChunkRenderer {
        if let renderer, renderer.engineID == engineID { return renderer }
        guard let descriptor = engines.descriptor(engineID),
              let host = engines.makeHost(for: engineID, voice: engineVoice)
        else {
            throw LocalSynthError.engineUnavailable(
                engines.blockReason(engineID) ?? "\(engines.shortName(engineID)) isn’t available on this device.")
        }
        let made = LocalChunkRenderer(host: host, descriptor: descriptor, crashGuard: crashGuard)
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
    private func prepare() async throws {
        await waitForRetiredHosts()
        try await currentRenderer().prepare()
    }

    /// One synth chunk → CAF (render queue worker), on the resident host of `engineID` only: a
    /// render never loads a host or speaks in another engine. Re-splits internally on overflow.
    func renderChunkToFile(text: String, destination: URL, engineID: String,
                           request: ChunkRenderRequest) async throws -> TimeInterval {
        guard state.readyEngineID?.rawValue == engineID, let renderer, renderer.engineID.rawValue == engineID else {
            throw LocalSynthError.engineUnavailable("\(engines.shortName(SpeechEngineID(rawValue: engineID))) isn’t loaded.")
        }
        return try await renderer.renderChunk(text: text, to: destination, request: request)
    }
}
