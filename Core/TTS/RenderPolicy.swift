import Foundation

/// A compute resource that runs model calls. One today: every engine renders on the CPU. A Neural
/// Engine or GPU lane is a new case plus a policy that uses it; the queue, the renderer, the crash
/// guard and the cache don't change.
enum Lane: String, Sendable, Hashable, CaseIterable {
    case cpu
}

/// Whether a route can be told how many threads a call may use.
enum ThreadControl: Sendable, Equatable {
    /// Takes a thread count (ONNX intra-op threads; the host rebuilds its session when the count
    /// changes). `cap`: the most it may use.
    case honored(cap: Int)
    /// Can't be told one (Core ML).
    case uncapped
}

/// One way an engine runs, declared by its provider (`SpeechEngineProvider.routes`). Facts only.
struct RenderRoute: Sendable, Equatable, Identifiable {
    let id: String
    let engine: SpeechEngineID
    let lane: Lane
    let threads: ThreadControl
}

/// Why a unit renders, most urgent first.
enum Demand: Int, Sendable, Comparable {
    /// The player waits for a chunk of this paragraph.
    case listener
    /// The article playing, from its playhead on.
    case playing
    /// The opening of the chapter staged to play next.
    case staged
    /// Everything else: saves, prepares, gap fill, the playing article above its playhead.
    case queued

    static func < (a: Demand, b: Demand) -> Bool { a.rawValue < b.rawValue }
}

/// One unit the render queue would render next, with its demand. The queue picks the unit (which
/// paragraph of which job); the policy picks among units.
struct RenderCandidate: Sendable, Equatable {
    var item: UUID
    var paragraph: Int
    var demand: Demand
    /// The article's own engine: the only one whose routes are offered.
    var engine: SpeechEngineID
    var routes: [RenderRoute]
}

/// What runs on a lane now.
struct LaneSnapshot: Sendable, Equatable {
    var callsInFlight = 0
    /// The route whose host is loaded on this lane (nil: none).
    var resident: RenderRoute?
}

/// Everything a render decision may depend on, as values.
struct RenderSituation: Sendable, Equatable {
    var phase: AppRunState.Phase
    /// Audio is playing: in the background, the app is kept alive only then.
    var audioPlaying: Bool
    /// Thermal state or Low Power Mode holds work nobody is listening to (`BakeConditions`).
    var hold: BakeConditions.Hold?
    /// The routes of an engine asked to be loaded once nothing renders (the launch's preload);
    /// empty: none.
    var preload: [RenderRoute]
    /// In the queue's order: each job's next unit per demand.
    var candidates: [RenderCandidate]
    var lanes: [Lane: LaneSnapshot]
    var maxCallsInFlight: Int
    var cores: Int
}

/// What to do now: the one action the queue's worker takes before it asks again.
enum RenderPlan: Sendable, Equatable {
    struct Start: Sendable, Equatable {
        /// Index into `RenderSituation.candidates`.
        var candidate: Int
        var route: RenderRoute
        /// For a route that takes a count; nil for one that can't.
        var threads: Int?
        var priority: RenderPriority
    }

    struct Load: Sendable, Equatable {
        /// Its host is built for this route and becomes its lane's resident one.
        var route: RenderRoute
        var priority: RenderPriority
        /// The candidate it loads for (nil: a preload).
        var candidate: Int?
    }

    /// Run one model call.
    case start(Start)
    /// Load a route's host, replacing its lane's resident one.
    case load(Load)
    /// Work waits for this hold to clear (the queue's log and debug line).
    case held(BakeConditions.Hold)
    /// Nothing now: the worker stops until an event kicks it.
    case idle

    /// What the scheduler refuses whatever the policy says (a broken one is a bug in the
    /// policy): a route is its candidate's own engine's (the voice is never swapped); a call runs
    /// on its route's resident host, no more calls run than `maxCallsInFlight`; a load replaces a
    /// lane's host only while no call runs on it.
    func violation(of situation: RenderSituation) -> String? {
        func route(_ route: RenderRoute, of index: Int) -> String? {
            guard situation.candidates.indices.contains(index) else { return "no candidate \(index)" }
            let candidate = situation.candidates[index]
            guard route.engine == candidate.engine, candidate.routes.contains(route) else {
                return "route \(route.id) isn't \(candidate.engine.rawValue)'s"
            }
            return nil
        }
        switch self {
        case .start(let start):
            let inFlight = situation.lanes.values.reduce(0) { $0 + $1.callsInFlight }
            if inFlight + 1 > situation.maxCallsInFlight { return "more calls than \(situation.maxCallsInFlight)" }
            if let wrong = route(start.route, of: start.candidate) { return wrong }
            guard situation.lanes[start.route.lane]?.resident == start.route else {
                return "\(start.route.id) isn't loaded on \(start.route.lane.rawValue)"
            }
        case .load(let load):
            if let index = load.candidate {
                if let wrong = route(load.route, of: index) { return wrong }
            } else if !situation.preload.contains(load.route) {
                return "route \(load.route.id) wasn't asked to preload"
            }
            if situation.lanes[load.route.lane]?.callsInFlight ?? 0 > 0 {
                return "a call runs on \(load.route.lane.rawValue)"
            }
        case .held, .idle:
            break
        }
        return nil
    }
}

/// Decides what renders next from a snapshot: no I/O, no engines, no clock of its own. The
/// render queue asks it before every call. A new policy is one type and the line in
/// `AppComposition.makeRenderPolicy`.
@MainActor
protocol RenderPolicy: AnyObject {
    var name: String { get }
    func plan(_ situation: RenderSituation) -> RenderPlan
}
