import XCTest
@testable import MeridianReader

/// The whole background / route admission matrix, one row per case.
final class RenderAdmissionTests: XCTestCase {
    private struct Row {
        var phase: AppRunState.Phase
        var cpuRoute: Bool
        var live: Bool
        var playing: Bool
        var expected: RenderAdmission
    }

    func testDecisionTable() {
        let rows: [Row] = [
            // Active: everything renders.
            Row(phase: .active, cpuRoute: false, live: false, playing: false, expected: .render),
            Row(phase: .active, cpuRoute: false, live: true, playing: false, expected: .render),
            Row(phase: .active, cpuRoute: true, live: false, playing: false, expected: .render),
            // Inactive: Core ML serves only a waiting listener; the CPU route runs as if active.
            Row(phase: .inactive, cpuRoute: false, live: true, playing: false, expected: .render),
            Row(phase: .inactive, cpuRoute: false, live: false, playing: true, expected: .park),
            Row(phase: .inactive, cpuRoute: true, live: false, playing: false, expected: .render),
            // Background, Core ML: no model call; a listener's audio goes to Apple.
            Row(phase: .background, cpuRoute: false, live: true, playing: true, expected: .deferToApple),
            Row(phase: .background, cpuRoute: false, live: false, playing: true, expected: .park),
            // Background, CPU route: the listener and the playing article; other articles wait.
            Row(phase: .background, cpuRoute: true, live: true, playing: false, expected: .render),
            Row(phase: .background, cpuRoute: true, live: false, playing: true, expected: .render),
            Row(phase: .background, cpuRoute: true, live: false, playing: false, expected: .park),
        ]
        for row in rows {
            XCTAssertEqual(
                RenderAdmission.decide(phase: row.phase, rendersInBackground: row.cpuRoute,
                                       isLiveRequest: row.live, isPlayingArticle: row.playing),
                row.expected, "\(row)")
        }
    }

    func testHardRuleOnlyBlocksCoreMLInTheBackground() {
        XCTAssertTrue(RenderAdmission.modelCallsAllowed(phase: .active, rendersInBackground: false))
        XCTAssertTrue(RenderAdmission.modelCallsAllowed(phase: .inactive, rendersInBackground: false))
        XCTAssertFalse(RenderAdmission.modelCallsAllowed(phase: .background, rendersInBackground: false))
        XCTAssertTrue(RenderAdmission.modelCallsAllowed(phase: .background, rendersInBackground: true))
    }
}
