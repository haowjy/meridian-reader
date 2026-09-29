import Foundation

// Kokoro-82M CPU route (ONNX Runtime; Kokoro's main route since 2026-09-24) — pure, engine-free
// pieces (unit-tested).
// See Features/Speech/CPURoute/CPURouteBench.swift and docs/LISTEN_PLAYBACK.md § CPU route benchmark.

/// Kokoro text frontend + assets for the CPU route, owned by the FluidAudio side
/// (`KokoroCPUHost`) so only FluidAudio files import FluidAudio. Phonemes, vocab and voice pack
/// are exactly the ones the Core ML route uses; nothing here touches Core ML.
protocol KokoroCPURouteFrontend: AnyObject, Sendable {
    /// Text → Kokoro IPA phoneme string (Misaki lexicon + pure-Swift BART G2P; no Core ML).
    func cpuRoutePhonemes(for text: String) async throws -> String
    /// Phoneme string → vocab ids **without** BOS/EOS (`vocab.json`; file-based, no Core ML).
    func cpuRouteTokenIDs(for phonemes: String) async throws -> [Int32]
    /// Flat 510×256 fp32 voice pack (`<voice>.bin`; file-based, no Core ML).
    func cpuRouteVoicePack(_ voice: String) async throws -> [Float]
}

/// The three ONNX inputs of `onnx-community/Kokoro-82M-v1.0-ONNX` (`input_ids` int64 [1, n],
/// `style` float [1, 256], `speed` float [1]); output `waveform` float [1, samples] at 24 kHz.
struct KokoroCPUInputs: Equatable, Sendable {
    /// `[0, ids…, 0]` (BOS/EOS pad = 0).
    var inputIDs: [Int64]
    /// Voice-pack row `styleRow` (256 floats: [0..<128] timbre, [128..<256] style_s = ONNX `ref_s`).
    var style: [Float]
    var speed: [Float]
    var styleRow: Int
    /// Phoneme-string length (Swift `Character`s) — what selects the style row.
    var phonemeCount: Int
    /// Ids between the pads (= inputIDs.count - 2).
    var tokenCount: Int { max(inputIDs.count - 2, 0) }
}

enum KokoroCPUTensorBuilder {
    static let styleDim = 256
    static let voicePackRows = 510
    /// Kokoro's per-call cap (FluidAudio `maxPhonemeLength`); ids + 2 pads ≤ 512.
    static let maxPhonemes = 510
    static let padID: Int64 = 0

    enum BuildError: LocalizedError, Equatable {
        case empty
        case tooLong(Int)
        case badVoicePack(Int)

        var errorDescription: String? {
            switch self {
            case .empty: return "No phoneme ids."
            case .tooLong(let n): return "\(n) phonemes exceeds Kokoro's \(KokoroCPUTensorBuilder.maxPhonemes) cap."
            case .badVoicePack(let n): return "Voice pack has \(n) floats, expected \(KokoroCPUTensorBuilder.voicePackRows * KokoroCPUTensorBuilder.styleDim)."
            }
        }
    }

    /// Same rule as FluidAudio / kokoro-onnx: `pack[len(phonemes) - 1]`, clamped to 0…509.
    static func styleRow(phonemeCount: Int) -> Int {
        min(max(phonemeCount - 1, 0), voicePackRows - 1)
    }

    /// - Parameters:
    ///   - tokenIDs: vocab ids WITHOUT BOS/EOS (they are added here as 0).
    ///   - phonemeCount: length of the phoneme string (can exceed `tokenIDs.count` when the vocab
    ///     drops unknown symbols; the style row follows the string length like FluidAudio).
    static func build(tokenIDs: [Int32], phonemeCount: Int, voicePack: [Float], speed: Float = 1.0) throws -> KokoroCPUInputs {
        guard !tokenIDs.isEmpty else { throw BuildError.empty }
        guard tokenIDs.count <= maxPhonemes, phonemeCount <= maxPhonemes else {
            throw BuildError.tooLong(max(tokenIDs.count, phonemeCount))
        }
        guard voicePack.count == voicePackRows * styleDim else { throw BuildError.badVoicePack(voicePack.count) }
        var ids: [Int64] = [padID]
        ids.reserveCapacity(tokenIDs.count + 2)
        ids.append(contentsOf: tokenIDs.map { Int64($0) })
        ids.append(padID)
        let row = styleRow(phonemeCount: phonemeCount)
        let style = Array(voicePack[(row * styleDim)..<((row + 1) * styleDim)])
        return KokoroCPUInputs(inputIDs: ids, style: style, speed: [speed], styleRow: row, phonemeCount: phonemeCount)
    }

    /// The Mac benchmark's short case: the first three ". "-separated sentences of the long
    /// phoneme string plus the closing ".", 190 phonemes for the fixed passage.
    static func shortCase(fromLongPhonemes long: String) -> String {
        long.components(separatedBy: ". ").prefix(3).joined(separator: ". ") + "."
    }
}

/// Fixed benchmark passage (the Mac ORT benchmark's input; 501 phonemes with FluidAudio's G2P).
enum KokoroCPUBenchText {
    static let long = "At first, people didn't like the rules. There were too many restrictions, not enough freedom. Some individuals would skip out on their tests, refusing to become part of the “New America”. President I. Ericcson-Sprucefeld said at a press conference, much lacking in actual press, that “the government has a very powerful weapon in its grasp that, if needed, would be unleashed on the entire population of the U.S.A., no matter how many people are involved.” This shut people up real fast."

    /// FluidAudio v0.16.1 phonemes of `long`, computed on the Mac (fallback only, used when
    /// the on-device phonemizer can't run; the result records `phonemes_source`).
    static let longPhonemesMac = "æt fˈɜɹst, pˈipᵊl dˈɪdᵊnt lˈIk ði ɹˈulz. ðɛɹ wɜɹ tˈu mˈɛni ɹəstɹˈɪkʃənz, nˌɑt ɪnˈʌf fɹˈidəm. sˌʌm ˌɪndəvˈɪʤəwəlz wʊd skˈɪp ˈWt ˌɔn ðɛɹ tˈɛsts, ɹəfjˈuzɪŋ tu bəkˈʌm pˈɑɹt ʌv ði“ nˈu əmˈɛɹəkə”. pɹˈɛzədˌɛnt ˈI. əɹˈɪksᵊn spɹˈusfˌɛld sˈɛd æt A pɹˈɛs kˈɑnfəɹəns, mˈʌʧ lˈækɪŋ ɪn ˈækʧəwəl pɹˈɛs, ðæt“ ði ɡˈʌvəɹnmənt hæz A vˈɛɹi pˈWəɹfᵊl wˈɛpən ɪn ɪts ɡɹˈæsp ðæt, ɪf nˈidᵻd, wʊd bi ʌnlˈiʃt ˌɔn ði əntˈIəɹ pˌɑpjəlˈAʃən ʌv ði jˈu ˈɛs ˈA., nˈO mˈæɾəɹ hˌW mˈɛni pˈipᵊl ɑɹ ɪnvˈɑlvd.” ðɪs ʃˈʌt pˈipᵊl ˌʌp ɹˈiᵊl fˈæst."
}

/// Audio helpers for the CPU route sample (unit-tested).
enum KokoroCPUAudio {
    static let sampleRate = 24_000
    /// ONNX output measured ≈3 dB louder than FluidAudio Core ML on the same passage
    /// (RMS 0.072 vs 0.050) → ×0.69 (≈ −3.2 dB) for an A/B at matched loudness.
    static let coreMLMatchGain: Float = 0.69

    static func allFinite(_ samples: [Float]) -> Bool {
        samples.allSatisfy { $0.isFinite }
    }

    static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Double = 0
        for s in samples { sum += Double(s) * Double(s) }
        return Float((sum / Double(samples.count)).squareRoot())
    }

    /// 16-bit PCM mono WAV, samples scaled by `gain` and clipped to ±1.
    static func wavData(_ samples: [Float], sampleRate: Int = sampleRate, gain: Float = 1) -> Data {
        var pcm = Data(capacity: samples.count * 2)
        for s in samples {
            let v = max(-1, min(1, s * gain))
            var i = Int16((v * 32767).rounded()).littleEndian
            withUnsafeBytes(of: &i) { pcm.append(contentsOf: $0) }
        }
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + pcm.count))
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1)
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(UInt32(pcm.count))
        d.append(pcm)
        return d
    }
}
