import Foundation

/// Reader local patch (2026-09-24): pure-Swift port of the English BART G2P
/// (`G2PEncoder.mlmodelc` + `G2PDecoder.mlmodelc`) so OOV words can be phonemized without
/// Core ML. `G2PModel` runs the same network through Core ML `.cpuOnly`, which on iOS 26.4+
/// goes through Espresso/BNNS — the library that SIGSEGVs in Reader's Kokoro crashes.
///
/// The network is tiny (1-layer post-LN BART, d_model 128, one attention head, FFN 1024,
/// vocab 63), so plain Float loops cost well under a millisecond per word. Weights are read
/// straight from the compiled bundles: `model.mil` names each const tensor with its shape and
/// `weights/weight.bin` offset; each offset points at a 64-byte MILBlob header
/// (0xDEADBEEF sentinel, dtype 1 = fp16, byte size, data offset).
/// Validated token-for-token against `G2PModel` (Core ML) in Reader's simulator tests.
final class KokoroSwiftG2P: @unchecked Sendable {

    enum LoadError: Error, LocalizedError {
        case missing(String)
        case badWeights(String)
        var errorDescription: String? {
            switch self {
            case .missing(let s): return "Swift G2P: missing \(s)"
            case .badWeights(let s): return "Swift G2P: bad weights (\(s))"
            }
        }
    }

    static let dModel = 128
    static let ffn = 1024
    static let maxSteps = 64
    static let maxInput = 64
    /// fp16 constants from the MIL graph.
    static let attnScale: Float = 0.08837890625  // 0x1.6ap-4
    static let lnEps: Float = 1.0013580322265625e-05  // 0x1.5p-17

    private struct Linear {
        let w: [Float]  // [out, in] row-major
        let b: [Float]
        let outDim: Int
        let inDim: Int

        func apply(_ x: [Float]) -> [Float] {
            var y = b
            w.withUnsafeBufferPointer { wp in
                x.withUnsafeBufferPointer { xp in
                    for o in 0..<outDim {
                        var acc: Float = 0
                        let row = o * inDim
                        for i in 0..<inDim { acc += wp[row + i] * xp[i] }
                        y[o] += acc
                    }
                }
            }
            return y
        }
    }

    private struct LayerNorm {
        let g: [Float]
        let b: [Float]
        func apply(_ x: [Float]) -> [Float] {
            let n = Float(x.count)
            var mean: Float = 0
            for v in x { mean += v }
            mean /= n
            var varSum: Float = 0
            for v in x { varSum += (v - mean) * (v - mean) }
            let inv = 1 / (varSum / n + KokoroSwiftG2P.lnEps).squareRoot()
            var y = [Float](repeating: 0, count: x.count)
            for i in 0..<x.count { y[i] = (x[i] - mean) * inv * g[i] + b[i] }
            return y
        }
    }

    private struct Block {
        let q, k, v, out: Linear
        let attnNorm: LayerNorm
    }

    // Encoder
    private let encEmbed: [Float]  // [63,128]
    private let encPos: [Float]  // [66,128]
    private let encEmbNorm: LayerNorm
    private let encAttn: Block
    private let encFc1, encFc2: Linear
    private let encFinal: LayerNorm
    // Decoder
    private let decEmbed: [Float]
    private let decPos: [Float]
    private let decEmbNorm: LayerNorm
    private let decSelf: Block
    private let decCross: Block
    private let decFc1, decFc2: Linear
    private let decFinal: LayerNorm
    private let logitsBias: [Float]
    private let vocabSize: Int

    let graphemeToId: [Character: Int]
    let idToPhoneme: [Int: String]
    let bos: Int
    let eos: Int
    let unk: Int

    /// `kokoroDirectory` = `<models>/kokoro` holding `G2PEncoder.mlmodelc`,
    /// `G2PDecoder.mlmodelc`, `g2p_vocab.json`.
    init(kokoroDirectory: URL) throws {
        let enc = try Self.loadTensors(kokoroDirectory.appendingPathComponent(ModelNames.G2P.encoderFile))
        let dec = try Self.loadTensors(kokoroDirectory.appendingPathComponent(ModelNames.G2P.decoderFile))
        func t(_ m: [String: ([Int], [Float])], _ name: String) throws -> ([Int], [Float]) {
            guard let v = m[name] else { throw LoadError.missing(name) }
            return v
        }
        func lin(_ m: [String: ([Int], [Float])], _ w: String, _ b: String) throws -> Linear {
            let (ws, wv) = try t(m, w)
            let (_, bv) = try t(m, b)
            guard ws.count == 2, wv.count == ws[0] * ws[1], bv.count == ws[0] else {
                throw LoadError.badWeights(w)
            }
            return Linear(w: wv, b: bv, outDim: ws[0], inDim: ws[1])
        }
        func ln(_ m: [String: ([Int], [Float])], _ g: String, _ b: String) throws -> LayerNorm {
            LayerNorm(g: try t(m, g).1, b: try t(m, b).1)
        }

        encEmbed = try t(enc, "encoder_embed_tokens_weight").1
        encPos = try t(enc, "encoder_embed_positions_weight").1
        encEmbNorm = try ln(enc, "encoder_layernorm_embedding_weight", "encoder_layernorm_embedding_bias")
        let e = "encoder_layers_0_"
        encAttn = Block(
            q: try lin(enc, e + "self_attn_q_proj_weight", e + "self_attn_q_proj_bias"),
            k: try lin(enc, e + "self_attn_k_proj_weight", e + "self_attn_k_proj_bias"),
            v: try lin(enc, e + "self_attn_v_proj_weight", e + "self_attn_v_proj_bias"),
            out: try lin(enc, e + "self_attn_out_proj_weight", e + "self_attn_out_proj_bias"),
            attnNorm: try ln(enc, e + "self_attn_layer_norm_weight", e + "self_attn_layer_norm_bias"))
        encFc1 = try lin(enc, e + "fc1_weight", e + "fc1_bias")
        encFc2 = try lin(enc, e + "fc2_weight", e + "fc2_bias")
        encFinal = try ln(enc, e + "final_layer_norm_weight", e + "final_layer_norm_bias")

        let (embShape, emb) = try t(dec, "embed_tokens_weight")
        decEmbed = emb
        vocabSize = embShape[0]
        decPos = try t(dec, "embed_positions_weight").1
        decEmbNorm = try ln(dec, "layernorm_embedding_weight", "layernorm_embedding_bias")
        decSelf = Block(
            q: try lin(dec, "self_attn_q_weight", "self_attn_q_bias"),
            k: try lin(dec, "self_attn_k_weight", "self_attn_k_bias"),
            v: try lin(dec, "self_attn_v_weight", "self_attn_v_bias"),
            out: try lin(dec, "self_attn_out_weight", "self_attn_out_bias"),
            attnNorm: try ln(dec, "self_attn_norm_weight", "self_attn_norm_bias"))
        decCross = Block(
            q: try lin(dec, "cross_attn_q_weight", "cross_attn_q_bias"),
            k: try lin(dec, "cross_attn_k_weight", "cross_attn_k_bias"),
            v: try lin(dec, "cross_attn_v_weight", "cross_attn_v_bias"),
            out: try lin(dec, "cross_attn_out_weight", "cross_attn_out_bias"),
            attnNorm: try ln(dec, "cross_attn_norm_weight", "cross_attn_norm_bias"))
        decFc1 = try lin(dec, "fc1_weight", "fc1_bias")
        decFc2 = try lin(dec, "fc2_weight", "fc2_bias")
        decFinal = try ln(dec, "final_layer_norm_weight", "final_layer_norm_bias")
        logitsBias = try t(dec, "linear_10_bias_0").1
        guard logitsBias.count == vocabSize, encEmbed.count == vocabSize * Self.dModel else {
            throw LoadError.badWeights("vocab size")
        }

        // Vocab (same parsing as G2PModel).
        let vocabURL = kokoroDirectory.appendingPathComponent(ModelNames.G2P.vocabularyFile)
        guard let data = try? Data(contentsOf: vocabURL),
            let vocab = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let g2id = vocab["grapheme_to_id"] as? [String: Int],
            let id2ph = vocab["id_to_phoneme"] as? [String: String]
        else { throw LoadError.missing(ModelNames.G2P.vocabularyFile) }
        var gMap: [Character: Int] = [:]
        for (k, v) in g2id where k.count == 1 { gMap[k.first!] = v }
        var pMap: [Int: String] = [:]
        for (k, v) in id2ph { if let i = Int(k) { pMap[i] = v } }
        graphemeToId = gMap
        idToPhoneme = pMap
        bos = vocab["bos_token_id"] as? Int ?? 1
        eos = vocab["eos_token_id"] as? Int ?? 2
        unk = vocab["unk_token_id"] as? Int ?? 3
    }

    /// Same contract as `G2PModel.phonemize(word:)`: phoneme tokens, or nil if empty.
    func phonemize(word: String) -> [String]? {
        let ids = decodeIDs(word: word)
        let special: Set<Int> = [0, bos, eos, unk]
        let phonemes = ids.filter { !special.contains($0) }.compactMap { idToPhoneme[$0] }
        return phonemes.isEmpty ? nil : phonemes
    }

    /// Greedy decode; returns decoder ids including the leading BOS (like G2PModel).
    func decodeIDs(word: String) -> [Int] {
        var input: [Int] = [bos]
        for ch in word { input.append(graphemeToId[ch] ?? unk) }
        input.append(eos)
        // Position table has 66 rows (positions 0..63 + BART offset 2).
        if input.count > Self.maxInput { input = Array(input.prefix(Self.maxInput - 1)) + [eos] }
        let d = Self.dModel

        // ---- Encoder ----
        var h: [[Float]] = input.enumerated().map { (i, id) in
            var x = [Float](repeating: 0, count: d)
            let tok = min(max(id, 0), vocabSize - 1) * d
            let pos = (i + 2) * d
            for j in 0..<d { x[j] = encEmbed[tok + j] + encPos[pos + j] }
            return encEmbNorm.apply(x)
        }
        let eq = h.map { encAttn.q.apply($0) }
        let ek = h.map { encAttn.k.apply($0) }
        let ev = h.map { encAttn.v.apply($0) }
        h = h.indices.map { i in
            let o = encAttn.out.apply(Self.attend(q: eq[i], keys: ek, values: ev, upTo: ek.count))
            return encAttn.attnNorm.apply(Self.add(h[i], o))
        }
        let encOut: [[Float]] = h.map { x in
            let f = encFc2.apply(Self.gelu(encFc1.apply(x)))
            return encFinal.apply(Self.add(x, f))
        }
        let crossK = encOut.map { decCross.k.apply($0) }
        let crossV = encOut.map { decCross.v.apply($0) }

        // ---- Decoder (incremental; causal single layer => earlier states never change) ----
        var ids: [Int] = [bos]
        var selfK: [[Float]] = []
        var selfV: [[Float]] = []
        for step in 0..<Self.maxSteps {
            let tok = min(max(ids[step], 0), vocabSize - 1) * d
            let pos = min(step + 2, 65) * d
            var x = [Float](repeating: 0, count: d)
            for j in 0..<d { x[j] = decEmbed[tok + j] + decPos[pos + j] }
            x = decEmbNorm.apply(x)
            selfK.append(decSelf.k.apply(x))
            selfV.append(decSelf.v.apply(x))
            let sa = decSelf.out.apply(Self.attend(q: decSelf.q.apply(x), keys: selfK, values: selfV, upTo: selfK.count))
            x = decSelf.attnNorm.apply(Self.add(x, sa))
            let ca = decCross.out.apply(Self.attend(q: decCross.q.apply(x), keys: crossK, values: crossV, upTo: crossK.count))
            x = decCross.attnNorm.apply(Self.add(x, ca))
            let f = decFc2.apply(Self.gelu(decFc1.apply(x)))
            x = decFinal.apply(Self.add(x, f))
            // logits = embed_tokens · x + bias; argmax (first max wins, like G2PModel).
            var best = 0
            var bestVal = -Float.infinity
            for v in 0..<vocabSize {
                var acc = logitsBias[v]
                let row = v * d
                for j in 0..<d { acc += decEmbed[row + j] * x[j] }
                if acc > bestVal { bestVal = acc; best = v }
            }
            if best == eos { break }
            ids.append(best)
        }
        return ids
    }

    // MARK: - Math

    private static func add(_ a: [Float], _ b: [Float]) -> [Float] {
        var y = a
        for i in 0..<y.count { y[i] += b[i] }
        return y
    }

    private static func gelu(_ x: [Float]) -> [Float] {
        x.map { 0.5 * $0 * (1 + Float(erf(Double($0) / 2.0.squareRoot()))) }
    }

    private static func attend(q: [Float], keys: [[Float]], values: [[Float]], upTo n: Int) -> [Float] {
        let d = q.count
        var scores = [Float](repeating: 0, count: n)
        var maxS = -Float.infinity
        for t in 0..<n {
            var acc: Float = 0
            let k = keys[t]
            for j in 0..<d { acc += q[j] * k[j] }
            scores[t] = acc * attnScale
            maxS = max(maxS, scores[t])
        }
        var sum: Float = 0
        for t in 0..<n {
            scores[t] = expf(scores[t] - maxS)
            sum += scores[t]
        }
        var out = [Float](repeating: 0, count: d)
        for t in 0..<n {
            let w = scores[t] / sum
            let v = values[t]
            for j in 0..<d { out[j] += w * v[j] }
        }
        return out
    }

    // MARK: - Weight loading

    /// name (minus `_to_fp16`) → (shape, values) for every fp16 BLOBFILE const in `model.mil`.
    static func loadTensors(_ bundle: URL) throws -> [String: ([Int], [Float])] {
        let milURL = bundle.appendingPathComponent("model.mil")
        let binURL = bundle.appendingPathComponent("weights/weight.bin")
        guard let mil = try? String(contentsOf: milURL, encoding: .utf8) else {
            throw LoadError.missing(milURL.lastPathComponent)
        }
        guard let bin = try? Data(contentsOf: binURL, options: .mappedIfSafe) else {
            throw LoadError.missing("weight.bin")
        }
        let pattern =
            #"tensor<fp16, \[([0-9, ]+)\]> ([A-Za-z0-9_]+) = const\(\).*?BLOBFILE\(path = tensor<string, \[\]>\("@model_path/weights/weight\.bin"\), offset = tensor<uint64, \[\]>\(([0-9]+)\)\)"#
        let regex = try NSRegularExpression(pattern: pattern)
        var out: [String: ([Int], [Float])] = [:]
        let ns = mil as NSString
        for m in regex.matches(in: mil, range: NSRange(location: 0, length: ns.length)) {
            let shape = ns.substring(with: m.range(at: 1)).split(separator: ",").compactMap {
                Int($0.trimmingCharacters(in: .whitespaces))
            }
            var name = ns.substring(with: m.range(at: 2))
            if name.hasSuffix("_to_fp16") { name = String(name.dropLast("_to_fp16".count)) }
            guard let offset = Int(ns.substring(with: m.range(at: 3))) else { continue }
            out[name] = (shape, try readFP16Blob(bin, headerOffset: offset, count: shape.reduce(1, *), name: name))
        }
        guard !out.isEmpty else { throw LoadError.badWeights("no tensors in \(bundle.lastPathComponent)") }
        return out
    }

    private static func readFP16Blob(_ data: Data, headerOffset: Int, count: Int, name: String) throws -> [Float] {
        func u32(_ o: Int) -> UInt32 {
            data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt32.self) }
        }
        func u64(_ o: Int) -> UInt64 {
            data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt64.self) }
        }
        guard headerOffset + 24 <= data.count, u32(headerOffset) == 0xDEAD_BEEF else {
            throw LoadError.badWeights("\(name): no blob header")
        }
        let dtype = u32(headerOffset + 4)
        let size = Int(u64(headerOffset + 8))
        let dataOffset = Int(u64(headerOffset + 16))
        guard dtype == 1, size == count * 2, dataOffset + size <= data.count else {
            throw LoadError.badWeights("\(name): dtype \(dtype) size \(size) count \(count)")
        }
        var values = [Float](repeating: 0, count: count)
        data.withUnsafeBytes { raw in
            for i in 0..<count {
                values[i] = halfToFloat(raw.loadUnaligned(fromByteOffset: dataOffset + i * 2, as: UInt16.self))
            }
        }
        return values
    }

    static func halfToFloat(_ h: UInt16) -> Float {
        let sign = UInt32(h >> 15) << 31
        let exp = Int((h >> 10) & 0x1F)
        let mant = UInt32(h & 0x3FF)
        if exp == 0 {
            if mant == 0 { return Float(bitPattern: sign) }
            // subnormal
            let v = Float(mant) / 1024.0 * powf(2, -14)
            return sign != 0 ? -v : v
        }
        if exp == 31 {
            return Float(bitPattern: sign | 0x7F80_0000 | (mant << 13))
        }
        return Float(bitPattern: sign | UInt32(exp - 15 + 127) << 23 | (mant << 13))
    }
}
