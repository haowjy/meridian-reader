import XCTest
@testable import MeridianReader

/// Background admission (C94): a download renders only on its turn, on a route that renders in
/// the background; never on Core ML, never instead of a burst of the playing article.
final class RenderAdmissionTests: XCTestCase {
    private func decide(cpu: Bool = true, playing: Bool = false, burst: Bool = false, turn: Bool = false) -> RenderAdmission {
        RenderAdmission.decide(engineReady: true, phase: .background, rendersInBackground: cpu,
                               isLiveRequest: false, isPlayingArticle: playing, inBackgroundBurst: burst,
                               isDownloadTurn: turn)
    }

    func testADownloadRendersInTheBackgroundOnlyOnItsTurn() {
        XCTAssertEqual(decide(turn: true), .render)
        XCTAssertEqual(decide(turn: false), .park)
    }

    func testCoreMLNeverRendersADownloadInTheBackground() {
        XCTAssertEqual(decide(cpu: false, turn: true), .park)
    }

    func testThePlayingArticleStillRendersInABurst() {
        XCTAssertEqual(decide(playing: true, burst: true), .render)
        XCTAssertEqual(decide(playing: true, burst: false), .park)
    }
}
