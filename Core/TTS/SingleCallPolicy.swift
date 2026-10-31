import Foundation

/// One model call at a time on the CPU, in front and in the background, in demand order (a
/// waiting listener's chunk, the article playing from its playhead, the staged chapter's opening,
/// then the rest), first come first served within a demand: the candidates' queue order. The
/// app's policy.
///
/// - Holds (thermal, Low Power Mode) stop work nobody listens to: `.staged` and `.queued`.
/// - In the background a call starts only while audio plays: iOS suspends the app soon after it
///   stops, and a call cut there would leave a crash marker behind.
/// - Threads, for a route that takes a count: every core but `frontReserveCores` in front (and
///   inactive), `backgroundThreads` in the background, never over the route's cap.
/// - QoS: `.userInitiated` for a listener's chunk, `.utility` for everything else.
/// - The route of the work it picks is loaded first, when it isn't the resident one; with no
///   work, the route of the engine asked for as a preload.
@MainActor
final class SingleCallPolicy: RenderPolicy {
    let name = "single-call"

    static let frontReserveCores = 1
    static let backgroundThreads = 1

    func plan(_ situation: RenderSituation) -> RenderPlan {
        guard situation.lanes[.cpu]?.isFree == true else { return RenderPlan() }
        guard situation.phase != .background || situation.audioPlaying else { return RenderPlan() }
        for index in situation.urgencyOrder {
            let candidate = situation.candidates[index]
            if candidate.demand > .playing, let hold = situation.hold { return RenderPlan(held: hold) }
            guard let route = candidate.routes.first(where: { $0.lane == .cpu }) else { continue }
            let priority = Self.priority(of: candidate)
            guard situation.lanes[.cpu]?.resident == route else {
                return RenderPlan(actions: [.cpu: .load(.init(route: route, priority: priority, candidate: index))])
            }
            return RenderPlan(actions: [.cpu: .start(.init(candidate: index, route: route,
                                                           threads: Self.threads(on: route, budget: Self.budget(in: situation)),
                                                           priority: priority))])
        }
        if let route = situation.preload.first(where: { $0.lane == .cpu }), situation.lanes[.cpu]?.resident != route {
            return RenderPlan(actions: [.cpu: .load(.init(route: route, priority: .bakeAhead, candidate: nil))])
        }
        return RenderPlan()
    }

    /// The CPU threads calls may use: every core but `frontReserveCores` in front (and inactive),
    /// `backgroundThreads` in the background.
    static func budget(in situation: RenderSituation) -> Int {
        situation.phase == .background ? backgroundThreads : situation.cores - frontReserveCores
    }

    /// A call's threads on `route`: the budget, never over the route's cap, at least one; nil for
    /// a route that takes no count.
    static func threads(on route: RenderRoute, budget: Int) -> Int? {
        guard case .honored(let cap) = route.threads else { return nil }
        return max(1, min(cap, budget))
    }

    static func priority(of candidate: RenderCandidate) -> RenderPriority {
        candidate.demand == .listener ? .listener : .bakeAhead
    }
}
