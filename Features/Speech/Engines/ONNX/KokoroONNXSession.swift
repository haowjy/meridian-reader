import Foundation
import OnnxRuntimeBindings

/// Kokoro-82M through ONNX Runtime on the CPU execution provider (no Core ML EP, no GPU, no
/// ANE — nothing that is restricted in the background): Kokoro's main route (`KokoroCPUHost`).
/// The only file that imports ONNX Runtime. Model:
/// `onnx-community/Kokoro-82M-v1.0-ONNX/onnx/model_fp16.onnx`, downloaded at runtime by
/// `KokoroONNXModelStore` (never bundled).
///
/// Not thread-safe: one `run` at a time per session. Create the session on the queue whose QoS
/// the intra-op thread pool should inherit (ORT spawns its pool threads at session creation).
///
/// Memory: inputs vary in length (≈1.3 MB of activations per token), so ORT's CPU arena keeps
/// adding larger blocks, and on its own never gives them back (a 320-call stress run grows the
/// app from about 480 MB to 1.9 GB on an iPhone 17 Pro). Every run asks the arena to shrink when
/// it ends (`memory.enable_memory_arena_shrinkage`), which returns the blocks that run no longer
/// uses; the output buffers ORT hands back as autoreleased objects are released when `run`
/// returns (`autoreleasepool`), not whenever the calling GCD thread drains its pool.
final class KokoroONNXSession: @unchecked Sendable {
    private static let envLock = NSLock()
    private static var sharedEnv: ORTEnv?

    static var runtimeVersion: String { ORTVersion() ?? "?" }

    let threads: Int
    let allowSpinning: Bool
    private let session: ORTSession
    /// Every run's options: shrink the CPU arena when the run ends.
    private let runOptions: ORTRunOptions

    /// ORT's run option that frees the arena's unused blocks at the end of a run, and its value
    /// for the CPU arena (device 0).
    static let arenaShrinkageKey = "memory.enable_memory_arena_shrinkage"
    static let arenaShrinkageValue = "cpu:0"

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
        let runOptions = try ORTRunOptions()
        try runOptions.addConfigEntry(withKey: Self.arenaShrinkageKey, value: Self.arenaShrinkageValue)
        self.runOptions = runOptions
        self.threads = threads
        self.allowSpinning = allowSpinning
    }

    /// Run `body` synchronously on a global queue of `qos` and await the result. Create a session
    /// this way so ORT's pool (spawned at creation) inherits that QoS; run renders this way so the
    /// calling thread has the render's QoS.
    static func onQueue<T>(_ qos: DispatchQoS.QoSClass, _ body: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: qos).async {
                cont.resume(with: Result { try body() })
            }
        }
    }

    /// One synchronous render → 24 kHz mono float samples.
    func run(_ inputs: KokoroCPUInputs) throws -> [Float] {
        try autoreleasepool {
            let n = inputs.inputIDs.count
            let ids = inputs.inputIDs.withUnsafeBufferPointer { NSMutableData(bytes: $0.baseAddress, length: n * MemoryLayout<Int64>.size) }
            let style = inputs.style.withUnsafeBufferPointer { NSMutableData(bytes: $0.baseAddress, length: $0.count * MemoryLayout<Float>.size) }
            let speed = inputs.speed.withUnsafeBufferPointer { NSMutableData(bytes: $0.baseAddress, length: $0.count * MemoryLayout<Float>.size) }
            let feeds: [String: ORTValue] = [
                "input_ids": try ORTValue(tensorData: ids, elementType: .int64, shape: [1, NSNumber(value: n)]),
                "style": try ORTValue(tensorData: style, elementType: .float, shape: [1, NSNumber(value: inputs.style.count)]),
                "speed": try ORTValue(tensorData: speed, elementType: .float, shape: [NSNumber(value: inputs.speed.count)]),
            ]
            let out = try session.run(withInputs: feeds, outputNames: ["waveform"], runOptions: runOptions)
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
}
