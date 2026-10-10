import AVFoundation
import XCTest
@testable import MeridianReader

/// Audio chunking of giant run-on paragraphs. Fixture text is public domain: Arthur Conan Doyle,
/// "The Boscombe Valley Mystery" (1891). Joins between chunks must fall where a reader pauses
/// (sentence ends, clauses), never between bare words.
final class HierarchicalChunkerTests: XCTestCase {
    /// 1,881 chars; the display split cuts it into three pieces.
    static let inquest = "“The two McCarthys were seen after the time when William Crowder, the game-keeper, lost sight of them. The Boscombe Pool is thickly wooded round, with just a fringe of grass and of reeds round the edge. A girl of fourteen, Patience Moran, who is the daughter of the lodge-keeper of the Boscombe Valley estate, was in one of the woods picking flowers. She states that while she was there she saw, at the border of the wood and close by the lake, Mr. McCarthy and his son, and that they appeared to be having a violent quarrel. She heard Mr. McCarthy the elder using very strong language to his son, and she saw the latter raise up his hand as if to strike his father. She was so frightened by their violence that she ran away and told her mother when she reached home that she had left the two McCarthys quarrelling near Boscombe Pool, and that she was afraid that they were going to fight. She had hardly said the words when young Mr. McCarthy came running up to the lodge to say that he had found his father dead in the wood, and to ask for the help of the lodge-keeper. He was much excited, without either his gun or his hat, and his right hand and sleeve were observed to be stained with fresh blood. On following him they found the dead body stretched out upon the grass beside the pool. The head had been beaten in by repeated blows of some heavy and blunt weapon. The injuries were such as might very well have been inflicted by the butt-end of his son’s gun, which was found lying on the grass within a few paces of the body. Under these circumstances the young man was instantly arrested, and a verdict of ‘wilful murder’ having been returned at the inquest on Tuesday, he was on Wednesday brought before the magistrates at Ross, who have referred the case to the next Assizes. Those are the main facts of the case as they came out before the coroner and the police-court.”"
    /// 2,083 chars, quoted testimony with "Mr." abbreviations and an exclamation inside quotes.
    static let testimony = "“Mr. James McCarthy, the only son of the deceased, was then called and gave evidence as follows: ‘I had been away from home for three days at Bristol, and had only just returned upon the morning of last Monday, the 3rd. My father was absent from home at the time of my arrival, and I was informed by the maid that he had driven over to Ross with John Cobb, the groom. Shortly after my return I heard the wheels of his trap in the yard, and, looking out of my window, I saw him get out and walk rapidly out of the yard, though I was not aware in which direction he was going. I then took my gun and strolled out in the direction of the Boscombe Pool, with the intention of visiting the rabbit warren which is upon the other side. On my way I saw William Crowder, the game-keeper, as he had stated in his evidence; but he is mistaken in thinking that I was following my father. I had no idea that he was in front of me. When about a hundred yards from the pool I heard a cry of “Cooee!” which was a usual signal between my father and myself. I then hurried forward, and found him standing by the pool. He appeared to be much surprised at seeing me and asked me rather roughly what I was doing there. A conversation ensued which led to high words and almost to blows, for my father was a man of a very violent temper. Seeing that his passion was becoming ungovernable, I left him and returned towards Hatherley Farm. I had not gone more than 150 yards, however, when I heard a hideous outcry behind me, which caused me to run back again. I found my father expiring upon the ground, with his head terribly injured. I dropped my gun and held him in my arms, but he almost instantly expired. I knelt beside him for some minutes, and then made my way to Mr. Turner’s lodge-keeper, his house being the nearest, to ask for assistance. I saw no one near my father when I returned, and I have no idea how he came by his injuries. He was not a popular man, being somewhat cold and forbidding in his manners, but he had, as far as I know, no active enemies. I know nothing further of the matter.’"
    /// 1,135 chars: under the display-split threshold, so audio chunking alone shapes it.
    static let belowThreshold = "“On the contrary,” said Holmes, “it is the brightest rift which I can at present see in the clouds. However innocent he might be, he could not be such an absolute imbecile as not to see that the circumstances were very black against him. Had he appeared surprised at his own arrest, or feigned indignation at it, I should have looked upon it as highly suspicious, because such surprise or anger would not be natural under the circumstances, and yet might appear to be the best policy to a scheming man. His frank acceptance of the situation marks him as either an innocent man, or else as a man of considerable self-restraint and firmness. As to his remark about his deserts, it was also not unnatural if you consider that he stood beside the dead body of his father, and that there is no doubt that he had that very day so far forgotten his filial duty as to bandy words with him, and even, according to the little girl whose evidence is so important, to raise his hand as if to strike him. The self-reproach and contrition which are displayed in his remark appear to me to be the signs of a healthy mind rather than of a guilty one.”"

    private let limits = TextChunker.Limits.kokoroCPU
    private var giants: [String] { [Self.inquest, Self.testimony, Self.belowThreshold] }

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
        // 28 cuts, 25 at sentence ends; the rest are clause cuts in the fast-start ramp or inside a
        // sentence longer than hardMax.
        XCTAssertGreaterThanOrEqual(Double(sentence) / Double(total), 0.85, "\(sentence)/\(total)")
    }

    func testFirstChunkIsShortAndNotAWordCut() {
        for para in giants {
            let first = TextChunker.chunks(for: para, limits: limits)[0]
            XCTAssertTrue(endsAtBoundary(first), first)
            XCTAssertLessThanOrEqual(units(first), limits.firstTarget + TextChunker.Limits.firstSlack)
        }
        // A 99-unit first sentence fits the first-chunk slack: whole, not "…see in the" | "clouds."
        XCTAssertEqual(TextChunker.chunks(for: Self.belowThreshold, limits: limits)[0],
                       "“On the contrary,” said Holmes, “it is the brightest rift which I can at present see in the clouds.")
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

    func testAbbreviationsAndQuotedExclamationsAreNotCutPoints() {
        for para in giants {
            for c in TextChunker.chunks(for: para, limits: limits) {
                XCTAssertFalse(c.hasSuffix("Mr."), "\"Mr.\" is not a sentence end: …\(c.suffix(40))")
                XCTAssertFalse(c.hasSuffix("“Cooee!”"), "a lowercase word follows, so the sentence goes on")
            }
        }
        let testimony = TextChunker.chunks(for: Self.testimony, limits: limits)
        XCTAssertTrue(testimony.contains { $0.contains("“Cooee!” which was a usual signal") })
    }

    func testListEndingInDashedEtcEndsTheSentence() {
        let para = "The stall sold bread, cheese, apples, rope, lamp oil, candles, nails, etc-. The next stall "
            + "sold nothing but fish, and the one after that sold nothing at all. " + String(repeating: "More words follow here. ", count: 12)
        let chunks = TextChunker.chunks(for: para, limits: limits)
        XCTAssertFalse(chunks.contains { $0.lowercased().hasPrefix("etc") }, "\(chunks)")
        XCTAssertEqual(TextChunker.splitSentences(TextChunker.normalize(para)).first,
                       "The stall sold bread, cheese, apples, rope, lamp oil, candles, nails, etc.")
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
        XCTAssertEqual(TextChunker.normalize("bread, cheese, etc-. The next"), "bread, cheese, etc. The next")
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
