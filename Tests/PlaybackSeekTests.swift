import XCTest
@testable import Reader

/// Scrubber seek: keeps play/pause state (paused seek must not start audio or reload).
@MainActor
final class PlaybackSeekTests: XCTestCase {
    private func state(_ phase: PlaybackPhase) -> PlaybackSessionState {
        var s = PlaybackSessionState()
        s.bind(articleID: UUID(), document: ParagraphDocument(parts: ["One.", "Two two.", "Three three three.", "Four."]), startingAt: 0)
        s.phase = phase
        return s
    }

    func testSeekWhilePlayingKeepsPlaying() {
        var s = state(.playing)
        let cmds = s.handle(.seek(paragraph: 2), engine: .init(isAudible: true, isPaused: false))
        XCTAssertEqual(cmds, [.engineSeek(paragraph: 2)])
        XCTAssertEqual(s.phase, .playing)
        XCTAssertEqual(s.playhead, 2)
    }

    func testSeekWhilePausedStaysPaused() {
        var s = state(.paused)
        let cmds = s.handle(.seek(paragraph: 3), engine: .init(isAudible: false, isPaused: true))
        XCTAssertEqual(cmds, [.engineSeek(paragraph: 3)], "engine re-queues at the new spot (startPaused)")
        XCTAssertEqual(s.phase, .paused)
        XCTAssertEqual(s.playhead, 3)
        XCTAssertEqual(s.utf16Offset, s.document.startUTF16Offset(forParagraph: 3))
        // Play afterwards resumes from the seeked spot.
        XCTAssertEqual(s.handle(.toggle, engine: .init(isAudible: false, isPaused: true)), [.engineResume])
        XCTAssertEqual(s.playhead, 3)
    }

    func testSeekWhenPreparedOnlyMovesPlayhead() {
        var s = state(.prepared)
        XCTAssertEqual(s.handle(.seek(paragraph: 1), engine: .init(isAudible: false, isPaused: false)), [])
        XCTAssertEqual(s.phase, .prepared)
        XCTAssertEqual(s.handle(.toggle, engine: .init(isAudible: false, isPaused: false)), [.enginePlay(from: 1)])
    }

    func testSeekAfterFinishedClampsAndRearms() {
        var s = state(.finished)
        XCTAssertEqual(s.handle(.seek(paragraph: 99), engine: .init(isAudible: false, isPaused: false)), [])
        XCTAssertEqual(s.playhead, 3)
        XCTAssertEqual(s.phase, .prepared)
    }
}
