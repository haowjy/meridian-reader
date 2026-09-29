import XCTest
@testable import Reader

/// The ONNX route's pure-Swift BART G2P must match FluidAudio's Core ML `G2PModel` (same fp16
/// weights, read from the mlmodelc) so switching routes does not change pronunciation.
/// Simulator-only; copies the Mac's FluidAudio cache (`SIMULATOR_HOST_HOME/.cache/fluidaudio`)
/// into the simulator container. Skipped when those assets are absent.
final class KokoroSwiftG2PTests: XCTestCase {
    private func installHostAssets() throws {
        guard let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] else {
            throw XCTSkip("Simulator-only (needs host assets)")
        }
        let hostModels = URL(fileURLWithPath: home + "/.cache/fluidaudio/Models")
        let hostKokoro = hostModels.appendingPathComponent("kokoro")
        let hostVocab = hostModels.appendingPathComponent("kokoro-82m-coreml/ANE/vocab.json")
        let fm = FileManager.default
        let needed = ["G2PEncoder.mlmodelc", "G2PDecoder.mlmodelc", "g2p_vocab.json", "us_lexicon_cache.json"]
        guard needed.allSatisfy({ fm.fileExists(atPath: hostKokoro.appendingPathComponent($0).path) }),
              fm.fileExists(atPath: hostVocab.path) else {
            throw XCTSkip("Host FluidAudio Kokoro assets not present")
        }
        let dirs = try KokoroCPUHost.debugFrontendDirectories()
        try fm.createDirectory(at: dirs.kokoro, withIntermediateDirectories: true)
        try fm.createDirectory(at: dirs.repo, withIntermediateDirectories: true)
        for name in needed {
            let dst = dirs.kokoro.appendingPathComponent(name)
            if !fm.fileExists(atPath: dst.path) {
                try fm.copyItem(at: hostKokoro.appendingPathComponent(name), to: dst)
            }
        }
        let vocabDst = dirs.repo.appendingPathComponent("vocab.json")
        if !fm.fileExists(atPath: vocabDst.path) { try fm.copyItem(at: hostVocab, to: vocabDst) }
    }

    static let names = ["Adric", "Annaliese", "Keo", "Favian", "Irabel", "Wealdswood", "Aldermoon",
                        "Trinkets", "Wowee", "Hermione", "Daenerys", "Tolkien", "Cthulhu", "Nguyen",
                        "Xiomara", "quokka", "zeitgeist", "blorptastic", "unfrobnicate", "Szczepanski"]

    func testSwiftBARTMatchesCoreML() async throws {
        try installHostAssets()
        var words = Set(Self.names)
        if let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"],
           let text = try? String(contentsOfFile: home + "/Developer/Reader/.probe/crash-2346/article-BA7D7639.txt",
                                  encoding: .utf8) {
            for w in text.split(whereSeparator: { !$0.isLetter && $0 != "'" }) where w.count > 1 {
                words.insert(String(w))
            }
        }
        let list = words.sorted()
        let bad = try await KokoroCPUHost.debugCompareG2PWithCoreML(words: list)
        let identical = Double(list.count - bad.count) / Double(list.count)
        print("G2P_COMPARE words=\(list.count) mismatches=\(bad.count) identical=\(String(format: "%.4f", identical))")
        for b in bad.prefix(20) { print("G2P_MISMATCH \(b.word): swift=\(b.swift) coreml=\(b.coreML)") }
        XCTAssertGreaterThanOrEqual(identical, 0.99)
    }

    func testOnnxFrontendPhonemizesWithoutCoreML() async throws {
        try installHostAssets()
        let text = "Adric ruffled Keo’s thick, black hair, which was harder to reach now that he was so tall."
        let start = Date()
        let r = try await KokoroCPUHost.debugPhonemes(text: text)
        print("G2P_FRONTEND ms=\(Int(Date().timeIntervalSince(start) * 1000)) oov=\(r.oovWords) ipa=\(r.phonemes)")
        XCTAssertFalse(r.phonemes.isEmpty)
        XCTAssertGreaterThanOrEqual(r.oovWords, 1)
    }

    /// First-chunk latency of the ONNX route on the Mac simulator (reference only; the phone is
    /// measured by `first_audio` in ListenTiming): short first chunk (TextChunker .kokoroCPU).
    func testFirstChunkLatencyOnSimulator() async throws {
        try installHostAssets()
        let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"]!
        let model = URL(fileURLWithPath: home + "/Developer/tts-audition/bg-research/models/onnxcommunity-model_fp16.onnx")
        let pack = URL(fileURLWithPath: home + "/.cache/fluidaudio/Models/kokoro-82m-coreml/ANE/af_heart.bin")
        guard FileManager.default.fileExists(atPath: model.path), FileManager.default.fileExists(atPath: pack.path) else {
            throw XCTSkip("ONNX research model not present")
        }
        let para = "Adric ruffled Keo’s thick, black hair, which was harder to reach now that he was so tall. "
            + "“Maybe next cycle when you get Chosen. Then I’ll give you whatever weapon you want.”"
        let first = TextChunker.chunks(for: para, limits: .kokoroCPU)[0]
        let session = try KokoroONNXSession(modelURL: model, threads: 3)
        let packData = try Data(contentsOf: pack)
        var voice = [Float](repeating: 0, count: packData.count / 4)
        _ = voice.withUnsafeMutableBytes { packData.copyBytes(to: $0) }
        let frontend = try KokoroAneCPUFrontendHandle()
        _ = try await frontend.ids(for: "Warm up.") // lexicon + weights load (prepare)
        let t0 = Date()
        let (ids, count) = try await frontend.ids(for: first)
        let t1 = Date()
        let inputs = try KokoroCPUTensorBuilder.build(tokenIDs: ids, phonemeCount: count, voicePack: voice)
        let samples = try session.run(inputs)
        let t2 = Date()
        let audio = Double(samples.count) / 24_000
        print("FIRST_CHUNK chars=\(first.count) g2p_ms=\(Int(t1.timeIntervalSince(t0) * 1000)) onnx_ms=\(Int(t2.timeIntervalSince(t1) * 1000)) audio_s=\(String(format: "%.2f", audio))")
        XCTAssertGreaterThan(audio, 1)
    }
}
