import XCTest
@testable import Reader

/// End-to-end ONNX Runtime check against the Mac Python reference (onnxruntime 1.2x, same fp16
/// model, same phonemes/vocab/af_heart row 500): 657000 samples, RMS ≈ 0.0722.
/// Simulator-only and skipped unless the Mac research assets exist under `SIMULATOR_HOST_HOME`:
/// `Developer/tts-audition/bg-research/models/onnxcommunity-model_fp16.onnx` and FluidAudio's
/// `.cache/fluidaudio/Models/kokoro-82m-coreml/ANE/{vocab.json, af_heart.bin}`.
final class KokoroONNXSessionTests: XCTestCase {
    func testMatchesMacReferenceRender() throws {
        guard let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] else {
            throw XCTSkip("Simulator-only (needs host assets)")
        }
        let model = URL(fileURLWithPath: home + "/Developer/tts-audition/bg-research/models/onnxcommunity-model_fp16.onnx")
        let ane = URL(fileURLWithPath: home + "/.cache/fluidaudio/Models/kokoro-82m-coreml/ANE")
        let fm = FileManager.default
        guard fm.fileExists(atPath: model.path),
              fm.fileExists(atPath: ane.appendingPathComponent("vocab.json").path),
              fm.fileExists(atPath: ane.appendingPathComponent("af_heart.bin").path) else {
            throw XCTSkip("Mac research assets not present")
        }
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: ane.appendingPathComponent("vocab.json"))) as! [String: Any]
        var vocab: [Character: Int32] = [:]
        for (k, v) in json { if k.count == 1, let i = v as? Int { vocab[k.first!] = Int32(i) } }
        let phonemes = KokoroCPUBenchText.longPhonemesMac
        let ids = phonemes.compactMap { vocab[$0] }
        let packData = try Data(contentsOf: ane.appendingPathComponent("af_heart.bin"))
        var pack = [Float](repeating: 0, count: packData.count / 4)
        _ = pack.withUnsafeMutableBytes { packData.copyBytes(to: $0) }

        let inputs = try KokoroCPUTensorBuilder.build(tokenIDs: ids, phonemeCount: phonemes.count, voicePack: pack)
        XCTAssertEqual(inputs.inputIDs.count, 503)
        XCTAssertEqual(inputs.styleRow, 500)
        let session = try KokoroONNXSession(modelURL: model, threads: 4)
        let samples = try session.run(inputs)
        XCTAssertEqual(samples.count, 657_000)
        XCTAssertEqual(KokoroCPUAudio.rms(samples), 0.0722, accuracy: 0.0722 * 0.03)
    }
}
