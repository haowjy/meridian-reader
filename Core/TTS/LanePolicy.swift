import Foundation

/// Two lanes in front, the CPU alone in the background. Chosen by a Debug launch only
/// (`-renderPolicy lanes`); the app's policy is `SingleCallPolicy`, whose demand order, holds,
/// QoS, background rule and thread budget this one keeps.
///
/// - **In front** the Neural Engine lane takes the most urgent work whose engine has a route
///   there (Phonon), and the CPU lane the most urgent work left: another article, or the same
///   article's other paragraphs. An engine with no Neural Engine route (Kokoro) renders on the
///   CPU lane only.
/// - **In the background** only the CPU lane starts calls (`Lane.runsInBackground`).
/// - **Memory**: a model loads beside another only with its footprint plus `memoryHeadroomMB`
///   free. Once that is refused, the policy keeps to the CPU lane for the rest of the process
///   (`isOneLane`): its loads first let the Neural Engine's host go, and that lane takes nothing.
/// - **Threads**: while a Neural Engine host is loaded in front, the CPU lane's budget leaves
///   `neuralEngineCallCores` for its calls. A CPU call started before that (with the whole
///   budget) holds it: a new Neural Engine call waits until it ends.
/// - **A failed load** takes only that route out: the other lane renders the work. Listeners are
///   told only when no lane it may use now has a route left for them.
@MainActor
final class LanePolicy: RenderPolicy {
    var name: String { isOneLane ? "lanes (one: memory)" : "lanes" }
    let lanes: [Lane] = [.neuralEngine, .cpu]

    /// The CPU a Neural Engine call uses itself (Phonon: about 1.1 cores, p433).
    static let neuralEngineCallCores = 1
    /// What an uncapped CPU call counts against the budget (Phonon's Core ML CPU path: about 1.7
    /// cores, p427).
    static let uncappedCallCores = 2
    /// Free memory a second model must leave after its own footprint, MB.
    static let memoryHeadroomMB = 400

    /// A second model didn't fit: the CPU lane alone from then on.
    private(set) var isOneLane = false

    func plan(_ situation: RenderSituation) -> RenderPlan {
        let wasOneLane = isOneLane
        let usable: [Lane] = situation.phase != .background && !isOneLane ? lanes : [.cpu]
        var plan = RenderPlan(failed: situation.unservable(on: usable))
        guard situation.phase != .background || situation.audioPlaying else { return plan }
        var taken = Set<Int>()
        var loading = situation.lanes.values.contains { if case .load = $0.work { true } else { false } }

        /// Plan `lane`'s action: the most urgent candidate not taken that has a route there.
        func fill(_ lane: Lane) {
            guard situation.lanes[lane]?.isFree == true else { return }
            for index in situation.urgencyOrder where !taken.contains(index) {
                let candidate = situation.candidates[index]
                if candidate.demand > .playing, let hold = situation.hold {
                    plan.held = hold
                    return
                }
                guard let route = candidate.routes.first(where: { $0.lane == lane }) else { continue }
                let priority = SingleCallPolicy.priority(of: candidate)
                if situation.lanes[lane]?.resident == route {
                    guard mayStart(on: lane, in: situation) else { return }
                    plan.actions[lane] = .start(.init(candidate: index, route: route,
                                                      threads: SingleCallPolicy.threads(on: route, budget: cpuBudget(in: situation)),
                                                      priority: priority))
                    taken.insert(index)
                } else if !loading, let load = load(route, for: index, priority: priority, in: situation) {
                    plan.actions[lane] = .load(load)
                    loading = true
                }
                return
            }
        }

        if usable.contains(.neuralEngine) { fill(.neuralEngine) }
        fill(.cpu)
        // Turned to one lane during this plan: the lone load waits for the Neural Engine's call.
        if case .load(let load)? = plan.actions[.cpu], load.alone, plan.actions[.neuralEngine] != nil {
            plan.actions[.cpu] = nil
        }
        // Turned to one lane during this plan: tell the listeners the CPU lane alone can't serve,
        // now, since no later event need come to plan again.
        if isOneLane, !wasOneLane {
            let started = Set(plan.actions.values.compactMap { action -> Int? in
                if case .start(let start) = action { start.candidate } else { nil }
            })
            plan.failed = situation.unservable(on: [.cpu]).filter { !started.contains($0) }
        }
        if plan.actions.isEmpty, situation.candidates.isEmpty, !loading {
            if let route = usable.lazy.compactMap({ lane in situation.preload.first { $0.lane == lane } }).first,
               situation.lanes[route.lane]?.isFree == true, situation.lanes[route.lane]?.resident != route,
               let load = load(route, for: nil, priority: .bakeAhead, in: situation) {
                plan.actions[route.lane] = .load(load)
            }
        }
        return plan
    }

    /// `route`'s load: beside the other lanes' hosts when nothing else is loaded or it fits; when
    /// it doesn't fit, the policy turns to one lane and the CPU lane loads alone once the others
    /// are free (nil meanwhile, and always on the Neural Engine lane then).
    private func load(_ route: RenderRoute, for candidate: Int?, priority: RenderPriority,
                      in situation: RenderSituation) -> RenderPlan.Load? {
        let others = situation.otherResidents(than: route.lane)
        if !others.isEmpty, !isOneLane, let free = situation.availableMemoryMB,
           free < route.footprintMB + Self.memoryHeadroomMB {
            isOneLane = true
        }
        guard !others.isEmpty, isOneLane else {
            return RenderPlan.Load(route: route, priority: priority, candidate: candidate)
        }
        guard route.lane == .cpu, others.allSatisfy({ situation.lanes[$0]?.isFree == true }) else { return nil }
        return RenderPlan.Load(route: route, priority: priority, candidate: candidate, alone: true)
    }

    /// A Neural Engine call starts only while the CPU call in flight leaves it its cores.
    private func mayStart(on lane: Lane, in situation: RenderSituation) -> Bool {
        guard lane == .neuralEngine, case .call(let route, let threads)? = situation.lanes[.cpu]?.work else { return true }
        let used = threads ?? (route.threads == .uncapped ? Self.uncappedCallCores : 0)
        return used + Self.neuralEngineCallCores <= SingleCallPolicy.budget(in: situation)
    }

    /// The CPU lane's budget: `SingleCallPolicy`'s, less the Neural Engine call's own cores while
    /// a host is loaded there in front.
    private func cpuBudget(in situation: RenderSituation) -> Int {
        let budget = SingleCallPolicy.budget(in: situation)
        let sharing = situation.phase != .background && situation.lanes[.neuralEngine]?.resident != nil
        return sharing ? budget - Self.neuralEngineCallCores : budget
    }
}
