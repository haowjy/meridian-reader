import Foundation

/// A compute resource that runs model calls, one call or load at a time. Every engine renders on
/// the CPU; Phonon also declares a Neural Engine route, which only `LanePolicy` uses.
enum Lane: String, Sendable, Hashable, CaseIterable {
    case neuralEngine
    case cpu

    /// Whether calls may run on it with the app in the background: the Neural Engine is for the
    /// app in front.
    var runsInBackground: Bool { self == .cpu }

    /// Whether a model call may start on it in `phase`: what the plan check and the renderer at
    /// the model call (`LaneUnavailable`) both hold to.
    func runs(in phase: AppRunState.Phase) -> Bool { runsInBackground || phase != .background }
}

/// A model call refused at its start: its lane doesn't run in the app's phase now (the app left
/// the front between the plan and the call). Not the paragraph's failure: its listeners keep
/// waiting and the queue plans it again, for a lane that runs now.
struct LaneUnavailable: Error {
    let lane: Lane
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
    /// About how much its loaded host adds to the process's memory footprint, MB (measured on the
    /// phone): what a second model must find free to load beside another.
    let footprintMB: Int
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
/// paragraph of which job); the policy picks among units. A paragraph rendering on a lane is
/// never offered.
struct RenderCandidate: Sendable, Equatable {
    var item: UUID
    var paragraph: Int
    var demand: Demand
    /// The article's own engine: the only one whose routes are offered.
    var engine: SpeechEngineID
    /// The engine's routes it may render on.
    var routes: [RenderRoute]
    /// The engine's routes whose load failed (until a fresh try: a listener's request, a voice
    /// change, the host dropped). Whether the candidate waits or its listeners are told is the
    /// policy's (`RenderPlan.failed`).
    var failedRoutes: [RenderRoute] = []
}

/// What a lane is doing now. A lane runs one thing at a time: it takes an action only when free.
struct LaneSnapshot: Sendable, Equatable {
    enum Work: Sendable, Equatable {
        /// A model call on `route`, at `threads` (nil: a route that takes no count).
        case call(RenderRoute, threads: Int?)
        /// `alone`: no other lane takes work until it ends (`RenderPlan.Load.alone`).
        case load(RenderRoute, alone: Bool)
    }

    var work: Work?
    /// The route whose host is loaded on this lane (nil: none).
    var resident: RenderRoute?

    var isFree: Bool { work == nil }
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
    /// Every lane, free or not.
    var lanes: [Lane: LaneSnapshot]
    var cores: Int
    /// What the process may still allocate before iOS ends it, MB; nil where no limit applies
    /// (the Simulator).
    var availableMemoryMB: Int?

    /// The lanes with a host loaded other than `lane`.
    func otherResidents(than lane: Lane) -> [Lane] {
        lanes.compactMap { $0.key != lane && $0.value.resident != nil ? $0.key : nil }
    }
}

/// What to do now: one action per free lane the policy uses (none: those lanes wait for an event).
/// The queue starts each, and asks again when any call or load ends.
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
        /// Its host is built for this route and becomes its lane's resident one.
        var route: RenderRoute
        var priority: RenderPriority
        /// The candidate it loads for (nil: a preload).
        var candidate: Int?
        /// The other lanes' hosts go first: two models wouldn't fit (`LanePolicy`).
        var alone = false
    }

    enum Action: Sendable, Equatable {
        /// Run one model call.
        case start(Start)
        /// Load a route's host, replacing its lane's resident one.
        case load(Load)

        var lane: Lane {
            switch self {
            case .start(let start): start.route.lane
            case .load(let load): load.route.lane
            }
        }
    }

    var actions: [Lane: Action] = [:]
    /// Work waits for this hold to clear (the queue's log and debug line).
    var held: BakeConditions.Hold?
    /// Candidates whose listeners are told their chunk won't come: no route left that the policy
    /// would render them on (indices into `RenderSituation.candidates`). The queue fails their
    /// waiters with the failed load's error.
    var failed: [Int] = []

    /// What the scheduler refuses whatever the policy says (a broken one is a bug in the policy):
    /// a route is its candidate's own engine's (the voice is never swapped); an action runs on its
    /// route's lane, one of the policy's `lanes`, only while that lane is free, and only on a lane
    /// that runs in the app's phase; a call runs on its route's resident host; two calls never
    /// take the same paragraph; one load at a time, and one loading alone only while the other
    /// lanes are free (and nothing else starts while it runs); a failed candidate isn't also
    /// started.
    func violation(of situation: RenderSituation, lanes policyLanes: [Lane]) -> String? {
        func route(_ route: RenderRoute, of index: Int) -> String? {
            guard situation.candidates.indices.contains(index) else { return "no candidate \(index)" }
            let candidate = situation.candidates[index]
            guard route.engine == candidate.engine, candidate.routes.contains(route) else {
                return "route \(route.id) isn't \(candidate.engine.rawValue)'s"
            }
            return nil
        }
        var paragraphs = Set<String>()
        var loads = 0
        for (lane, snapshot) in situation.lanes {
            guard case .load(_, let alone)? = snapshot.work else { continue }
            loads += 1
            if alone, !actions.isEmpty { return "\(lane.rawValue) loads alone" }
        }
        for index in failed where !situation.candidates.indices.contains(index) { return "no candidate \(index)" }
        for (lane, action) in actions {
            guard action.lane == lane else { return "\(lane.rawValue) can't run a \(action.lane.rawValue) route" }
            guard policyLanes.contains(lane) else { return "\(lane.rawValue) isn't the policy's" }
            guard situation.lanes[lane]?.isFree == true else { return "\(lane.rawValue) is busy" }
            switch action {
            case .start(let start):
                if let wrong = route(start.route, of: start.candidate) { return wrong }
                if !lane.runs(in: situation.phase) {
                    return "\(lane.rawValue) doesn't run in the background"
                }
                guard situation.lanes[lane]?.resident == start.route else {
                    return "\(start.route.id) isn't loaded on \(lane.rawValue)"
                }
                let candidate = situation.candidates[start.candidate]
                guard paragraphs.insert("\(candidate.item)|\(candidate.paragraph)").inserted else {
                    return "two calls on \(candidate.item) p\(candidate.paragraph)"
                }
                if failed.contains(start.candidate) { return "candidate \(start.candidate) fails and starts" }
            case .load(let load):
                if let index = load.candidate {
                    if let wrong = route(load.route, of: index) { return wrong }
                } else if !situation.preload.contains(load.route) {
                    return "route \(load.route.id) wasn't asked to preload"
                }
                loads += 1
                if loads > 1 { return "two loads at once" }
                if load.alone, actions.count > 1 || situation.lanes.contains(where: { $0.key != lane && !$0.value.isFree }) {
                    return "\(load.route.id) loads alone while another lane works"
                }
            }
        }
        return nil
    }
}

/// Decides what renders next from a snapshot: no I/O, no engines, no clock of its own. The
/// render queue asks it whenever one of its lanes may be free. A new policy is one type and the
/// line in `AppComposition.makeRenderPolicy`.
@MainActor
protocol RenderPolicy: AnyObject {
    var name: String { get }
    /// The lanes it plans for: the queue asks it only while one of them is free, and refuses an
    /// action on another.
    var lanes: [Lane] { get }
    func plan(_ situation: RenderSituation) -> RenderPlan
}

extension RenderSituation {
    /// The candidates' indices in demand order, the queue's order within a demand.
    var urgencyOrder: [Int] {
        candidates.indices.sorted {
            (candidates[$0].demand.rawValue, $0) < (candidates[$1].demand.rawValue, $1)
        }
    }

    /// The listeners' candidates none of `lanes` can render, their engine's route there having
    /// failed to load: what a policy that renders only on `lanes` tells them (`RenderPlan.failed`).
    func unservable(on lanes: [Lane]) -> [Int] {
        candidates.indices.filter { index in
            let candidate = candidates[index]
            return candidate.demand == .listener && !candidate.failedRoutes.isEmpty
                && !candidate.routes.contains { lanes.contains($0.lane) }
        }
    }
}
