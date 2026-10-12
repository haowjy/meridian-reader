import XCTest
@testable import MeridianReader

/// Measures ONNX Runtime render speed (× real time) across intra-op thread counts and spinning,
/// on the Mac's CPU through the Simulator: the same ORT build and fp16 model as the app. A proxy
/// for the phone only (the M3 has 4 performance cores, the A19 Pro 2): the device numbers come
/// from the timing log and the CPU route benchmark.
///
/// Skipped unless `TEST_RUNNER_READER_ONNX_SWEEP=1` is in xcodebuild's environment and the Mac
/// research assets `KokoroONNXSessionTests` uses exist. Prints one line per configuration
/// (`onnx_sweep threads=… spin=… x120=… x500=…`, × real time for a typical chunk and a long one,
/// best of the rounds). `TEST_RUNNER_READER_ONNX_SWEEP_CONFIGS="3:0,5:0"` (threads:spinning) and
/// `TEST_RUNNER_READER_ONNX_SWEEP_ROUNDS=4` change what runs.
final class KokoroONNXThreadSweepTests: XCTestCase {
    func testThreadSweep() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["READER_ONNX_SWEEP"] == "1" else { throw XCTSkip("Set TEST_RUNNER_READER_ONNX_SWEEP=1") }
        guard let home = env["SIMULATOR_HOST_HOME"] else { throw XCTSkip("Simulator-only (needs host assets)") }
        let model = URL(fileURLWithPath: home + "/Developer/tts-audition/bg-research/models/onnxcommunity-model_fp16.onnx")
        let ane = URL(fileURLWithPath: home + "/.cache/fluidaudio/Models/kokoro-82m-coreml/ANE")
        guard FileManager.default.fileExists(atPath: model.path) else { throw XCTSkip("Mac research model not present") }

        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: ane.appendingPathComponent("vocab.json"))) as! [String: Any]
        var vocab: [Character: Int32] = [:]
        for (k, v) in json { if k.count == 1, let i = v as? Int { vocab[k.first!] = Int32(i) } }
        let packData = try Data(contentsOf: ane.appendingPathComponent("af_heart.bin"))
        var pack = [Float](repeating: 0, count: packData.count / 4)
        _ = pack.withUnsafeMutableBytes { packData.copyBytes(to: $0) }
        let phonemes = KokoroCPUBenchText.longPhonemesMac
        // A typical chunk (the app's chunks run 60–220 tokens) and the long passage.
        let typical = String(phonemes.prefix(120))
        func inputs(_ p: String) throws -> KokoroCPUInputs {
            try KokoroCPUTensorBuilder.build(tokenIDs: p.compactMap { vocab[$0] }, phonemeCount: p.count, voicePack: pack)
        }
        let cases = [("120", try inputs(typical)), ("500", try inputs(phonemes))]
        // "threads:spin" pairs, rendered round-robin so a busy Mac slows every config alike.
        let configs: [(threads: Int, spin: Bool)] = (env["READER_ONNX_SWEEP_CONFIGS"] ?? "2:0,3:0,3:1,4:0,4:1,6:0")
            .split(separator: ",").compactMap { pair in
                let parts = pair.split(separator: ":").compactMap { Int($0) }
                return parts.count == 2 ? (parts[0], parts[1] == 1) : nil
            }
        let rounds = Int(env["READER_ONNX_SWEEP_ROUNDS"] ?? "") ?? 4
        var sessions: [KokoroONNXSession] = []
        for config in configs {
            let session = try await KokoroONNXSession.onQueue(.userInitiated) {
                try KokoroONNXSession(modelURL: model, threads: config.threads, allowSpinning: config.spin)
            }
            for (_, input) in cases { _ = try await KokoroONNXSession.onQueue(.userInitiated) { try session.run(input) } }
            sessions.append(session)
        }
        var best = Array(repeating: Array(repeating: Double.infinity, count: cases.count), count: configs.count)
        var cpu = best
        var audio = Array(repeating: 0.0, count: cases.count)
        for _ in 0..<rounds {
            for (i, session) in sessions.enumerated() {
                for (j, (_, input)) in cases.enumerated() {
                    let (wall, seconds, used) = try await KokoroONNXSession.onQueue(.userInitiated) {
                        let c0 = ProcessCPUTime.seconds
                        let t0 = CFAbsoluteTimeGetCurrent()
                        let samples = try session.run(input)
                        return (CFAbsoluteTimeGetCurrent() - t0, Double(samples.count) / 24_000, ProcessCPUTime.seconds - c0)
                    }
                    if wall < best[i][j] { best[i][j] = wall; cpu[i][j] = used }
                    audio[j] = seconds
                }
            }
        }
        for (i, config) in configs.enumerated() {
            var line = "onnx_sweep threads=\(config.threads) spin=\(config.spin ? 1 : 0)"
            for (j, (label, _)) in cases.enumerated() {
                line += String(format: " x%@=%.2f cpu%@=%.2f", label, audio[j] / best[i][j], label, cpu[i][j] / audio[j])
            }
            print(line)
        }
    }
}
