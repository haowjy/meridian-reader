import XCTest
@testable import MeridianReader

/// Scrubber seek: keeps play/pause state (paused seek must not start audio or reload).
@MainActor
final class PlaybackSeekTests: XCTestCase {
    private func state(_ phase: PlaybackPhase) -> PlaybackSessionState {
        var s = PlaybackSessionState()
        s.bind(articleID: UUID(), document: ParagraphDocument(parts: ["One.", "Two two.", "Three three three.", "Four."]))
        s.phase = phase
        return s
    }

    /// The scrubber released at the start of `paragraph`.
    private func seek(_ s: inout PlaybackSessionState, to paragraph: Int, engine: PlaybackEngineSnapshot) -> [PlaybackCommand] {
        s.handle(.seekOffset(utf16: s.document.startUTF16Offset(forParagraph: paragraph)), engine: engine)
    }

    func testSeekWhilePlayingKeepsPlaying() {
        var s = state(.playing)
        let cmds = seek(&s, to: 2, engine: .init(isAudible: true, isPaused: false))
        XCTAssertEqual(cmds, [.engineSeek])
        XCTAssertEqual(s.phase, .playing)
        XCTAssertEqual(s.playhead, 2)
    }

    func testSeekWhilePausedStaysPaused() {
        var s = state(.paused)
        let cmds = seek(&s, to: 3, engine: .init(isAudible: false, isPaused: true))
        XCTAssertEqual(cmds, [.engineSeek], "engine re-queues at the new spot (startPaused)")
        XCTAssertEqual(s.phase, .paused)
        XCTAssertEqual(s.playhead, 3)
        XCTAssertEqual(s.utf16Offset, s.document.startUTF16Offset(forParagraph: 3))
        // Play afterwards resumes from the seeked spot.
        XCTAssertEqual(s.handle(.toggle, engine: .init(isAudible: false, isPaused: true)), [.engineResume])
        XCTAssertEqual(s.playhead, 3)
    }

    func testSeekWhenPreparedOnlyMovesPlayhead() {
        var s = state(.prepared)
        XCTAssertEqual(seek(&s, to: 1, engine: .init(isAudible: false, isPaused: false)), [])
        XCTAssertEqual(s.phase, .prepared)
        XCTAssertEqual(s.handle(.toggle, engine: .init(isAudible: false, isPaused: false)), [.enginePlay])
        XCTAssertEqual(s.playhead, 1, "Play speaks from the seeked paragraph")
    }

    func testSeekAfterFinishedClampsAndRearms() {
        var s = state(.finished)
        XCTAssertEqual(s.handle(.seekOffset(utf16: 10_000), engine: .init(isAudible: false, isPaused: false)), [])
        XCTAssertEqual(s.playhead, 3)
        XCTAssertEqual(s.phase, .prepared)
    }
}
