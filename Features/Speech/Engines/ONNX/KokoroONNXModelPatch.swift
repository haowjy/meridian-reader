import Foundation

/// Fixes a NaN bug in the onnx-community Kokoro-82M `model_fp16.onnx` by editing the model file
/// (protobuf), once, on device.
///
/// Root cause (diagnosed 2026-09-25 from The Forgotten on Jimmy's phone: 14 chunks ≈ 16 % of the
/// rendered audio came out as NaN → written as full-scale DC = a pop, silence, a pop): the
/// generator's harmonic-source STFT phase is exported as `atan2(im, re)` = `Atan(Div(im, re))` plus
/// `Where` quadrant fixes. In fp16, bins where both `re` and `im` round to exactly 0 give
/// `0/0 = NaN`; the NaN flows into `noise_convs` → AdaIN (a mean over the whole time axis), so the
/// entire chunk becomes NaN. Whether an exact 0/0 happens depends on kernel rounding (thread
/// count, ORT version, CPU), which is why it looked random. (`±x/0 = ±inf` is fine: atan → ±π/2.)
///
/// Patch: every `Atan` input `x` gets `Where(IsNaN(x), 0, x)` in front of it, i.e. PyTorch's
/// `atan2(0, 0) = 0`. Only NaN elements change, so all other audio is bit-identical.
enum KokoroONNXModelPatch {
    enum PatchError: LocalizedError {
        case malformed(String)
        case nothingToPatch
        var errorDescription: String? {
            switch self {
            case .malformed(let s): return "ONNX patch: malformed model (\(s))"
            case .nothingToPatch: return "ONNX patch: no Atan node found"
            }
        }
    }

    static let suffix = "_atan2nanfix"

    /// Patched model bytes and how many `Atan` nodes were guarded. Reads `model` in place (use a
    /// memory-mapped `Data`); the output is built once (≈ model size).
    static func patch(_ model: Data) throws -> (data: Data, guarded: Int) {
        try model.withUnsafeBytes { raw -> (Data, Int) in
            let b = raw.bindMemory(to: UInt8.self)
            // Pass 1: locate the graph and the Atan nodes inside it.
            var graphTagRange: Range<Int>?
            var graphBody: Range<Int>?
            var pos = 0
            while pos < b.count {
                let (tag, afterTag) = try varint(b, pos)
                let end = try skip(b, afterTag, wire: Int(tag & 7))
                if tag >> 3 == 7, tag & 7 == 2 {
                    let (len, s) = try varint(b, afterTag)
                    graphTagRange = pos..<afterTag
                    graphBody = s..<(s + Int(len))
                }
                pos = end
            }
            guard let graphTagRange, let graphBody else { throw PatchError.malformed("no graph") }
            // (node field range, replacement bytes incl. field headers)
            var edits: [(Range<Int>, [UInt8])] = []
            pos = graphBody.lowerBound
            while pos < graphBody.upperBound {
                let (tag, afterTag) = try varint(b, pos)
                let end = try skip(b, afterTag, wire: Int(tag & 7))
                if tag == 0x0A {
                    let (len, s) = try varint(b, afterTag)
                    let node = Array(b[s..<(s + Int(len))])
                    if let replacement = try guardedAtan(node) { edits.append((pos..<end, replacement)) }
                }
                pos = end
            }
            guard !edits.isEmpty else { throw PatchError.nothingToPatch }
            let delta = edits.reduce(0) { $0 + $1.1.count - $1.0.count }
            let newGraphLen = graphBody.count + delta
            // Pass 2: write.
            var out = Data()
            out.reserveCapacity(b.count + delta + 16)
            func copy(_ r: Range<Int>) {
                guard !r.isEmpty else { return }
                out.append(UnsafeBufferPointer(rebasing: b[r]))
            }
            copy(0..<graphTagRange.lowerBound)
            out.append(contentsOf: [UInt8(0x3A)])
            out.append(contentsOf: encodeVarint(UInt64(newGraphLen)))
            var cursor = graphBody.lowerBound
            for (range, bytes) in edits {
                copy(cursor..<range.lowerBound)
                out.append(contentsOf: bytes)
                cursor = range.upperBound
            }
            copy(cursor..<graphBody.upperBound)
            copy(graphBody.upperBound..<b.count)
            return (out, edits.count)
        }
    }

    /// For an `Atan` node: the guard nodes + the rewritten Atan (each with its GraphProto.node
    /// header). nil for any other node.
    private static func guardedAtan(_ node: [UInt8]) throws -> [UInt8]? {
        let info = try parseNode(node)
        guard info.opType == "Atan", info.domain.isEmpty, info.inputs.count == 1 else { return nil }
        let x = info.inputs[0]
        let fixed = x + suffix
        let zero = fixed + "_zero", isNaN = fixed + "_isnan"
        let prefix = (info.name.isEmpty ? x : info.name) + suffix
        var out = [UInt8]()
        for extra in [
            constantFP16Zero(output: zero, name: prefix + "_Zero"),
            simpleNode(op: "IsNaN", inputs: [x], output: isNaN, name: prefix + "_IsNaN"),
            simpleNode(op: "Where", inputs: [isNaN, zero, x], output: fixed, name: prefix + "_Where"),
            try replaceFirstInput(node, with: fixed),
        ] {
            out += bytesField(1, extra)
        }
        return out
    }

    private struct NodeInfo { var inputs: [String] = []; var name = ""; var opType = ""; var domain = "" }

    private static func parseNode(_ n: [UInt8]) throws -> NodeInfo {
        var info = NodeInfo()
        var pos = 0
        while pos < n.count {
            let (tag, afterTag) = try varint(n, pos)
            let field = tag >> 3, wire = tag & 7
            let end = try skip(n, afterTag, wire: Int(wire))
            if wire == 2, [1, 3, 4, 7].contains(field) {
                let (len, s) = try varint(n, afterTag)
                let str = String(decoding: n[s..<(s + Int(len))], as: UTF8.self)
                switch field {
                case 1: info.inputs.append(str)
                case 3: info.name = str
                case 4: info.opType = str
                default: info.domain = str
                }
            }
            pos = end
        }
        return info
    }

    private static func replaceFirstInput(_ n: [UInt8], with name: String) throws -> [UInt8] {
        var out = [UInt8]()
        var pos = 0
        var done = false
        while pos < n.count {
            let start = pos
            let (tag, afterTag) = try varint(n, pos)
            let end = try skip(n, afterTag, wire: Int(tag & 7))
            if !done, tag == 0x0A {
                out.append(contentsOf: stringField(1, name))
                done = true
            } else {
                out.append(contentsOf: n[start..<end])
            }
            pos = end
        }
        return out
    }

    // MARK: - Node builders

    private static func simpleNode(op: String, inputs: [String], output: String, name: String) -> [UInt8] {
        var b = [UInt8]()
        for i in inputs { b += stringField(1, i) }
        b += stringField(2, output)
        b += stringField(3, name)
        b += stringField(4, op)
        return b
    }

    /// `Constant` with a float16 scalar 0 (TensorProto data_type 10, raw_data 0x0000).
    private static func constantFP16Zero(output: String, name: String) -> [UInt8] {
        var tensor = [UInt8]()
        tensor += [0x10, 10]                        // data_type = FLOAT16
        tensor += bytesField(9, [0, 0])             // raw_data
        var attr = [UInt8]()
        attr += stringField(1, "value")             // name
        attr += bytesField(5, tensor)               // t
        attr += [0xA0, 0x01, 4]                     // type (field 20, varint) = TENSOR
        var b = [UInt8]()
        b += stringField(2, output)
        b += stringField(3, name)
        b += stringField(4, "Constant")
        b += bytesField(5, attr)
        return b
    }

    private static func stringField(_ field: UInt64, _ s: String) -> [UInt8] { bytesField(field, Array(s.utf8)) }

    private static func bytesField(_ field: UInt64, _ v: [UInt8]) -> [UInt8] {
        encodeVarint(field << 3 | 2) + encodeVarint(UInt64(v.count)) + v
    }

    // MARK: - Protobuf wire helpers

    static func encodeVarint(_ value: UInt64) -> [UInt8] {
        var v = value
        var out = [UInt8]()
        repeat {
            var byte = UInt8(v & 0x7F)
            v >>= 7
            if v != 0 { byte |= 0x80 }
            out.append(byte)
        } while v != 0
        return out
    }

    private static func varint<C: RandomAccessCollection>(_ b: C, _ start: Int) throws -> (UInt64, Int)
        where C.Element == UInt8, C.Index == Int {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var i = start
        while i < b.endIndex {
            let byte = b[i]
            result |= UInt64(byte & 0x7F) << shift
            i += 1
            if byte & 0x80 == 0 { return (result, i) }
            shift += 7
            if shift > 63 { break }
        }
        throw PatchError.malformed("varint at \(start)")
    }

    private static func skip<C: RandomAccessCollection>(_ b: C, _ pos: Int, wire: Int) throws -> Int
        where C.Element == UInt8, C.Index == Int {
        switch wire {
        case 0: return try varint(b, pos).1
        case 1: guard pos + 8 <= b.endIndex else { throw PatchError.malformed("fixed64") }; return pos + 8
        case 2:
            let (len, s) = try varint(b, pos)
            guard s + Int(len) <= b.endIndex else { throw PatchError.malformed("length at \(pos)") }
            return s + Int(len)
        case 5: guard pos + 4 <= b.endIndex else { throw PatchError.malformed("fixed32") }; return pos + 4
        default: throw PatchError.malformed("wire type \(wire) at \(pos)")
        }
    }

    // MARK: - Files

    /// Patched sibling of `original` (`model_fp16.onnx` → `model_fp16_atan2nanfix.onnx`).
    static func patchedURL(for original: URL) -> URL {
        original.deletingLastPathComponent()
            .appendingPathComponent(original.deletingPathExtension().lastPathComponent + suffix + ".onnx")
    }

    /// Writes the patched model next to `original` (atomic) and returns its URL.
    static func writePatched(from original: URL) throws -> (url: URL, guarded: Int) {
        let data = try Data(contentsOf: original, options: .alwaysMapped)
        let (patched, n) = try patch(data)
        let dst = patchedURL(for: original)
        try patched.write(to: dst, options: .atomic)
        return (dst, n)
    }
}
