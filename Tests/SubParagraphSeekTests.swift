import XCTest
@testable import Reader

/// Nav I: scrubbing snaps to sentence starts and playback resumes at that sentence (not the
/// paragraph start); fine-scrub speeds; chunk ↔ paragraph offset mapping for the local engine.
@MainActor
final class SubParagraphSeekTests: XCTestCase {
    private let p0 = "First sentence here. Second one follows! Third? Yes, the third."
    private let p1 = "Only one sentence in this paragraph"

    func testSentenceStarts() {
        let starts = SentenceStarts.offsets(in: p0)
        XCTAssertEqual(starts.first, 0)
        XCTAssertEqual(starts.count, 4)
        let ns = p0 as NSString
        XCTAssertEqual(ns.substring(from: starts[1]).prefix(6), "Second")
        XCTAssertEqual(ns.substring(from: starts[2]).prefix(5), "Third")
        XCTAssertEqual(SentenceStarts.offsets(in: p1), [0])
        XCTAssertEqual(SentenceStarts.offsets(in: ""), [0])
    }

    func testScrubMapSnapsToTheSentenceUnderTheFinger() {
        let map = ReaderScrubMap(paragraphs: [p0, p1])
        let second = SentenceStarts.offsets(in: p0)[1]
        // Anywhere inside sentence 2 → its start.
        let mid = map.fraction(paragraph: 0, offset: second + 5)
        let t = map.target(at: mid)
        XCTAssertEqual(t, .init(paragraph: 0, sentence: 1, offset: second))
        XCTAssertEqual(map.fraction(of: t), map.fraction(paragraph: 0, offset: second), accuracy: 1e-9)
        XCTAssertEqual(map.snippet(for: t), "Second one follows!")
        // A small move back that stays in the sentence commits the same sentence start.
        XCTAssertEqual(map.target(at: mid - 0.01).offset, second)
        // Start of the article and the second paragraph.
        XCTAssertEqual(map.target(at: 0), .init(paragraph: 0, sentence: 0, offset: 0))
        XCTAssertEqual(map.target(at: 0.99).paragraph, 1)
        XCTAssertEqual(map.target(at: 0.99).offset, 0)
        // Ticks: 3 sentence starts in p0 + the p1 start.
        XCTAssertEqual(map.ticks.count, 4)
        XCTAssertNotEqual(map.tickIndex(at: mid), map.tickIndex(at: map.fraction(paragraph: 0, offset: 2)))
        XCTAssertEqual(map.sentenceCount(paragraph: 0), 4)
        XCTAssertEqual(map.target(paragraph: 0, offset: 10_000).sentence, 3)
    }

    func testSnippetIsShortened() {
        let long = String(repeating: "word ", count: 60) + "end."
        let map = ReaderScrubMap(paragraphs: [long])
        let snippet = map.snippet(for: map.target(at: 0), maxLength: 30)
        XCTAssertTrue(snippet.hasSuffix("…"))
        XCTAssertLessThanOrEqual(snippet.count, 31)
    }

    func testScrubSpeedTiers() {
        XCTAssertEqual(ScrubSpeed(verticalDistance: 0), .normal)
        XCTAssertEqual(ScrubSpeed(verticalDistance: -49), .normal)
        XCTAssertEqual(ScrubSpeed(verticalDistance: -60), .half)
        XCTAssertEqual(ScrubSpeed(verticalDistance: -120), .quarter)
        XCTAssertEqual(ScrubSpeed(verticalDistance: -200), .fine)
        XCTAssertEqual(ScrubSpeed.fine.multiplier, 0.1)
        XCTAssertNil(ScrubSpeed.normal.label)
        XCTAssertEqual(ScrubSpeed.fine.label, "Fine scrubbing")
    }

    func testChunkOffsetsSurviveNormalization() {
        // TextChunker rewrites whitespace / dashes; letters and digits are untouched.
        let paragraph = "Alpha  beta — gamma delta.\u{00A0}Epsilon zeta eta. Theta iota kappa."
        let chunks = ["Alpha beta, gamma delta.", "Epsilon zeta eta.", "Theta iota kappa."]
        let starts = ChunkOffsets.starts(paragraph: paragraph, chunks: chunks)
        let ns = paragraph as NSString
        XCTAssertEqual(starts.count, 3)
        XCTAssertEqual(starts[0], 0)
        XCTAssertTrue(ns.substring(from: starts[1]).hasPrefix("Epsilon"))
        XCTAssertTrue(ns.substring(from: starts[2]).hasPrefix("Theta"))
        // Sentence start in chunk 1 → (1, 0); a point halfway through chunk 2.
        XCTAssertEqual(ChunkOffsets.locate(offset: starts[1], starts: starts, length: ns.length).chunk, 1)
        XCTAssertEqual(ChunkOffsets.locate(offset: starts[1], starts: starts, length: ns.length).fraction, 0)
        let half = starts[2] + (ns.length - starts[2]) / 2
        let loc = ChunkOffsets.locate(offset: half, starts: starts, length: ns.length)
        XCTAssertEqual(loc.chunk, 2)
        XCTAssertEqual(loc.fraction, 0.5, accuracy: 0.06)
        XCTAssertEqual(ChunkOffsets.offset(chunk: 2, fraction: loc.fraction, starts: starts, length: ns.length), half, accuracy: 1)
        XCTAssertEqual(ChunkOffsets.starts(paragraph: paragraph, chunks: [paragraph]), [0])
    }

    func testTimeInStitchedParagraphMapsToChunk() {
        let loc = ChunkOffsets.locate(time: 3.5, fileDuration: 6, durations: [2, 3, 1], chunkCount: 3)
        XCTAssertEqual(loc.chunk, 1)
        XCTAssertEqual(loc.fraction, 0.5, accuracy: 1e-9)
        let whole = ChunkOffsets.locate(time: 3, fileDuration: 6, durations: nil, chunkCount: 1)
        XCTAssertEqual(whole.chunk, -1)
        XCTAssertEqual(whole.fraction, 0.5, accuracy: 1e-9)
    }

    // MARK: - Session

    private func state(_ phase: PlaybackPhase) -> PlaybackSessionState {
        var s = PlaybackSessionState()
        s.bind(articleID: UUID(), document: ParagraphDocument(parts: ["One. Uno.", "Two two. Dos dos.", "Three."]), startingAt: 0)
        s.phase = phase
        return s
    }

    func testSeekToSentenceWhilePlayingKeepsTheOffset() {
        var s = state(.playing)
        let target = s.document.startUTF16Offset(forParagraph: 1) + 9 // "Dos dos."
        let cmds = s.handle(.seekOffset(utf16: target), engine: .init(isAudible: true, isPaused: false))
        XCTAssertEqual(cmds, [.engineSeek(paragraph: 1)])
        XCTAssertEqual(s.playhead, 1)
        XCTAssertEqual(s.utf16Offset, target, "mid-paragraph, not the paragraph start")
        XCTAssertEqual(s.phase, .playing)
    }

    func testPausedSentenceSeekStaysPaused() {
        var s = state(.paused)
        let target = s.document.startUTF16Offset(forParagraph: 0) + 5
        XCTAssertEqual(s.handle(.seekOffset(utf16: target), engine: .init(isAudible: false, isPaused: true)),
                       [.engineSeek(paragraph: 0)])
        XCTAssertEqual(s.phase, .paused)
        XCTAssertEqual(s.utf16Offset, target)
    }

    func testPreparedSentenceSeekIsWherePlayStarts() {
        var s = state(.prepared)
        let target = s.document.startUTF16Offset(forParagraph: 1) + 9
        XCTAssertEqual(s.handle(.seekOffset(utf16: target), engine: .init(isAudible: false, isPaused: false)), [])
        XCTAssertEqual(s.handle(.play(from: 1), engine: .init(isAudible: false, isPaused: false)), [.enginePlay(from: 1)])
        XCTAssertEqual(s.utf16Offset, target, "Play from the playhead keeps the scrubbed sentence")
        // Playing another paragraph starts at its beginning.
        var t = state(.prepared)
        _ = t.handle(.seekOffset(utf16: target), engine: .init(isAudible: false, isPaused: false))
        _ = t.handle(.play(from: 2), engine: .init(isAudible: false, isPaused: false))
        XCTAssertEqual(t.utf16Offset, t.document.startUTF16Offset(forParagraph: 2))
    }
}
