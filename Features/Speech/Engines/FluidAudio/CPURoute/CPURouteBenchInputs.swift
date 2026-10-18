#if DEBUG
import Foundation

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

/// Fixed benchmark passage (the Mac ORT benchmark's input; 501 phonemes with FluidAudio's G2P).
enum KokoroCPUBenchText {
    static let long = "At first, people didn't like the rules. There were too many restrictions, not enough freedom. Some individuals would skip out on their tests, refusing to become part of the “New America”. President I. Ericcson-Sprucefeld said at a press conference, much lacking in actual press, that “the government has a very powerful weapon in its grasp that, if needed, would be unleashed on the entire population of the U.S.A., no matter how many people are involved.” This shut people up real fast."

    /// FluidAudio v0.16.1 phonemes of `long`, computed on the Mac (fallback only, used when
    /// the on-device phonemizer can't run; the result records `phonemes_source`).
    static let longPhonemesMac = "æt fˈɜɹst, pˈipᵊl dˈɪdᵊnt lˈIk ði ɹˈulz. ðɛɹ wɜɹ tˈu mˈɛni ɹəstɹˈɪkʃənz, nˌɑt ɪnˈʌf fɹˈidəm. sˌʌm ˌɪndəvˈɪʤəwəlz wʊd skˈɪp ˈWt ˌɔn ðɛɹ tˈɛsts, ɹəfjˈuzɪŋ tu bəkˈʌm pˈɑɹt ʌv ði“ nˈu əmˈɛɹəkə”. pɹˈɛzədˌɛnt ˈI. əɹˈɪksᵊn spɹˈusfˌɛld sˈɛd æt A pɹˈɛs kˈɑnfəɹəns, mˈʌʧ lˈækɪŋ ɪn ˈækʧəwəl pɹˈɛs, ðæt“ ði ɡˈʌvəɹnmənt hæz A vˈɛɹi pˈWəɹfᵊl wˈɛpən ɪn ɪts ɡɹˈæsp ðæt, ɪf nˈidᵻd, wʊd bi ʌnlˈiʃt ˌɔn ði əntˈIəɹ pˌɑpjəlˈAʃən ʌv ði jˈu ˈɛs ˈA., nˈO mˈæɾəɹ hˌW mˈɛni pˈipᵊl ɑɹ ɪnvˈɑlvd.” ðɪs ʃˈʌt pˈipᵊl ˌʌp ɹˈiᵊl fˈæst."
}
#endif
