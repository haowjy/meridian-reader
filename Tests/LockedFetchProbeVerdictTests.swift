import XCTest
@testable import MeridianReader

/// The device probe's verdicts. The owner runs it once on a locked phone, and the Simulator can't
/// lock (protected data is always available there), so its pass and fail are pinned here.
final class LockedFetchProbeVerdictTests: XCTestCase {
    private typealias Probe = LockedFetchProbe

    func testTheFetchCountsOnlyWhenItRanLockedWithChapterOnePlaying() {
        func ruling(_ answer: Probe.Ruling, woke: Bool = false, lockedAtEnd: Bool = true,
                    playingAtEnd: Bool = true) -> Probe.Ruling {
            Probe.ruling(on: Probe.FetchEvidence(answer: answer, lockedAtStart: true, lockedAtEnd: lockedAtEnd,
                                                 playingAtStart: true, playingAtEnd: playingAtEnd, woke: woke))
        }
        XCTAssertEqual(ruling(.pass("loaded")).verdict, .pass)
        XCTAssertEqual(ruling(.fail("WebKit didn't answer")), .fail("WebKit didn't answer"))
        XCTAssertEqual(ruling(.pass("loaded"), woke: true).verdict, .inconclusive, "came to the front during the fetch")
        XCTAssertEqual(ruling(.fail("WebKit didn't answer"), lockedAtEnd: false).verdict, .inconclusive, "unlocked by its end")
        XCTAssertEqual(ruling(.pass("loaded"), playingAtEnd: false).verdict, .inconclusive, "chapter 1 ended early")
    }

    func testTheWaitFailsWhenTheHoldRanLateEvenIfTheUnlockWokeTheApp() {
        func ruling(held: TimeInterval = 5.1, resumed: Bool = true, deactivated: Bool = false,
                    lockedAtStart: Bool = true, lockedAtResume: Bool = true, woke: Bool = false) -> Probe.Ruling {
            Probe.ruling(on: Probe.WaitEvidence(held: held, resumed: resumed,
                                                outcome: resumed ? "chapter 2 audible" : "playback ended before chapter 2",
                                                deactivated: deactivated, lockedAtStart: lockedAtStart, lockedAtEnd: true,
                                                lockedAtResume: lockedAtResume, woke: woke))
        }
        XCTAssertEqual(ruling().verdict, .pass)
        XCTAssertEqual(ruling(held: 40, woke: true).verdict, .fail, "suspended until the unlock")
        XCTAssertEqual(ruling(held: 40, lockedAtStart: false).verdict, .inconclusive, "not locked when it began")
        XCTAssertEqual(ruling(woke: true).verdict, .inconclusive, "on time, but unlocked during the wait")
        XCTAssertEqual(ruling(lockedAtResume: false).verdict, .inconclusive)
        XCTAssertEqual(ruling(deactivated: true).verdict, .fail)
        XCTAssertEqual(ruling(resumed: false), .fail("playback ended before chapter 2"))
    }
}
