import Foundation

/// One model call at a time on the CPU, in front and in the background, in demand order (a
/// waiting listener's chunk, the article playing from its playhead, the staged chapter's opening,
/// then the rest), first come first served within a demand: the candidates' queue order.
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
        let inFlight = situation.lanes.values.reduce(0) { $0 + $1.callsInFlight }
        guard inFlight < situation.maxCallsInFlight else { return .idle }
        guard situation.phase != .background || situation.audioPlaying else { return .idle }
        let order = situation.candidates.indices.sorted {
            (situation.candidates[$0].demand.rawValue, $0) < (situation.candidates[$1].demand.rawValue, $1)
        }
        for index in order {
            let candidate = situation.candidates[index]
            if candidate.demand > .playing, let hold = situation.hold { return .held(hold) }
            guard let route = candidate.routes.first(where: { $0.lane == .cpu }) else { continue }
            let priority: RenderPriority = candidate.demand == .listener ? .listener : .bakeAhead
            guard situation.lanes[route.lane]?.resident == route else {
                return .load(.init(route: route, priority: priority, candidate: index))
            }
            return .start(.init(candidate: index, route: route, threads: Self.threads(on: route, in: situation),
                                priority: priority))
        }
        if let route = situation.preload.first(where: { $0.lane == .cpu }), situation.lanes[.cpu]?.resident != route {
            return .load(.init(route: route, priority: .bakeAhead, candidate: nil))
        }
        return .idle
    }

    static func threads(on route: RenderRoute, in situation: RenderSituation) -> Int? {
        guard case .honored(let cap) = route.threads else { return nil }
        let budget = situation.phase == .background ? backgroundThreads : situation.cores - frontReserveCores
        return max(1, min(cap, budget))
    }
}
