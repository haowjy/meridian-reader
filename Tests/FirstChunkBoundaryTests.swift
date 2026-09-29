import XCTest
@testable import Reader

/// The first (fast-start) chunk of a paragraph must end at a sentence end or a clause boundary
/// (`; : —`, comma, before and/but/which…), never between bare words, and its join gets the
/// matching pause. Regression: two pieces of The Forgotten p6 (after the 1,200-char split) had
/// first joins of 0.08 s (“…to buy toilet paper | and canned food”, “…departments such as |
/// healthcare”).
final class FirstChunkBoundaryTests: XCTestCase {
    private let limits = TextChunker.Limits.kokoroCPU
    private var cap: Int { limits.firstTarget + TextChunker.Limits.firstStretch }
    private func units(_ s: String) -> Int { TextChunker.estimatedUnits(s) }

    /// All listen paragraphs of the real chapter, after the long-paragraph split.
    private var chapterParagraphs: [String] {
        ListenHTMLBlocks.leafTexts(fromHTML: ParagraphSplitTests.chapterHTML).flatMap { ParagraphSplitter.pieces($0) }
    }

    private func joins(_ chunks: [String]) -> [ChunkEdgeTrim.Boundary] {
        chunks.indices.dropLast().map { i in
            ChunkEdgeTrim.boundary(after: chunks[i], nextWord: chunks[i + 1].split(separator: " ").first.map(String.init),
                                   isLastInParagraph: false)
        }
    }

    /// Join silence = the chunk's trailing pause + the next chunk's lead-in.
    private func joinSeconds(_ b: ChunkEdgeTrim.Boundary) -> Double {
        Double(ChunkEdgeTrim.trailMs(b) + ChunkEdgeTrim.leadMs) / 1000
    }

    func testForgottenPieceTwoFirstChunkEndsBeforeConjunctionWithClausePause() {
        let piece = ParagraphSplitter.pieces(HierarchicalChunkerTests.p6)[1]
        XCTAssertTrue(piece.hasPrefix("There were hundreds of people"))
        let chunks = TextChunker.chunks(for: piece, limits: limits)
        XCTAssertEqual(chunks[0], "There were hundreds of people rushing into stores to buy toilet paper")
        XCTAssertTrue(chunks[1].hasPrefix("and canned food"))
        XCTAssertEqual(joins(chunks)[0], .clause)
        XCTAssertGreaterThanOrEqual(joinSeconds(joins(chunks)[0]), 0.15)
    }

    func testForgottenPieceThreeFirstChunkEndsAtCommaNotMidPhrase() {
        let piece = ParagraphSplitter.pieces(HierarchicalChunkerTests.p6)[2]
        XCTAssertTrue(piece.hasPrefix("The first group, Scienta"))
        let chunks = TextChunker.chunks(for: piece, limits: limits)
        // Old: "…consists of jobs in departments such as" | "healthcare, …" (a bare word cut).
        XCTAssertEqual(chunks[0], "The first group, Scienta, or knowledge,")
        XCTAssertEqual(joins(chunks)[0], .clause)
        XCTAssertEqual(chunks.joined(separator: " "), TextChunker.normalize(piece))
    }

    func testNoWordJoinsAnywhereInTheChapter() {
        for (i, para) in chapterParagraphs.enumerated() {
            let chunks = TextChunker.chunks(for: para, limits: limits)
            guard chunks.count > 1 else { continue }
            XCTAssertLessThanOrEqual(units(chunks[0]), cap, "paragraph \(i) first chunk over the cap")
            XCTAssertEqual(chunks.joined(separator: " "), TextChunker.normalize(para))
            for (k, b) in joins(chunks).enumerated() {
                XCTAssertNotEqual(b, .word, "paragraph \(i) join \(k): …\(chunks[k].suffix(40)) | \(chunks[k + 1].prefix(20))")
                XCTAssertGreaterThanOrEqual(joinSeconds(b), 0.15)
            }
        }
    }

    func testHeadStartRampStillHoldsForThePieces() {
        for para in chapterParagraphs {
            let u = TextChunker.chunks(for: para, limits: limits).map(units)
            guard u.count > 1 else { continue }
            for k in 1..<u.count {
                let rendered = u[1...k].reduce(0, +)
                let played = u[0..<k].reduce(0, +)
                XCTAssertLessThanOrEqual(Double(rendered) / 2.4, Double(played) + 1, "chunk \(k) would stall: \(u)")
            }
        }
    }

    func testStretchesToTheNearestClausePastTheBudgetWithinTheCap() {
        // No clause boundary in the first 80 units; a comma at ≈101.
        let s = "The enormous grey building at the very end of the quiet street near the old market square stood empty for years, nobody wanted it. Then it sold."
        let chunks = TextChunker.chunks(for: s, limits: limits)
        XCTAssertEqual(chunks[0], "The enormous grey building at the very end of the quiet street near the old market square stood empty for years,")
        XCTAssertGreaterThan(units(chunks[0]), limits.firstTarget)
        XCTAssertLessThanOrEqual(units(chunks[0]), cap)
    }

    func testWholeFirstSentenceWithinTheCapBeatsAWordCut() {
        let s = "The enormous grey building at the very end of the quiet street near the old market stood empty. It sold later that year to a family from out of town who wanted a shop."
        let first = TextChunker.chunks(for: s, limits: limits)[0]
        XCTAssertEqual(first, "The enormous grey building at the very end of the quiet street near the old market stood empty.")
    }

    func testTinyClauseHeadIsNotUsedForTheFirstChunk() {
        // "Well," is too short to carry the fast start; the next clause boundary is used.
        let s = "Well, the enormous grey building at the very end of the quiet street near the old market square, stood empty for years and years until the town finally sold it off."
        let first = TextChunker.chunks(for: s, limits: limits)[0]
        XCTAssertNotEqual(first, "Well,")
        XCTAssertTrue(first.hasSuffix(",") || first.hasSuffix("."), first)
        XCTAssertLessThanOrEqual(units(first), cap)
    }

    func testClauseFreeRunFallsBackToASpaceCutInsideTheBudget() {
        // Last resort only: no sentence end, clause mark or conjunction within the cap.
        let s = (1...40).map { _ in "word" }.joined(separator: " ") + "."
        let first = TextChunker.chunks(for: s, limits: limits)[0]
        XCTAssertLessThanOrEqual(units(first), limits.firstTarget)
    }

    func testConjunctionJoinGetsTheClausePause() {
        XCTAssertEqual(ChunkEdgeTrim.boundary(after: "to buy toilet paper", nextWord: "and", isLastInParagraph: false), .clause)
        XCTAssertEqual(ChunkEdgeTrim.boundary(after: "the house", nextWord: "Which", isLastInParagraph: false), .clause)
        XCTAssertEqual(ChunkEdgeTrim.boundary(after: "departments such as", nextWord: "healthcare,", isLastInParagraph: false), .word)
        XCTAssertEqual(ChunkEdgeTrim.boundary(after: "the end.", nextWord: "and", isLastInParagraph: false), .sentence)
        XCTAssertEqual(ChunkEdgeTrim.boundary(after: "x", nextWord: "and", isLastInParagraph: true), .paragraphEnd)
    }

    func testFirstStretchMatchesPhoneRenderTiming() {
        // Phone (iPhone 17 Pro, ONNX): ≈0.35 s + 23 ms/char median, 28 ms/char worst.
        let worst = 0.35 + 0.028 * Double(cap)
        XCTAssertLessThanOrEqual(worst, 3.8, "first audio stays under ≈4 s worst case at the cap")
        XCTAssertEqual(cap, 120)
    }
}
