import XCTest
@testable import MeridianReader

/// ONNX fp16 Kokoro NaN: text that renders all-NaN audio with the unpatched model, and the model
/// patch (`KokoroONNXModelPatch`) that fixes it. Simulator-only; needs the Mac research model.
final class KokoroNaNProbeTests: XCTestCase {
    /// Public-domain lines (The Adventures of Sherlock Holmes, 1892). The first is all-NaN with the
    /// unpatched model on the simulator (ORT 1.24.2); the others render clean, to check the patch
    /// changes nothing else.
    static let texts = [
        "My experience of camp life in Afghanistan had at least had the effect of making me a prompt and ready traveller.",
        "“I think of writing another little monograph some of these days on the typewriter and its relation to crime.",
        "Our visitor collapsed into a chair, with a ghastly face and a glitter of moisture on his brow.",
        "What does her clever stepfather do then?",
        "“I cannot now entirely see all the steps of your reasoning,”",
        "Turner had a considerable household, some half-dozen at the least.",
    ]

    /// The Mac research model and Heart's voice pack, with the model patched into a temporary
    /// folder of this case's own (removed when the case ends), so no case reads what another wrote.
    private struct ResearchModel {
        let model: URL
        let patched: URL
        let guarded: Int
        let pack: [Float]
    }

    private func researchModel() throws -> ResearchModel {
        guard let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] else { throw XCTSkip("sim only") }
        let model = URL(fileURLWithPath: home + "/Developer/tts-audition/bg-research/models/onnxcommunity-model_fp16.onnx")
        let packURL = URL(fileURLWithPath: home + "/.cache/fluidaudio/Models/kokoro-82m-coreml/ANE/af_heart.bin")
        guard FileManager.default.fileExists(atPath: model.path) else { throw XCTSkip("research model absent") }
        let packData = try Data(contentsOf: packURL)
        var pack = [Float](repeating: 0, count: packData.count / 4)
        _ = pack.withUnsafeMutableBytes { packData.copyBytes(to: $0) }

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("nanfix-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: tmp) }
        let original = tmp.appendingPathComponent("model_fp16.onnx")
        try FileManager.default.createSymbolicLink(at: original, withDestinationURL: model)
        let t0 = Date()
        let (patched, guarded) = try KokoroONNXModelPatch.writePatched(from: original)
        print("NANFIX patch_ms=\(Int(Date().timeIntervalSince(t0) * 1000)) guarded=\(guarded)")
        return ResearchModel(model: model, patched: patched, guarded: guarded, pack: pack)
    }

    func testPatchedModelHasNoNaNAndOtherwiseIdenticalAudio() async throws {
        let research = try researchModel()
        let (model, patchedURL, pack) = (research.model, research.patched, research.pack)
        XCTAssertEqual(research.guarded, 1)
        XCTAssertEqual(patchedURL.lastPathComponent, "model_fp16_atan2nanfix.onnx")

        let fe = try KokoroAneCPUFrontendHandle()
        let plain = try KokoroONNXSession(modelURL: model, threads: 3)
        let fixed = try KokoroONNXSession(modelURL: patchedURL, threads: 3)
        var plainNaNTexts = 0
        for (i, t) in Self.texts.enumerated() {
            let (ids, n) = try await fe.ids(for: t)
            let inputs = try KokoroCPUTensorBuilder.build(tokenIDs: ids, phonemeCount: n, voicePack: pack)
            let a = try plain.run(inputs)
            let b = try fixed.run(inputs)
            let aNaN = a.contains { !$0.isFinite }
            if aNaN { plainNaNTexts += 1 }
            XCTAssertFalse(b.contains { !$0.isFinite }, "patched model produced NaN for text \(i)")
            XCTAssertEqual(a.count, b.count)
            if !aNaN { XCTAssertEqual(a, b, "patch changed audio for text \(i) (should only touch NaN bins)") }
            print("NANFIX text=\(i) plain_nan=\(aNaN) fixed_rms=\(KokoroCPUAudio.rms(b))")
        }
        XCTAssertGreaterThanOrEqual(plainNaNTexts, 1, "repro text no longer NaN on the unpatched model")
    }

    /// A giant paragraph through the chunk plan, the NaN-patched model and the join trim: every
    /// chunk finite, no full-scale runs, joins ≈ the boundary pause (sentence ≈0.4 s, comma
    /// ≈0.22 s) rather than Kokoro's ≈0.8 s of padding.
    func testGiantParagraphRendersCleanWithNaturalJoins() async throws {
        let research = try researchModel()
        let pack = research.pack
        let fe = try KokoroAneCPUFrontendHandle()
        let session = try KokoroONNXSession(modelURL: research.patched, threads: 3)
        let sr = KokoroCPUAudio.sampleRate
        let chunks = TextChunker.chunks(for: HierarchicalChunkerTests.inquest, limits: .kokoroCPU)
        var rendered: [[Float]] = []
        var audio = 0.0, wall = 0.0
        for (i, c) in chunks.enumerated() {
            let (ids, n) = try await fe.ids(for: c)
            XCTAssertLessThanOrEqual(ids.count, KokoroCPUHost.maxTokensPerCall, "chunk \(i) tokens")
            let inputs = try KokoroCPUTensorBuilder.build(tokenIDs: ids, phonemeCount: n, voicePack: pack)
            let t0 = Date()
            let raw = try session.run(inputs).map { $0 * KokoroCPUHost.gain }
            wall += Date().timeIntervalSince(t0)
            XCTAssertTrue(KokoroCPUAudio.allFinite(raw), "chunk \(i) NaN: \(c.prefix(40))")
            let b = ChunkEdgeTrim.boundary(after: c, isLastInParagraph: i == chunks.count - 1)
            let out = ChunkEdgeTrim.trim(raw, sampleRate: sr, trailMs: ChunkEdgeTrim.trailMs(b))
            XCTAssertLessThan(out.filter { abs($0) >= 0.98 }.count, sr / 100, "chunk \(i) saturated")
            audio += Double(out.count) / Double(sr)
            rendered.append(out)
            print("GIANT c\(i) chars=\(c.count) tokens=\(ids.count) audio=\(String(format: "%.1f", Double(out.count) / Double(sr)))s b=\(b.rawValue)")
        }
        // Silence at each join = trailing silence of chunk k + leading silence of chunk k+1.
        func silentFrames(_ x: [Float], fromEnd: Bool) -> Int {
            let frame = sr / 100
            let frames = x.count / frame
            var n = 0
            for f in 0..<frames {
                let idx = fromEnd ? frames - 1 - f : f
                let s = x[(idx * frame)..<((idx + 1) * frame)]
                let rms = (s.reduce(0) { $0 + $1 * $1 } / Float(frame)).squareRoot()
                if rms > ChunkEdgeTrim.threshold { break }
                n += 1
            }
            return n
        }
        for k in 0..<(rendered.count - 1) {
            let gap = Double(silentFrames(rendered[k], fromEnd: true) + silentFrames(rendered[k + 1], fromEnd: false)) / 100
            let b = ChunkEdgeTrim.boundary(after: chunks[k], isLastInParagraph: false)
            print("GIANT join \(k)|\(k + 1) \(b.rawValue) gap=\(String(format: "%.2f", gap))s")
            let target = Double(ChunkEdgeTrim.trailMs(b) + ChunkEdgeTrim.leadMs) / 1000
            XCTAssertEqual(gap, target, accuracy: 0.12, "join \(k) \(b.rawValue)")
        }
        print("GIANT chunks=\(chunks.count) audio=\(Int(audio))s wall=\(Int(wall))s rtf=\(String(format: "%.1f", audio / wall))x")
    }

    func testPatchRejectsNonModelData() {
        XCTAssertThrowsError(try KokoroONNXModelPatch.patch(Data([0x08, 0x07])))
        XCTAssertEqual(KokoroONNXModelPatch.encodeVarint(300), [0xAC, 0x02])
    }
}
