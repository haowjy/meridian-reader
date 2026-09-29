import Foundation
import OnnxRuntimeBindings

/// Debug-only: Kokoro-82M through ONNX Runtime on the CPU execution provider (no Core ML EP,
/// no GPU, no ANE — nothing that is restricted in the background). The only file that imports
/// ONNX Runtime. Model: `onnx-community/Kokoro-82M-v1.0-ONNX/onnx/model_fp16.onnx`, downloaded
/// at runtime by `CPURouteModelStore` (never bundled).
///
/// Not thread-safe: one `run` at a time per session. Create the session on the queue whose QoS
/// the intra-op thread pool should inherit (ORT spawns its pool threads at session creation).
final class KokoroONNXSession: @unchecked Sendable {
    private static let envLock = NSLock()
    private static var sharedEnv: ORTEnv?

    static var runtimeVersion: String { ORTVersion() ?? "?" }

    let threads: Int
    let allowSpinning: Bool
    private let session: ORTSession

    init(modelURL: URL, threads: Int, allowSpinning: Bool = true) throws {
        let env: ORTEnv = try Self.envLock.withLock {
            if let e = Self.sharedEnv { return e }
            let e = try ORTEnv(loggingLevel: .warning)
            Self.sharedEnv = e
            return e
        }
        let opts = try ORTSessionOptions()
        try opts.setIntraOpNumThreads(Int32(threads))
        try opts.setGraphOptimizationLevel(.all)
        if !allowSpinning {
            try opts.addConfigEntry(withKey: "session.intra_op.allow_spinning", value: "0")
            try opts.addConfigEntry(withKey: "session.inter_op.allow_spinning", value: "0")
        }
        self.session = try ORTSession(env: env, modelPath: modelURL.path, sessionOptions: opts)
        self.threads = threads
        self.allowSpinning = allowSpinning
    }

    /// One synchronous render → 24 kHz mono float samples.
    func run(_ inputs: KokoroCPUInputs) throws -> [Float] {
        let n = inputs.inputIDs.count
        let ids = inputs.inputIDs.withUnsafeBufferPointer { NSMutableData(bytes: $0.baseAddress, length: n * MemoryLayout<Int64>.size) }
        let style = inputs.style.withUnsafeBufferPointer { NSMutableData(bytes: $0.baseAddress, length: $0.count * MemoryLayout<Float>.size) }
        let speed = inputs.speed.withUnsafeBufferPointer { NSMutableData(bytes: $0.baseAddress, length: $0.count * MemoryLayout<Float>.size) }
        let feeds: [String: ORTValue] = [
            "input_ids": try ORTValue(tensorData: ids, elementType: .int64, shape: [1, NSNumber(value: n)]),
            "style": try ORTValue(tensorData: style, elementType: .float, shape: [1, NSNumber(value: inputs.style.count)]),
            "speed": try ORTValue(tensorData: speed, elementType: .float, shape: [NSNumber(value: inputs.speed.count)]),
        ]
        let out = try session.run(withInputs: feeds, outputNames: ["waveform"], runOptions: nil)
        guard let wave = out["waveform"] else {
            throw LocalSynthError.engineUnavailable("ONNX output 'waveform' missing")
        }
        let data = try wave.tensorData() as Data
        let count = data.count / MemoryLayout<Float>.size
        var samples = [Float](repeating: 0, count: count)
        _ = samples.withUnsafeMutableBytes { data.copyBytes(to: $0) }
        return samples
    }
}
