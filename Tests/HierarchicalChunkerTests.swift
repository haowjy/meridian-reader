import AVFoundation
import XCTest
@testable import Reader

/// Audio chunking of giant run-on paragraphs (The Forgotten, royalroad 178276, "Prologue /
/// Chapter One: Gunner", 2026-09-25: "sounds like it's breaking up"). Real text, app paragraphs
/// p6 (2,543 chars), p7 (1,397) and p15 (1,121). The old chunker cut "pound on the | door",
/// "Smallpox, | announcing", "business admin, | etc-. The next Castra"; joins were ≈0.8 s of
/// dead air; and 16 % of the audio was NaN (pops + silence, fixed in KokoroONNXModelPatch).
final class HierarchicalChunkerTests: XCTestCase {
    static let p6 = "Okay, I’m gonna give you a bit of a rundown of the state of the, well, states. My parents gave me the occasional history lesson and now it's my turn to pass that knowledge on to you. After the Russian/Ukrainian war ended about 2.5 hundred years ago, -nobody can give me an exact year, answers vary, but the most common is 2031- people became restless. Everyone had thought it would be WWIII, especially when Britain joined the war. Following a threat from a Russian scientist, saying they would release bombs containing the virus Smallpox, announcing that they had evolved it to the point that it could wipe out the whole population, people freaked out, remembering the recent pandemic of COVID-19. The most out-of-stock thing people had trouble buying was toilet paper. Superstores and supermarkets were swamped. There were hundreds of people rushing into stores to buy toilet paper and canned food, -is that just food in a can? - it lasted longer like that apparently. When the war ended, again, no specific date, the world was restless. Much of Asia and Europe had been destroyed, only small, nondescript towns staying afloat. Other countries had civil unrest, leading to civil wars. The president by the end was no longer Trump, instead, it was Ian Ericcson-Sprucefeld. He decided to prevent civil unrest, and the Castra system was born. A long dead language, called Latin, was the basis for all the Castra names. Castra means camp, because you are sent to camps based on your skill. This isn't like any super nitty gritty camp, down in the dirt; it's just the name used for the different groups. Each Castra was named after the type of jobs necessary to keep a civilization afloat. The first group, Scienta, or knowledge, consists of jobs in departments such as healthcare, –nurse, doctor, etc- technology, -programmer, civil engineer, etc- and business –accountant, business admin, etc-. The next Castra, Arte, or skill, has jobs such as construction, -site formation, structural engineering, etc- and agriculture, -farming, etc- Castra number three, Entrepreneur, which is the same in both languages, includes things such as entrepreneur, -startup founder, business owner, etc- and business consultant -. Second to last, Artium, or arts with jobs such as performing arts, -actings, vocals, instruments- creative arts, -art, writing, etc-. Finally, Liberandum, or rescue, jobs such as search and rescue -though it’s not as necessary with the organized Castras, they’re more backup for other rescue services, paramedics, fire, and police."
    static let p7 = "At first, people didn't like the rules. There were too many restrictions, not enough freedom. Some individuals would skip out on their tests, refusing to become part the “New America”.   President I. Ericcson-Sprucefeld, said at a press conference, much lacking in actual press, that, “the government has a very powerful weapon in its grasp that, if needed, would be unleashed on the entire population of the U.S.A., no matter how many people are involved.” This shut people up real fast, those involved not wanting their families to get hurt. Once every one of age was tested, underage children would stay with both parents, alternating weeks, until Testing Day.  Every year, children at the age of 10 and 16 were tested. For 10-year-olds, they would get tested, just see what they have a gift for. Teachers and parents would use the results from the test, along with the child’s interests, to put more focus on the prominent gifts. Then at 16, they were tested a little more intensely, these tests defining what they should and shouldn't do. The teen would then come back out to the central room and announce the Castra of their choice. Their choice may not reflect their test results; it may, but sometimes they choose based off personal interests. These new Conscribes, or recruits, would pack up their belongings, have a three-day period to say goodbye and then they move to their new Castra."
    static let p15 = "I'm quickly finishing up when my mother decides it's her turn to pound on the door. “Gunner, we’re going to be late!” Her shadow moves under the door. “Hurry up.” Panic spikes in my stomach, little daggers that want to cut me apart. I shut off the faucet, slick back my hair one more time with my wet hands and run out the door, dragging my hands along a hanging towel on my way out of the bathroom. My socks slip along the hardwood floors, and I snag my leather jacket off the dining table chair that I sat in for breakfast. Nobody cares if you dress nicely, just wear clothes. Shoving my feet into my shoes, I hop out the door and head to our pickup truck. No, don't imagine those old, rusted out pickup trucks from the 21st century. Think, sleek, rounded edges with bright headlights. Sensors open the doors, DNA activated. The wheels? There aren’t any. It floats over the driveway, using the minerals in the earth to push off the ground. It must be held up on rubber blocks when off, so it doesn't scrape on the ground. I run across the driveway, press my thumb against the scanner pad, yank open my door, and scream."

    private let limits = TextChunker.Limits.kokoroCPU
    private var giants: [String] { [Self.p6, Self.p7, Self.p15] }

    private func units(_ s: String) -> Int { TextChunker.estimatedUnits(s) }

    private func endsAtBoundary(_ s: String) -> Bool {
        var t = Substring(s)
        while let c = t.last, "\"'”’)]»".contains(c) { t = t.dropLast() }
        guard let last = t.last else { return false }
        return ".!?…,;:—".contains(last)
    }

    func testGiantParagraphsReassembleExactly() {
        for para in giants {
            let chunks = TextChunker.chunks(for: para, limits: limits)
            XCTAssertEqual(chunks.joined(separator: " "), TextChunker.normalize(para),
                           "chunks must be the paragraph, in order, nothing dropped")
            XCTAssertTrue(chunks.allSatisfy { !$0.isEmpty && $0 == $0.trimmingCharacters(in: .whitespaces) })
        }
    }

    func testEveryCutIsAtSentenceOrClauseBoundary() {
        for para in giants {
            let chunks = TextChunker.chunks(for: para, limits: limits)
            for (i, c) in chunks.enumerated() {
                XCTAssertLessThanOrEqual(units(c), limits.hardMax, "chunk \(i) over hardMax: \(c)")
                XCTAssertTrue(endsAtBoundary(c), "chunk \(i) cut mid-phrase: …\(c.suffix(50))")
                XCTAssertFalse(c.lowercased().hasPrefix("etc"), "tail of a list stuck to the next chunk: \(c.prefix(40))")
            }
        }
    }

    func testMostCutsAreSentenceEnds() {
        var sentence = 0, total = 0
        for para in giants {
            for c in TextChunker.chunks(for: para, limits: limits).dropLast() {
                total += 1
                var t = Substring(c)
                while let ch = t.last, "\"'”’)]»".contains(ch) { t = t.dropLast() }
                if let l = t.last, ".!?…".contains(l) { sentence += 1 }
            }
        }
        // 29 cuts: 27 at sentence ends, 2 at commas inside 300+-char list sentences.
        XCTAssertGreaterThanOrEqual(Double(sentence) / Double(total), 0.9, "\(sentence)/\(total)")
    }

    func testFirstChunkIsShortAndNotAWordCut() {
        for para in giants {
            let first = TextChunker.chunks(for: para, limits: limits)[0]
            XCTAssertTrue(endsAtBoundary(first), first)
            XCTAssertLessThanOrEqual(units(first), limits.firstTarget + TextChunker.Limits.firstSlack)
        }
        // Old: "…decides it's her turn to pound on the" | "door."
        XCTAssertEqual(TextChunker.chunks(for: Self.p15, limits: limits)[0],
                       "I'm quickly finishing up when my mother decides it's her turn to pound on the door.")
    }

    func testHeadStartRampNeverOutrunsRendering() {
        // Chunk k renders while chunks 0…k−1 play; rendering is ≥ 2.4× real time on the phone.
        for para in giants {
            let u = TextChunker.chunks(for: para, limits: limits).map(units)
            XCTAssertLessThanOrEqual(u[0], limits.firstTarget + TextChunker.Limits.firstSlack)
            for k in 1..<u.count {
                let rendered = u[1...k].reduce(0, +)
                let played = u[0..<k].reduce(0, +)
                XCTAssertLessThanOrEqual(Double(rendered) / 2.4, Double(played) + 1,
                                         "chunk \(k) (\(u[k])) would stall: \(u)")
            }
        }
    }

    func testKnownBadCutsAreGone() {
        let p6 = TextChunker.chunks(for: Self.p6, limits: limits)
        XCTAssertTrue(p6.contains { $0.hasSuffix("announcing that they had evolved it to the point that it could wipe out the whole population, people freaked out, remembering the recent pandemic of COVID-19.") },
                      "Smallpox sentence stays whole")
        let i = p6.firstIndex { $0.hasSuffix("business admin, etc.") }
        XCTAssertNotNil(i, "\"etc-.\" normalised and treated as the sentence end")
        if let i { XCTAssertTrue(p6[i + 1].hasPrefix("The next Castra")) }
        XCTAssertLessThan(p6.count, 19, "old plan had 19 chunks for p6")
        let p7 = TextChunker.chunks(for: Self.p7, limits: limits)
        XCTAssertFalse(p7.contains { $0.hasSuffix("President I.") }, "initial is not a sentence end")
        XCTAssertTrue(p7.contains { $0.hasPrefix("President I. Ericcson-Sprucefeld, said at a press conference") })
    }

    func testChunkPlanIsDeterministic() {
        for para in giants {
            XCTAssertEqual(TextChunker.chunks(for: para, limits: limits), TextChunker.chunks(for: para, limits: limits))
        }
    }

    func testBalancedSplitOfOverlongSentence() {
        let s = (1...14).map { "the item number \($0) on the long list" }.joined(separator: ", ") + "."
        XCTAssertGreaterThan(units(s), limits.hardMax)
        let parts = TextChunker.balancedSplit(s, target: limits.target, hardMax: limits.hardMax)
        XCTAssertEqual(parts.joined(separator: " "), s)
        XCTAssertGreaterThan(parts.count, 1)
        XCTAssertTrue(parts.allSatisfy { units($0) <= limits.hardMax })
        XCTAssertTrue(parts.dropLast().allSatisfy { $0.hasSuffix(",") }, "\(parts)")
        let sizes = parts.map(units)
        XCTAssertGreaterThanOrEqual(Double(sizes.min()!), 0.5 * Double(sizes.max()!), "balanced: \(sizes)")
    }

    func testSplitHeadPrefersClauseOverConjunctionOverSpace() {
        let s = "He walked down the long road; and then he saw the house by the river and stopped."
        XCTAssertEqual(TextChunker.splitHead(s, maxUnits: 50, minStrength: .space)?.0, "He walked down the long road;")
        let t = "He walked down the long dusty road to the old house by the river and then stopped."
        XCTAssertEqual(TextChunker.splitHead(t, maxUnits: 70, minStrength: .space)?.0,
                       "He walked down the long dusty road to the old house by the river")
        XCTAssertNil(TextChunker.splitHead(t, maxUnits: 70, minStrength: .comma))
    }

    func testDashGluedToPunctuationIsDropped() {
        XCTAssertEqual(TextChunker.normalize("accountant, business admin, etc-. The next"), "accountant, business admin, etc. The next")
        XCTAssertEqual(TextChunker.normalize("farming, etc-, and"), "farming, etc, and")
        XCTAssertEqual(TextChunker.normalize("a well-known out-of-stock item."), "a well-known out-of-stock item.")
    }

    func testKokoroCPULimits() {
        XCTAssertEqual(limits.target, 240)
        XCTAssertEqual(limits.hardMax, 280)
        XCTAssertEqual(limits.firstTarget, 80)
        XCTAssertLessThanOrEqual(limits.hardMax + 40, KokoroCPUHost.maxTokensPerCall)
    }
}

/// Silence at chunk joins (Kokoro pads each call with ≈0.3 s + ≈0.5 s).
final class ChunkEdgeTrimTests: XCTestCase {
    private let sr = 24_000

    private func tone(ms: Int, amp: Float = 0.2) -> [Float] {
        (0..<(sr * ms / 1000)).map { amp * sin(Float($0) * 2 * .pi * 220 / Float(sr)) }
    }
    private func silence(ms: Int, floor: Float = 0.0004) -> [Float] {
        (0..<(sr * ms / 1000)).map { floor * sin(Float($0) * 0.37) }
    }

    func testTrimsKokoroPaddingToBoundaryPause() {
        let input = silence(ms: 330) + tone(ms: 1000) + silence(ms: 520)
        for b in [ChunkEdgeTrim.Boundary.paragraphEnd, .sentence, .clause, .word] {
            let out = ChunkEdgeTrim.trim(input, sampleRate: sr, trailMs: ChunkEdgeTrim.trailMs(b))
            let expected = (ChunkEdgeTrim.leadMs + 1000 + ChunkEdgeTrim.trailMs(b)) * sr / 1000
            XCTAssertEqual(Double(out.count), Double(expected), accuracy: Double(sr) * 0.011, "\(b)")
        }
        XCTAssertEqual(ChunkEdgeTrim.trailMs(.sentence) + ChunkEdgeTrim.leadMs, 400, "sentence join ≈ 0.4 s")
        XCTAssertEqual(ChunkEdgeTrim.trailMs(.clause) + ChunkEdgeTrim.leadMs, 220, "comma join ≈ 0.22 s")
    }

    func testPadsWhenTrailIsShort() {
        let input = silence(ms: 20) + tone(ms: 500)
        let out = ChunkEdgeTrim.trim(input, sampleRate: sr, trailMs: 360)
        XCTAssertEqual(Double(out.count), Double((20 + 500 + 360) * sr / 1000), accuracy: Double(sr) * 0.011)
        XCTAssertEqual(out.suffix(sr / 10).map(abs).max()!, 0, accuracy: 1e-6)
    }

    func testKeepsVoicedAudioIntact() {
        let voiced = tone(ms: 800)
        let out = ChunkEdgeTrim.trim(silence(ms: 300) + voiced + silence(ms: 500), sampleRate: sr, trailMs: 180)
        let lead = ChunkEdgeTrim.leadMs * sr / 1000
        let body = Array(out[lead..<(lead + voiced.count)])
        let err = zip(body.dropFirst(sr / 100), voiced.dropFirst(sr / 100)).map { abs($0 - $1) }.max()!
        XCTAssertLessThan(err, 1e-6, "no voiced sample removed or changed")
    }

    func testAllSilentUnchanged() {
        let input = silence(ms: 400)
        XCTAssertEqual(ChunkEdgeTrim.trim(input, sampleRate: sr, trailMs: 360), input)
    }

    func testBoundaryDetection() {
        XCTAssertEqual(ChunkEdgeTrim.boundary(after: "It was late.", isLastInParagraph: false), .sentence)
        XCTAssertEqual(ChunkEdgeTrim.boundary(after: "“Hurry up.”", isLastInParagraph: false), .sentence)
        XCTAssertEqual(ChunkEdgeTrim.boundary(after: "structural engineering,", isLastInParagraph: false), .clause)
        XCTAssertEqual(ChunkEdgeTrim.boundary(after: "down in the dirt;", isLastInParagraph: false), .clause)
        XCTAssertEqual(ChunkEdgeTrim.boundary(after: "pound on the", isLastInParagraph: false), .word)
        XCTAssertEqual(ChunkEdgeTrim.boundary(after: "pound on the", isLastInParagraph: true), .paragraphEnd)
    }
}

final class LocalPCMWriterNaNTests: XCTestCase {
    func testNonFiniteSamplesBecomeSilenceNotFullScale() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nan-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        var samples = [Float](repeating: 0.1, count: 2400)
        for i in 1000..<1400 { samples[i] = .nan }
        samples[1500] = .infinity
        try LocalPCMWriter.write(samples, sampleRate: 24_000, to: url)
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buf)
        let ch = UnsafeBufferPointer(start: buf.floatChannelData![0], count: Int(buf.frameLength))
        XCTAssertEqual(ch.count, 2400)
        XCTAssertEqual(ch[1200], 0, accuracy: 1e-4, "NaN → 0 (was +1.0 full scale)")
        XCTAssertEqual(ch[1500], 0, accuracy: 1e-4)
        XCTAssertEqual(ch[100], 0.1, accuracy: 1e-3)
    }
}
