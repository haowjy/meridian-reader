import Foundation

/// Reader local patch (2026-09-24): the KokoroAne English text frontend *without Core ML*.
///
/// `KokoroAneManager.phonemes(for:)` loads all 7 Kokoro Core ML stages just to read
/// `vocab.json`, and phonemizes OOV words with `G2PModel` (Core ML BART, `.cpuOnly` ⇒ BNNS).
/// Reader's ONNX Runtime route needs only IPA → token ids, so this actor rebuilds the same
/// frontend from plain files:
///   - `ANE/vocab.json` (token ids + the punctuation set the phonemizer keeps),
///   - `kokoro/us_lexicon_cache.json` via `LexiconAssetCache` (Misaki weak forms),
///   - `EnglishTextNormalizer.normalizeForFrontend` (NeMo FST / regex; no Core ML),
///   - `KokoroAneEnglishPhonemizer` (unchanged) with `KokoroSwiftG2P` as the OOV fallback.
/// Output is identical to `KokoroAneManager.phonemes(for:)` whenever the Swift BART matches
/// the Core ML BART token-for-token (validated in Reader's tests).
public actor KokoroAneCPUFrontend {

    public enum FrontendError: Error, LocalizedError {
        case assetsMissing(String)
        public var errorDescription: String? {
            switch self {
            case .assetsMissing(let s): return "Kokoro text frontend asset missing: \(s)"
            }
        }
    }

    private static let logger = AppLogger(category: "KokoroAneCPUFrontend")

    private let repoDirectory: URL
    private let kokoroDirectory: URL
    private var vocab: KokoroAneVocab?
    private var phonemizer: KokoroAneEnglishPhonemizer?
    private var g2p: KokoroSwiftG2P?
    private var oovCache: [String: [String]] = [:]
    private let lexiconCache = LexiconAssetCache()
    /// OOV words resolved by the Swift BART since launch (diagnostics).
    public private(set) var oovWordCount = 0

    /// Defaults: `<TTS cache>/Models/kokoro-82m-coreml/ANE` and `<TTS cache>/Models/kokoro`.
    public init(repoDirectory: URL? = nil, kokoroDirectory: URL? = nil) throws {
        self.repoDirectory = try repoDirectory ?? Self.defaultRepoDirectory()
        self.kokoroDirectory = try kokoroDirectory ?? Self.defaultKokoroDirectory()
    }

    public static func defaultRepoDirectory() throws -> URL {
        try KokoroAneResourceDownloader.repositoryDirectory(variant: .english)
    }

    public static func defaultKokoroDirectory() throws -> URL {
        try TtsCacheDirectory.ensure()
            .appendingPathComponent(KokoroAneResourceDownloader.modelsSubdirectory)
            .appendingPathComponent(Repo.kokoro.folderName)
    }

    /// Files this frontend needs (relative names inside the two directories).
    public static let requiredKokoroFiles: [String] = [
        ModelNames.G2P.vocabularyFile,
        "\(ModelNames.G2P.encoderFile)/model.mil", "\(ModelNames.G2P.encoderFile)/weights/weight.bin",
        "\(ModelNames.G2P.decoderFile)/model.mil", "\(ModelNames.G2P.decoderFile)/weights/weight.bin",
        "us_lexicon_cache.json",
    ]

    /// True when vocab + G2P weights + lexicon are on disk (no network needed).
    public static func assetsPresent() -> Bool {
        guard let repo = try? defaultRepoDirectory(), let kokoro = try? defaultKokoroDirectory() else {
            return false
        }
        let fm = FileManager.default
        guard fm.fileExists(atPath: repo.appendingPathComponent("vocab.json").path) else { return false }
        return requiredKokoroFiles.allSatisfy { fm.fileExists(atPath: kokoro.appendingPathComponent($0).path) }
    }

    /// Download the frontend's files if missing (≈3 MB): `ANE/vocab.json`, the G2P bundle
    /// (weights are read by `KokoroSwiftG2P`, never loaded into Core ML) and the lexicon.
    /// Does NOT download the 7 Kokoro Core ML stages.
    public static func ensureAssets() async throws {
        let repo = try defaultRepoDirectory()
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        let vocabURL = repo.appendingPathComponent("vocab.json")
        if !FileManager.default.fileExists(atPath: vocabURL.path) {
            let r = KokoroAneVariant.english.repo
            let remotePath = r.subPath.map { "\($0)/vocab.json" } ?? "vocab.json"
            let remote = try ModelRegistry.resolveModel(r.remotePath, remotePath)
            _ = try await AssetDownloader.ensure(
                AssetDownloader.Descriptor(description: "vocab.json", remoteURL: remote, destinationURL: vocabURL),
                logger: logger)
        }
        try await KokoroAneResourceDownloader.ensureG2PAssets(directory: nil)
        guard await KokoroAneResourceDownloader.ensureEnglishLexicon(directory: nil) != nil else {
            throw FrontendError.assetsMissing("us_lexicon_cache.json")
        }
    }

    /// Load vocab, lexicon and Swift G2P (idempotent). No Core ML.
    public func prepare() async throws {
        if phonemizer != nil { return }
        let vocabURL = repoDirectory.appendingPathComponent("vocab.json")
        guard FileManager.default.fileExists(atPath: vocabURL.path) else {
            throw FrontendError.assetsMissing("vocab.json")
        }
        let v = try KokoroAneVocab.load(from: vocabURL)
        let punctuation = Set(v.map.keys.filter { !$0.isLetter && !$0.isNumber && !$0.isWhitespace })
        let allowedTokens = Set(v.map.keys.map(String.init))
        try await lexiconCache.ensureLoaded(kokoroDirectory: kokoroDirectory, allowedTokens: allowedTokens)
        let maps = await lexiconCache.lexicons()
        g2p = try KokoroSwiftG2P(kokoroDirectory: kokoroDirectory)
        vocab = v
        phonemizer = KokoroAneEnglishPhonemizer(
            wordToPhonemes: maps.word,
            caseSensitiveWordToPhonemes: maps.caseSensitive,
            allowedPunctuation: punctuation)
    }

    /// English text → Misaki IPA, like `KokoroAneManager.phonemes(for:)` (english variant).
    public func phonemes(for text: String) async throws -> String {
        try await prepare()
        guard let phonemizer else { throw FrontendError.assetsMissing("phonemizer") }
        let normalized = EnglishTextNormalizer.normalizeForFrontend(text)
        let fallback: @Sendable (String) async -> [String]? = { [self] word in
            await self.oov(word)
        }
        return try await phonemizer.phonemize(normalized, fallback: fallback)
    }

    private func oov(_ word: String) -> [String]? {
        if let hit = oovCache[word] { return hit }
        let result = g2p?.phonemize(word: word)
        oovWordCount += 1
        if oovCache.count > 4096 { oovCache.removeAll(keepingCapacity: true) }
        oovCache[word] = result ?? []
        return result
    }

    /// IPA → token ids *without* BOS/EOS (callers pad with 0 on both sides).
    public func tokenIDs(for phonemes: String) async throws -> [Int32] {
        try await prepare()
        guard let vocab else { throw FrontendError.assetsMissing("vocab.json") }
        let ids = try vocab.encode(phonemes)
        guard ids.count >= 2 else { return [] }
        return Array(ids.dropFirst().dropLast())
    }

    /// Swift BART alone (tests/diagnostics).
    public func swiftG2P(word: String) async throws -> [String]? {
        try await prepare()
        return g2p?.phonemize(word: word)
    }

    /// Test hook: compare the Swift BART with the Core ML `G2PModel` on `words`.
    /// Returns mismatching words with both outputs. Runs Core ML — never call on device paths.
    public static func debugCompareWithCoreML(words: [String]) async throws -> [(word: String, swift: String, coreML: String)] {
        let swift = try KokoroSwiftG2P(kokoroDirectory: try defaultKokoroDirectory())
        var bad: [(String, String, String)] = []
        for w in words {
            let a = (swift.phonemize(word: w) ?? []).joined()
            let b = (try await G2PModel.shared.phonemize(word: w) ?? []).joined()
            if a != b { bad.append((w, a, b)) }
        }
        return bad
    }
}
