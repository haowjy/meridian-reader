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
    /// The engine whose model is loaded for this lane (nil: none).
    var resident: SpeechEngineID?
}

/// Everything a render decision may depend on, as values.
struct RenderSituation: Sendable, Equatable {
    var phase: AppRunState.Phase
    /// Audio is playing: in the background, the app is kept alive only then.
    var audioPlaying: Bool
    /// Thermal state or Low Power Mode holds work nobody is listening to (`BakeConditions`).
    var hold: BakeConditions.Hold?
    /// An engine asked to be loaded once nothing renders (the launch's preload).
    var preload: SpeechEngineID?
    /// In the queue's order.
    var candidates: [RenderCandidate]
    var lanes: [Lane: LaneSnapshot]
    var maxCallsInFlight: Int
    var cores: Int
}

/// What to do now: calls to start, models to load, or nothing.
struct RenderPlan: Sendable, Equatable {
    struct Start: Sendable, Equatable {
        /// Index into `RenderSituation.candidates`.
        var candidate: Int
        var route: RenderRoute
        /// For a route that takes a count; nil for one that can't.
        var threads: Int?
        var priority: RenderPriority
    }

    struct Load: Sendable, Equatable {
        var engine: SpeechEngineID
        var lane: Lane
        var priority: RenderPriority
        /// The candidate it loads for (nil: a preload).
        var candidate: Int?
    }

    var starts: [Start] = []
    var loads: [Load] = []
    /// Work waits for this hold to clear (the queue's log and debug line).
    var held: BakeConditions.Hold?

    /// What the scheduler refuses whatever the policy says (a broken one is a bug in the
    /// policy): a start's route is its candidate's own engine's (the voice is never swapped),
    /// runs on that engine's resident lane, and no more calls run than `maxCallsInFlight`.
    func violation(of situation: RenderSituation) -> String? {
        let inFlight = situation.lanes.values.reduce(0) { $0 + $1.callsInFlight }
        if inFlight + starts.count > situation.maxCallsInFlight { return "more calls than \(situation.maxCallsInFlight)" }
        for start in starts {
            guard situation.candidates.indices.contains(start.candidate) else { return "no candidate \(start.candidate)" }
            let candidate = situation.candidates[start.candidate]
            guard start.route.engine == candidate.engine, candidate.routes.contains(start.route) else {
                return "route \(start.route.id) isn't \(candidate.engine.rawValue)'s"
            }
            guard situation.lanes[start.route.lane]?.resident == candidate.engine else {
                return "\(candidate.engine.rawValue) isn't loaded on \(start.route.lane.rawValue)"
            }
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
