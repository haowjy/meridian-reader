import XCTest
@testable import Reader

/// Chunker regression tests. Origin: the long-paragraph skip (paragraphs of 1–2.5k chars overflowed
/// a single engine call and were skipped silently; see docs/LISTEN_PLAYBACK.md § Chunking).
/// Giant-paragraph cases (10k chars, 5k-char run-on, 600-char URL) check every invariant.
@MainActor
final class TextChunkerTests: XCTestCase {
    /// Synthetic stand-in shaped like the paragraphs that were skipped (≈2.5k chars): curly
    /// quotes, aside dashes, numbers, abbreviations, initials, slashes, double spaces.
    private let longA: String = {
        let base = """
        Okay, I’m gonna give you a quick rundown of how things got this way, and you’ll have to \
        trust me on the dates. After the Russian/Ukrainian war ended about 2.5 hundred years ago, \
        -nobody can give me an exact year, answers vary, but the usual guess is 2031- people grew \
        restless.  Everyone had expected a third world war, especially once the U.S.A. and Britain \
        joined in. Dr. Hollis and Mr. I. Ericcson-Sprucefeld wrote that the three-day blackout \
        changed everything, e.g. the grid, the ports, the farms, etc. Medical staff –nurse, doctor, \
        orderly, etc- were drafted by the thousands. “Nobody listened,” my father told me, “not \
        until the bombs were already in the air.” Then the treaty of 2044 split the continent into \
        eleven zones, each with its own council, currency, and curfew, and each one swore it was \
        the last honest place left on Earth.
        """
        return Array(repeating: base, count: 3).joined(separator: " ")
    }()

    func testLongParagraphChunksStayUnderHardMax() {
        XCTAssertGreaterThan(longA.count, 2000)
        let chunks = TextChunker.chunks(for: longA, limits: .tenSecondCall)
        XCTAssertGreaterThan(chunks.count, 10)
        for chunk in chunks {
            XCTAssertLessThanOrEqual(
                TextChunker.estimatedUnits(chunk), TextChunker.Limits.tenSecondCall.hardMax,
                "chunk over hardMax: \(chunk)"
            )
            XCTAssertFalse(chunk.isEmpty)
        }
        // First chunk is small so first audio lands sooner.
        // (A whole first sentence may use `firstSlack` instead of being cut mid-sentence.)
        XCTAssertLessThanOrEqual(TextChunker.estimatedUnits(chunks[0]),
                                 TextChunker.Limits.tenSecondCall.firstTarget + TextChunker.Limits.firstSlack)
        XCTAssertTrue(chunks[0].hasSuffix(".") || TextChunker.estimatedUnits(chunks[0]) <= TextChunker.Limits.tenSecondCall.firstTarget)
    }

    func testChunksPreserveAllText() {
        for text in [longA, "Short one.", "A b c.  D e f!  G h i?"] {
            let chunks = TextChunker.chunks(for: text)
            XCTAssertEqual(chunks.joined(separator: " "), TextChunker.normalize(text))
        }
    }

    func testAbbreviationsAndInitialsDoNotSplit() {
        let sentences = TextChunker.splitSentences(
            "Dr. Hollis met Mr. I. Ericcson-Sprucefeld in the U.S.A. last week. Then he left."
        )
        XCTAssertEqual(sentences.count, 2, "\(sentences)")
        XCTAssertTrue(sentences[0].hasPrefix("Dr. Hollis met Mr. I. Ericcson-Sprucefeld"))
        XCTAssertTrue(sentences[0].hasSuffix("last week."))
    }

    func testDecimalDoesNotSplit() {
        let sentences = TextChunker.splitSentences("It ended 2.5 hundred years ago. Really.")
        XCTAssertEqual(sentences, ["It ended 2.5 hundred years ago.", "Really."])
    }

    func testNormalizeKeepsIntraWordHyphensAndConvertsAsides() {
        let n = TextChunker.normalize("A three-day war,  -nobody knows- ended. Staff –nurse, doctor, etc- came.")
        XCTAssertTrue(n.contains("three-day"))
        XCTAssertFalse(n.contains("  "))
        XCTAssertFalse(n.contains("-nobody"))
        XCTAssertFalse(n.contains("–nurse"))
        XCTAssertTrue(n.contains("nobody knows"))
        XCTAssertFalse(n.contains(",,"))
    }

    /// Regression (found by the 600-char URL case): a dash next to non-quote punctuation inside a
    /// token (`z-_`, `/-/`) was turned into ", ", inserting a space into URLs.
    func testNormalizeLeavesDashesInsideTokensAlone() {
        let url = "https://example.com/a-_b/-/c--d?x=-1"
        XCTAssertEqual(TextChunker.normalize("See \(url) now."), "See \(url) now.")
        XCTAssertEqual(TextChunker.normalize("“Nobody listened”-she said."), "“Nobody listened”, she said.")
    }

    func testShortParagraphIsSingleChunk() {
        XCTAssertEqual(TextChunker.chunks(for: "  Hello there.  "), ["Hello there."])
        XCTAssertEqual(TextChunker.chunks(for: "   "), [])
    }

    func testNoSentenceBoundaryStillSplits() {
        let runOn = Array(repeating: "and then the wind kept rising", count: 20).joined(separator: " ")
        let chunks = TextChunker.chunks(for: runOn)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { TextChunker.estimatedUnits($0) <= TextChunker.hardMax })
        XCTAssertEqual(chunks.joined(separator: " "), TextChunker.normalize(runOn))
    }

    func testResplitHalvesOverflowingChunk() {
        let chunk = "The ports closed, the farms failed, the grid went dark, and nobody could say when it would end."
        let parts = TextChunker.resplit(chunk)
        XCTAssertGreaterThan(parts.count, 1)
        XCTAssertEqual(parts.joined(separator: " "), chunk)
        XCTAssertTrue(parts.allSatisfy { $0.count < chunk.count })
        // Tiny text cannot be re-split further → caller falls back to Apple TTS.
        XCTAssertEqual(TextChunker.resplit("Too short."), ["Too short."])
    }

    func testKokoroLimitsAllowLongerChunksButStayUnderPhonemeCap() {
        // The descriptor now uses .kokoroCPU (ONNX route, short first chunk); .kokoro is the Core ML sizing.
        XCTAssertEqual(FluidAudioProvider.kokoroDescriptor.limits, .kokoroCPU)
        let limits = TextChunker.Limits.kokoro
        let chunks = TextChunker.chunks(for: longA, limits: limits)
        XCTAssertLessThan(chunks.count, TextChunker.chunks(for: longA, limits: .tenSecondCall).count)
        for chunk in chunks {
            // 300 units keeps IPA well under KokoroAne's 510-phoneme input cap.
            XCTAssertLessThanOrEqual(TextChunker.estimatedUnits(chunk), limits.hardMax)
        }
        XCTAssertLessThanOrEqual(TextChunker.estimatedUnits(chunks[0]), limits.firstTarget + TextChunker.Limits.firstSlack)
        XCTAssertTrue(chunks[0].hasSuffix(".") || TextChunker.estimatedUnits(chunks[0]) <= limits.firstTarget)
        XCTAssertEqual(chunks.joined(separator: " "), TextChunker.normalize(longA))
    }

    func testDigitsWeighHeavier() {
        XCTAssertEqual(TextChunker.estimatedUnits("ab"), 2)
        XCTAssertEqual(TextChunker.estimatedUnits("2031"), 12)
    }

    // MARK: - Giant paragraphs

    private static let sentencePool = [
        "The committee met again on Thursday, and after nearly four hours of debate it agreed to delay the vote until the engineers could explain why the northern pumping station had failed twice in one winter.",
        "Nobody was surprised.",
        "Residents had complained for years about brown water, low pressure, and bills that seemed to rise every quarter whether or not anything was fixed.",
        "Dr. Alvarez, who has studied the system since 1998, said the pipes were laid in 1931 and were never meant to carry today's load.",
        "She showed a map; it was covered in red dots.",
        "Each dot marked a break, a leak, or a valve that no longer closed, and the densest cluster sat directly under the old market square where the city planned its new library.",
        "Why, one councillor asked, had no one mentioned this before the library contract was signed?",
        "The room went quiet.",
    ]

    /// ≈10,000 chars, normal punctuation; opens with a 200-char sentence (> Kokoro firstTarget).
    private static let giantPunctuated: String = {
        var parts: [String] = []
        var i = 0
        while parts.joined(separator: " ").count < 10_000 {
            parts.append(sentencePool[i % sentencePool.count])
            i += 1
        }
        return parts.joined(separator: " ")
    }()

    /// ≈5,000 chars, one "sentence": words and spaces only (no periods or commas).
    private static let giantRunOn: String = {
        let words = "the river kept rising through the night while the town slept and nobody heard the sirens until morning when water reached the steps of the old church".split(separator: " ")
        var out: [Substring] = []
        var i = 0
        while out.joined(separator: " ").count < 5_000 {
            out.append(words[i % words.count])
            i += 1
        }
        return out.joined(separator: " ")
    }()

    /// A 600-char whitespace-free token.
    private static let longURL: String = {
        var s = "https://example.com/archive/2026/09/24/"
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz-_")
        var i = 0
        while s.count < 600 { s.append(alphabet[i % alphabet.count]); i += 1 }
        return s
    }()

    /// Every invariant, walking the chunks back over `normalize(text)`:
    /// ≤ hardMax, first ≤ firstTarget, exact reassembly, and a cut not at a space only inside a
    /// whitespace-free run too long for a chunk.
    private func assertInvariants(_ text: String, _ limits: TextChunker.Limits,
                                  file: StaticString = #filePath, line: UInt = #line) {
        let chunks = TextChunker.chunks(for: text, limits: limits)
        let normalized = Array(TextChunker.normalize(text))
        XCTAssertFalse(chunks.isEmpty, file: file, line: line)
        for (i, chunk) in chunks.enumerated() {
            XCTAssertLessThanOrEqual(TextChunker.estimatedUnits(chunk), limits.hardMax,
                                     "chunk \(i) over hardMax", file: file, line: line)
            XCTAssertFalse(chunk.isEmpty, file: file, line: line)
        }
        if chunks.count > 1 {
            XCTAssertLessThanOrEqual(TextChunker.estimatedUnits(chunks[0]), limits.firstTarget,
                                     "first chunk over firstTarget: \(chunks[0].count) chars", file: file, line: line)
        }
        var pos = 0
        for (i, chunk) in chunks.enumerated() {
            let c = Array(chunk)
            guard pos + c.count <= normalized.count, Array(normalized[pos..<(pos + c.count)]) == c else {
                XCTFail("chunk \(i) does not continue the text at \(pos)", file: file, line: line)
                return
            }
            pos += c.count
            guard pos < normalized.count else { break }
            if normalized[pos] == " " {
                pos += 1
            } else {
                // Mid-run cut: only allowed when the whole whitespace-free run can't fit a chunk.
                var a = pos, b = pos
                while a > 0, normalized[a - 1] != " " { a -= 1 }
                while b < normalized.count, normalized[b] != " " { b += 1 }
                let run = String(normalized[a..<b])
                XCTAssertGreaterThan(TextChunker.estimatedUnits(run), limits.firstTarget,
                                     "chunk \(i) split the word \"\(run)\"", file: file, line: line)
            }
        }
        XCTAssertEqual(pos, normalized.count, "chunks do not cover the whole text", file: file, line: line)
        XCTAssertEqual(chunks.joined().filter { !$0.isWhitespace },
                       String(normalized).filter { !$0.isWhitespace }, file: file, line: line)
    }

    func testGiantPunctuatedParagraph() {
        XCTAssertGreaterThanOrEqual(Self.giantPunctuated.count, 10_000)
        XCTAssertGreaterThan(Self.sentencePool[0].count, TextChunker.Limits.kokoro.firstTarget)
        assertInvariants(Self.giantPunctuated, .kokoro)
        assertInvariants(Self.giantPunctuated, .tenSecondCall)
    }

    func testGiantRunOnSentenceWithoutPunctuation() {
        XCTAssertGreaterThanOrEqual(Self.giantRunOn.count, 5_000)
        XCTAssertFalse(Self.giantRunOn.contains(where: { ".,;:!?".contains($0) }))
        assertInvariants(Self.giantRunOn, .kokoro)
        assertInvariants(Self.giantRunOn, .tenSecondCall)
    }

    func testLongTokenWithoutSpaces() {
        XCTAssertEqual(Self.longURL.count, 600)
        assertInvariants(Self.longURL, .kokoro)
        assertInvariants("See \(Self.longURL) for the full minutes of the meeting.", .kokoro)
        assertInvariants(Self.longURL, .tenSecondCall)
        // Cut pieces reassemble to the exact token.
        XCTAssertEqual(TextChunker.chunks(for: Self.longURL, limits: .kokoro).joined(), Self.longURL)
    }
}
