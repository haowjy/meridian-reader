import Foundation
import Observation

/// The on-device engines' model side, owned by `LocalTTSCoordinator`: one resident host per lane
/// (`Lane`), each built for its route, with its lifecycle (`LocalEngineState`) behind the shared
/// `LocalChunkRenderer`. Loading on one lane never replaces another lane's host. The render
/// queue's worker is the only one that loads a host (`makeResident`, through the coordinator)
/// and renders through it (`SynthChunkRendering`); the listen player never touches the model, it
/// plays rendered files.
@MainActor
@Observable
final class LocalSynthService: SynthChunkRendering {
    /// Each lane's host lifecycle (absent: `.off`). Changed only by `setState(_:on:)`, which then
    /// calls `onStateChange`.
    private(set) var states: [Lane: LocalEngineState] = [:]
    /// After every state change (including prepare progress while warming).
    @ObservationIgnored var onStateChange: (() -> Void)?

    @ObservationIgnored private let engines: EngineRegistry
    /// Where a guarded engine's calls leave their in-flight marker: the coordinator's, which reads
    /// it at the next launch.
    @ObservationIgnored private let crashGuard: EngineCrashGuard

    /// A lane's host: the route it is built for (the last one loaded there), the voice it was
    /// asked for, and the host + renderer (nil until first use, and after an unload).
    private struct Slot {
        var route: RenderRoute
        var engineVoice: String?
        var renderer: LocalChunkRenderer?
    }

    @ObservationIgnored private var slots: [Lane: Slot] = [:]
    /// The hosts let go, on any lane, releasing their models (`LocalChunkRenderer.unload`). Every
    /// load waits for them first, so a load never overlaps the release it replaces (two ORT
    /// sessions are ≈1 GB), and one loaded alone finds the other lanes' memory free.
    @ObservationIgnored private var retiring: Task<Void, Never>?

    init(engines: EngineRegistry, crashGuard: EngineCrashGuard) {
        self.engines = engines
        self.crashGuard = crashGuard
    }

    func state(on lane: Lane) -> LocalEngineState { states[lane] ?? .off }

    /// `id`'s state across lanes, for what shows it (Settings): loading on any lane, else loaded on
    /// any, else failed on any, else off.
    func state(of id: SpeechEngineID) -> LocalEngineState {
        let all = Lane.allCases.map(state(on:))
        if let warming = all.first(where: { $0.warmingEngineID == id }) { return warming }
        if all.contains(where: { $0.readyEngineID == id }) { return .ready(id) }
        if let failed = all.first(where: { if case .failed(id, _) = $0 { true } else { false } }) { return failed }
        return .off
    }

    /// Some lane is loading a host.
    var isWarming: Bool { states.values.contains { $0.warmingEngineID != nil } }

    /// The engines with a host loaded on some lane.
    var loadedEngines: Set<SpeechEngineID> { Set(states.values.compactMap(\.readyEngineID)) }

    /// The route whose host is loaded on `lane` (`ready`; nil while none is, or one is loading).
    func residentRoute(on lane: Lane) -> RenderRoute? {
        guard let renderer = slots[lane]?.renderer, state(on: lane).readyEngineID == renderer.engineID else { return nil }
        return renderer.route
    }

    /// Routing labels of the live hosts (debug), "phonon-31m ane + phonon-31m cpu"; nil: none.
    var routingLabels: String? {
        let labels = Lane.allCases.compactMap { slots[$0]?.renderer?.host.routingLabel }
        return labels.isEmpty ? nil : labels.joined(separator: " + ")
    }

    /// Routing label of `id`'s live host (debug).
    func routingLabel(of id: SpeechEngineID) -> String? {
        Lane.allCases.lazy.compactMap { self.slots[$0]?.renderer }.first { $0.engineID == id }?.host.routingLabel
    }

    // MARK: - Lifecycle

    /// Make a host built for `route` the resident one on its lane: nothing to do when it is
    /// loaded, the load in flight awaited when it is loading (never a second load of it), else
    /// loaded (`load`). Throws when it ends anything but loaded: failed, cancelled (a dropped
    /// host), or replaced. The load runs at `priority`'s task priority (a listener's:
    /// `.userInitiated`; a preload's or bake-ahead's: `.utility`), and so does the host's load
    /// under it (`SingleFlightLoad`).
    func makeResident(_ route: RenderRoute, voice: String?, priority: RenderPriority) async throws {
        let (id, lane) = (route.engine, route.lane)
        if residentRoute(on: lane) == route { return }
        if case .warming(id, _, let task) = state(on: lane), slots[lane]?.route == route {
            await task.value
        } else {
            await load(route, voice: voice, priority: priority).value
        }
        if residentRoute(on: lane) == route { return }
        switch state(on: lane) {
        case .failed(id, let message): throw LocalSynthError.engineUnavailable(message)
        default: throw LocalSynthError.engineUnavailable("\(engines.shortName(id)) didn’t load.")
        }
    }

    /// Load a host for `route` on its lane (cancelling that lane's other load; that lane's host
    /// for another route is unloaded first) and move the lane to `.ready` / `.failed` when it
    /// settles. The returned task is the load; it is also held in `.warming`. A superseded load is
    /// cancelled by whoever replaced it and then leaves the state alone.
    private func load(_ route: RenderRoute, voice: String?, priority: RenderPriority) -> Task<Void, Never> {
        let (id, lane) = (route.engine, route.lane)
        cancelLoad(on: lane)
        use(route, voice: voice)
        let task = Task(priority: priority.taskPriority) { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.prepare(on: lane)
                guard !Task.isCancelled else { return }
                self.setState(.ready(id), on: lane)
            } catch {
                guard !Task.isCancelled else { return }
                self.setState(error is CancellationError
                    ? .off : .failed(id, message: self.friendlyError(error, engine: id)), on: lane)
            }
        }
        setState(.warming(id, progress: nil, task: task), on: lane)
        return task
    }

    /// Stop `lane`'s load and drop its host (its model deleted; the render queue's `dropHost`).
    /// The next render that needs it loads a fresh one.
    func turnOff(_ lane: Lane) {
        cancelLoad(on: lane)
        setState(.off, on: lane)
        unloadHost(on: lane)
    }

    /// The engine of `lane`'s host, loaded, loading or failed (nil: off).
    func engine(on lane: Lane) -> SpeechEngineID? { state(on: lane) == .off ? nil : slots[lane]?.route.engine }

    private func cancelLoad(on lane: Lane) {
        if case .warming(_, _, let task) = state(on: lane) { task.cancel() }
    }

    private func setState(_ new: LocalEngineState, on lane: Lane) {
        states[lane] = new
        onStateChange?()
    }

    /// Point `route`'s lane at it. Same route: forward a voice change to its host. Another route:
    /// unload the lane's old host (the load builds the new one).
    private func use(_ route: RenderRoute, voice: String?) {
        guard engines.contains(route.engine) else { return }
        let lane = route.lane
        let old = slots[lane]
        slots[lane] = Slot(route: route, engineVoice: voice, renderer: old?.renderer)
        if let renderer = old?.renderer, renderer.route == route {
            if voice != old?.engineVoice, let voice { renderer.host.setVoice(voice) }
            return
        }
        if let renderer = old?.renderer {
            ListenDebugLog.shared.append("unload \(renderer.route.id) host → \(route.id)")
        }
        unloadHost(on: lane)
    }

    /// Let `lane`'s host go: its load in flight stops, its models are released and the render in
    /// flight on it finishes; the next load or render waits for all of that, then builds a new one.
    private func unloadHost(on lane: Lane) {
        guard let old = slots[lane]?.renderer else { return }
        slots[lane]?.renderer = nil
        let earlier = retiring
        retiring = Task {
            await earlier?.value
            await old.unload()
        }
    }

    /// Let every host go and wait until their models are released: for diagnostics that load
    /// models of their own. The render queue's next work loads new hosts.
    func releaseHosts() async {
        for lane in Lane.allCases { turnOff(lane) }
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

    private func currentRenderer(on lane: Lane) throws -> LocalChunkRenderer {
        guard let slot = slots[lane] else { throw CancellationError() }
        if let renderer = slot.renderer, renderer.route == slot.route { return renderer }
        let route = slot.route
        guard let descriptor = engines.descriptor(route.engine),
              let host = engines.makeHost(for: route, voice: slot.engineVoice)
        else {
            throw LocalSynthError.engineUnavailable(
                engines.blockReason(route.engine) ?? "\(engines.shortName(route.engine)) isn’t available on this device.")
        }
        let made = LocalChunkRenderer(host: host, descriptor: descriptor, route: route, crashGuard: crashGuard)
        host.onProgress = { [weak self] fraction in
            Task { @MainActor in self?.noteLoadProgress(fraction, on: lane) }
        }
        slots[lane]?.renderer = made
        return made
    }

    private func noteLoadProgress(_ fraction: Double, on lane: Lane) {
        guard case .warming(let id, _, let task) = state(on: lane) else { return }
        setState(.warming(id, progress: fraction, task: task), on: lane)
    }

    /// Build and load `lane`'s host if needed (no-op once loaded), once every host let go has
    /// released its models.
    private func prepare(on lane: Lane) async throws {
        await waitForRetiredHosts()
        try await currentRenderer(on: lane).prepare()
    }

    /// One synth chunk → CAF (render queue worker), on `route`'s resident host only: a render
    /// never loads a host or speaks in another engine. Re-splits internally on overflow.
    func renderChunkToFile(text: String, destination: URL, route: RenderRoute,
                           request: ChunkRenderRequest) async throws -> TimeInterval {
        guard residentRoute(on: route.lane) == route, let renderer = slots[route.lane]?.renderer else {
            throw LocalSynthError.engineUnavailable("\(engines.shortName(route.engine)) isn’t loaded.")
        }
        return try await renderer.renderChunk(text: text, to: destination, request: request)
    }
}
