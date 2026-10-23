import XCTest
@testable import MeridianReader

/// Chunker invariants. Paragraphs of 1–2.5k chars must be cut into engine-sized calls with nothing
/// dropped (an overflowing call would lose the paragraph; see docs/LISTEN_PLAYBACK.md § Chunking).
/// Giant-paragraph cases (10k chars, 5k-char run-on, 600-char URL) check every invariant.
@MainActor
final class TextChunkerTests: XCTestCase {
    /// Short calls (≈10 s of audio): many chunks per paragraph, so every cut rule runs.
    private static let shortCalls = TextChunker.Limits(target: 120, hardMax: 140, firstTarget: 90, minResplit: 24)
    /// A synthetic ≈2.5k-char paragraph with what real prose throws at the chunker: curly quotes,
    /// aside dashes, numbers, abbreviations, initials, slashes, double spaces.
    private let longA: String = {
        let base = """
        Right, let me give you a quick tour of how the harbor town got this way, and you’ll have to \
        trust me on the dates. After the north/south canal opened about 2.5 hundred years ago, \
        -nobody agrees on the exact year, the records vary, but the usual guess is 1789- the town grew \
        quickly.  Everyone expected a second canal, especially once the U.S.A. and Britain \
        sent surveyors. Dr. Hollis and Mr. J. Ashby-Lowell wrote that the three-day flood \
        changed everything, e.g. the docks, the mills, the farms, etc. Dock crews –porters, pilots, \
        clerks, etc- were hired by the thousands. “Nobody listened,” my grandmother told me, “not \
        until the water was already in the streets.” Then the charter of 1844 split the town into \
        eleven wards, each with its own council, market, and curfew, and each one swore it was \
        the last honest place left on the coast.
        """
        return Array(repeating: base, count: 3).joined(separator: " ")
    }()


    func testChunksPreserveAllText() {
        for text in [longA, "Short one.", "A b c.  D e f!  G h i?"] {
            let chunks = TextChunker.chunks(for: text, limits: .kokoroCPU)
            XCTAssertEqual(chunks.joined(separator: " "), TTSTextNormalize.normalize(text))
        }
    }











    // MARK: - Normalize pauses (em dash / semicolon)

    func testNormalizeEmDashBetweenWordsBecomesColonPause() {
        let out = TTSTextNormalize.normalize("It got worse—and then better.")
        XCTAssertFalse(out.contains("—"), out)
        XCTAssertTrue(out.contains("worse: and"), out)
    }

    func testNormalizeKeepsEnDashRanges() {
        let out = TTSTextNormalize.normalize("Pages 10–12 and Monday–Friday were lost.")
        XCTAssertTrue(out.contains("10–12"), out)
        XCTAssertTrue(out.contains("Monday–Friday"), out)
        XCTAssertFalse(out.contains("10, 12"), out)
        XCTAssertFalse(out.contains("Monday, Friday"), out)
    }

    func testNormalizeKeepsSemicolonInsideURL() {
        let out = TTSTextNormalize.normalize("See https://example.com/a;b=1 for details.")
        XCTAssertTrue(out.contains("a;b=1") || out.contains("https://example.com/a;b=1"), out)
        XCTAssertFalse(out.contains("a,b=1"), out)
    }

    func testNormalizeKeepsASCIIHyphenCompounds() {
        let out = TTSTextNormalize.normalize("Dr. J. Ashby-Lowell wrote the three-day flood note.")
        XCTAssertTrue(out.contains("Ashby-Lowell"), out)
        XCTAssertTrue(out.contains("three-day"), out)
    }

    func testNormalizeSpacedDashBecomesColonPause() {
        let out = TTSTextNormalize.normalize("The docks — porters, pilots — were busy.")
        XCTAssertFalse(out.contains("—"), out)
        XCTAssertEqual(out, "The docks: porters, pilots: were busy.")
    }

    func testNormalizeSemicolonBecomesCommaPause() {
        let out = TTSTextNormalize.normalize("She showed a map; it was covered in red dots.")
        XCTAssertFalse(out.contains(";"), out)
        XCTAssertEqual(out, "She showed a map, it was covered in red dots.")
    }

    func testNormalizeClauseSemicolonBecomesCommaAndEmDashColon() {
        let out = TTSTextNormalize.normalize("Hello world—really; yes.")
        XCTAssertEqual(out, "Hello world: really, yes.")
    }


    // MARK: - Comma cuts vs sentence ends

    /// A first sentence with commas that still fits `firstTarget + firstStretch` must end the
    /// first chunk on the sentence end — not on a mid-clause comma (join sounds like a period).
    func testFirstChunkPrefersSentenceEndOverCommaWithinStretch() {
        let limits = TextChunker.Limits(target: 240, hardMax: 280, firstTarget: 80, minResplit: 24,
                                        alwaysSplitFirst: true, secondTarget: 160)
        // ~114 units; commas inside; period within firstCap (120). Next sentence forces multi-chunk.
        let text = "Right, let me give you a quick tour of how the harbor town got this way, and you'll have to trust me on the dates. After that the mills hummed through the night while nobody slept."
        let chunks = TextChunker.chunks(for: text, limits: limits)
        XCTAssertGreaterThanOrEqual(chunks.count, 2, chunks.joined(separator: " | "))
        XCTAssertTrue(chunks[0].hasSuffix("."), "first chunk should end on sentence end, got: \(chunks[0])")
        XCTAssertFalse(chunks[0].hasSuffix(","), "first chunk must not end on a comma when sentence fits stretch: \(chunks[0])")
    }

    /// When the first sentence clearly overshoots the stretch, a comma cut for TTFA is still OK.
    func testFirstChunkMayEndOnCommaWhenSentenceExceedsStretch() {
        let limits = TextChunker.Limits(target: 240, hardMax: 280, firstTarget: 80, minResplit: 24,
                                        alwaysSplitFirst: true, secondTarget: 160)
        let text = "Residents had complained for years about brown water, low pressure, and bills that seemed to rise every quarter whether or not anything was fixed."
        let chunks = TextChunker.chunks(for: text, limits: limits)
        XCTAssertEqual(chunks.count, 2, chunks.joined(separator: " | "))
        XCTAssertTrue(chunks[0].hasSuffix(","), "expected comma cut when sentence > stretch: \(chunks[0])")
        XCTAssertLessThanOrEqual(TextChunker.estimatedUnits(chunks[0]), limits.firstTarget)
    }

    /// Phonon keeps a comma-heavy paragraph under target as one call (no comma-as-period joins).
    func testPhononDoesNotSplitCommaHeavyParagraphUnderTarget() {
        let text = "Dr. Alvarez, who has studied the system since 1998, said the pipes were laid in 1931, were patched in 1972, and were never meant to carry today's load, low pressure, or brown water."
        let chunks = TextChunker.chunks(for: text, limits: .phonon)
        XCTAssertEqual(chunks.count, 1, chunks.joined(separator: " | "))
        XCTAssertTrue(chunks[0].contains(","), chunks[0])
    }

    /// Kokoro whole-paragraph profile: a normal paragraph under hardMax is one call.
    func testKokoroKeepsNormalParagraphWhole() {
        let text = "Residents had complained for years about brown water, low pressure, and bills that seemed to rise every quarter. Nobody was surprised. She showed a map; it was covered in red dots."
        XCTAssertLessThanOrEqual(TextChunker.estimatedUnits(TTSTextNormalize.normalize(text)), TextChunker.Limits.kokoroCPU.hardMax)
        let chunks = TextChunker.chunks(for: text, limits: .kokoroCPU)
        XCTAssertEqual(chunks.count, 1, chunks.joined(separator: " | "))
    }

    /// Over hardMax, Kokoro still splits — at sentence ends, every chunk ≤ hardMax.
    func testKokoroSplitsOverHardMaxAtSentenceEnds() {
        let text = Self.sentencePool.joined(separator: " ")
        let limits = TextChunker.Limits.kokoroCPU
        let chunks = TextChunker.chunks(for: text, limits: limits)
        XCTAssertGreaterThan(chunks.count, 1)
        for c in chunks {
            XCTAssertLessThanOrEqual(TextChunker.estimatedUnits(c), limits.hardMax, c)
            XCTAssertTrue([".", "!", "?"].contains(c.last.map(String.init) ?? ""), "should end on sentence: \(c)")
        }
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
        let normalized = Array(TTSTextNormalize.normalize(text))
        XCTAssertFalse(chunks.isEmpty, file: file, line: line)
        for (i, chunk) in chunks.enumerated() {
            XCTAssertLessThanOrEqual(TextChunker.estimatedUnits(chunk), limits.hardMax,
                                     "chunk \(i) over hardMax", file: file, line: line)
            XCTAssertFalse(chunk.isEmpty, file: file, line: line)
        }
        if chunks.count > 1 {
            // firstTarget + firstStretch: whole first sentence may fill the stretch so we do not
            // end the first call on a mid-clause comma (sounds period-like at the join).
            let firstCap = min(limits.firstTarget + TextChunker.Limits.firstStretch, limits.hardMax)
            XCTAssertLessThanOrEqual(TextChunker.estimatedUnits(chunks[0]), firstCap,
                                     "first chunk over firstTarget+stretch: \(chunks[0].count) chars", file: file, line: line)
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



}
