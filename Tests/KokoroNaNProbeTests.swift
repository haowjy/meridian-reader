import XCTest
@testable import Reader

/// ONNX fp16 Kokoro NaN (device 2026-09-25): texts that produced all-NaN audio, and the model patch
/// (`KokoroONNXModelPatch`) that fixes it. Simulator-only; needs the Mac research model.
final class KokoroNaNProbeTests: XCTestCase {
    /// "Like we had a choice" is all-NaN with the unpatched model on the simulator (ORT 1.24.2).
    static let texts = [
        "ARTE CASTRA, WHAT ONCE WAS ORLANDO, FLORIDA, 2240",
        "“Like we had a choice.” Aza mutters.",
        "“I'm kidding. Let's go.” I brush past her, looking back to see if she’s following.",
        "Think, sleek, rounded edges with bright headlights. Sensors open the doors, DNA activated. The wheels? There aren’t any.",
        "There were hundreds of people rushing into stores to buy toilet paper and canned food, is that just food in a can? it lasted longer like that apparently.",
        "Okay, I’m gonna give you a bit of a rundown of the state of the, well, states.",
    ]

    func testPatchedModelHasNoNaNAndOtherwiseIdenticalAudio() async throws {
        guard let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] else { throw XCTSkip("sim only") }
        let model = URL(fileURLWithPath: home + "/Developer/tts-audition/bg-research/models/onnxcommunity-model_fp16.onnx")
        let packURL = URL(fileURLWithPath: home + "/.cache/fluidaudio/Models/kokoro-82m-coreml/ANE/af_heart.bin")
        guard FileManager.default.fileExists(atPath: model.path) else { throw XCTSkip("research model absent") }
        let packData = try Data(contentsOf: packURL)
        var pack = [Float](repeating: 0, count: packData.count / 4)
        _ = pack.withUnsafeMutableBytes { packData.copyBytes(to: $0) }

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("nanfix-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let original = tmp.appendingPathComponent("model_fp16.onnx")
        try FileManager.default.createSymbolicLink(at: original, withDestinationURL: model)
        let t0 = Date()
        let (patchedURL, guarded) = try KokoroONNXModelPatch.writePatched(from: original)
        print("NANFIX patch_ms=\(Int(Date().timeIntervalSince(t0) * 1000)) guarded=\(guarded)")
        XCTAssertEqual(guarded, 1)
        XCTAssertEqual(patchedURL.lastPathComponent, "model_fp16_atan2nanfix.onnx")
        // Export for the Mac Python cross-check.
        let export = URL(fileURLWithPath: home + "/Developer/Reader/.probe/nan/patched_swift.onnx")
        try? FileManager.default.removeItem(at: export)
        try? FileManager.default.copyItem(at: patchedURL, to: export)

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

    /// The real 2,543-char run-on paragraph (The Forgotten p6) through the new chunk plan, the
    /// NaN-patched model and the join trim: every chunk finite, no full-scale runs, joins ≈ the
    /// boundary pause (sentence ≈0.4 s, comma ≈0.22 s) instead of ≈0.8 s of dead air.
    func testGiantParagraphRendersCleanWithNaturalJoins() async throws {
        guard let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] else { throw XCTSkip("sim only") }
        let patched = URL(fileURLWithPath: home + "/Developer/Reader/.probe/nan/patched_swift.onnx")
        let packURL = URL(fileURLWithPath: home + "/.cache/fluidaudio/Models/kokoro-82m-coreml/ANE/af_heart.bin")
        guard FileManager.default.fileExists(atPath: patched.path) else { throw XCTSkip("patched model absent") }
        let packData = try Data(contentsOf: packURL)
        var pack = [Float](repeating: 0, count: packData.count / 4)
        _ = pack.withUnsafeMutableBytes { packData.copyBytes(to: $0) }
        let fe = try KokoroAneCPUFrontendHandle()
        let session = try KokoroONNXSession(modelURL: patched, threads: 3)
        let sr = KokoroCPUAudio.sampleRate
        let chunks = TextChunker.chunks(for: HierarchicalChunkerTests.p6, limits: .kokoroCPU)
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
