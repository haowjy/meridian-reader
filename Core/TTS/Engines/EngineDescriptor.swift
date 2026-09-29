import Foundation

/// Stable engine identifier. Persisted in UserDefaults (`reader.tts.engineID`) and in every
/// `TTSCache/<article>/index.json` entry, so raw values must never change once shipped.
/// Well-known ids for concrete engines are declared by their provider (e.g. `FluidAudioProvider`);
/// the shared core only knows `.apple`, the always-available system fallback.
struct SpeechEngineID: RawRepresentable, Hashable, Codable, Sendable, Identifiable, CustomStringConvertible {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }

    var id: String { rawValue }
    var description: String { rawValue }

    /// Apple `AVSpeechSynthesizer` — no model, no bake cache, always available.
    static let apple = SpeechEngineID("apple")

    /// Everything except Apple renders CAF audio through the single GlobalSynthQueue worker.
    var isLocal: Bool { self != .apple }
}

/// One selectable voice of an engine.
struct EngineVoice: Hashable, Sendable, Identifiable {
    let id: String
    /// Row title ("Heart").
    let label: String
    /// Row subtitle ("Warm · American").
    var detail: String = ""
    /// Bundled preview clip (m4a resource name, no extension, in `VoicePreviews/`), if any.
    var previewResource: String? = nil
}

/// How the engine produces audio.
struct EngineStreaming: Sendable, Equatable {
    /// Audio can start before the whole call finishes.
    let streams: Bool
    /// The library hands back PCM chunks as they are generated (vs one buffer per call).
    let yieldsPCMChunks: Bool

    static let wholeCall = EngineStreaming(streams: false, yieldsPCMChunks: false)
}

/// One downloadable asset (for Settings / docs; the provider does the actual download).
struct EngineAsset: Sendable, Equatable {
    let name: String
    let approxBytes: Int64
    let source: String
}

/// Device floor for an engine. Evaluated by `DeviceChipGate.meets(_:)`.
struct HardwareRequirement: Sendable, Equatable {
    var minimumOSMajor: Int = 17
    var minimumChip: DeviceChipGeneration? = nil
    var allowsSimulator: Bool = true
    /// Short human requirement, e.g. "iPhone 13 / recent iPad (A15+)".
    var summary: String = ""

    static let none = HardwareRequirement()
}

/// How the engine's paragraphs are keyed in `ArticleAudioCache` (voice half of the key).
/// Must stay stable per engine or existing caches stop matching.
enum CacheVoiceKeyStyle: Sendable, Equatable {
    /// The user's Apple voice id (or "system"). Legacy style (the retired Chatterbox Nano used it).
    case appleVoice
    /// "<prefix>.<engine voice id>", e.g. "kokoro.af_heart".
    case prefixed(String)
}

enum EngineKind: Sendable, Equatable {
    /// OS speech (Apple). Not rendered through the synth queue.
    case system
    /// On-device model rendered to CAF through the single synth worker.
    case onDevice
}

/// Everything the shared core needs to know about an engine. Core code reads these
/// capabilities; it never switches on concrete engine types.
struct EngineDescriptor: Sendable, Identifiable {
    let id: SpeechEngineID
    let providerName: String
    let kind: EngineKind
    /// Settings row title ("Kokoro (on-device)").
    let displayName: String
    /// Debug overlay / logs / "Preparing X…" ("Kokoro").
    let shortName: String
    /// Settings subtitle before the model is downloaded.
    let subtitle: String
    /// Shows "Ready · recommended" and wins `EngineRegistry.defaultLocalEngineID`.
    let isRecommended: Bool
    /// Settings order among engines (ascending).
    let sortOrder: Int

    let voices: [EngineVoice]
    let defaultVoiceID: String?
    /// UserDefaults key for the selected voice (nil → "reader.tts.voice.<id>").
    let voiceDefaultsKey: String?
    let cacheVoiceKey: CacheVoiceKeyStyle

    let streaming: EngineStreaming
    /// Per-call chunk sizing used by `TextChunker` (units = chars, digits ×3).
    let limits: TextChunker.Limits
    /// What the per-call cap really is (tokens / phonemes / seconds) and how limits map to it.
    let limitNotes: String

    let assets: [EngineAsset]
    let approxDownloadBytes: Int64
    let hardware: HardwareRequirement
    /// Compute routing the provider uses on this OS (e.g. "gpuAneVocoder"), for logs / docs.
    let computeRouting: String?
    let quirks: [String]

    /// Paragraph CAFs are baked + cached (bake marks, Preparing next, BG bake). Apple: false.
    let supportsBakeCache: Bool
    /// Wrap every model call in `EngineCrashGuard` (engine can die uncatchably inside the call).
    let crashGuarded: Bool
    /// Human cause shown in the crash notice ("Apple Core ML/BNNS bug on this iOS version").
    let crashNoticeDetail: String?
    /// Languages the engine can speak, as base language codes ("en"). Empty = any language
    /// (Apple). An article whose effective language isn't listed speaks with Apple instead.
    var supportedLanguages: [String] = []

    var resolvedVoiceDefaultsKey: String { voiceDefaultsKey ?? "reader.tts.voice.\(id.rawValue)" }

    /// "~95 MB download" style label.
    var downloadSizeLabel: String {
        guard approxDownloadBytes > 0 else { return "" }
        let mb = Double(approxDownloadBytes) / 1_000_000
        return "~\(Int((mb / 5).rounded() * 5)) MB download"
    }

    /// True if the engine can speak `languageCode` (any BCP-47 form; compared by base language).
    func supportsLanguage(_ languageCode: String) -> Bool {
        supportedLanguages.isEmpty
            || supportedLanguages.contains(ListenLanguage.baseCode(languageCode))
    }

    /// "Kokoro is English-only" style note (nil when the engine speaks any language).
    var languageLimitNote: String? {
        guard !supportedLanguages.isEmpty else { return nil }
        let names = supportedLanguages.map { ListenLanguage.displayName(for: $0) }
        if names.count == 1 { return "\(shortName) is \(names[0])-only" }
        return "\(shortName) speaks \(names.joined(separator: ", "))"
    }

    /// Voice to use for a stored selection: the stored id if it's still offered, else the default.
    func resolvedVoice(_ stored: String?) -> String? {
        if let stored, voices.contains(where: { $0.id == stored }) { return stored }
        return defaultVoiceID ?? voices.first?.id
    }

    /// Cache voice key for this engine given its voice and the user's Apple voice.
    func cacheVoiceID(engineVoice: String?, appleVoice: String?) -> String {
        switch cacheVoiceKey {
        case .appleVoice: return appleVoice ?? "system"
        case .prefixed(let prefix): return "\(prefix).\(engineVoice ?? defaultVoiceID ?? "default")"
        }
    }
}

/// An engine a provider used to ship and has removed. At launch (once, idempotent) the
/// coordinator moves a persisted selection of `id` to `replacement` when that engine is installed
/// (else Apple), deletes `id`'s cached article audio, and calls `deleteFiles` for its models.
struct RetiredEngine: @unchecked Sendable {
    let id: SpeechEngineID
    let displayName: String
    /// UserDefaults flag set after the cleanup ran.
    let doneKey: String
    let replacement: SpeechEngineID
    /// Deletes the engine's model files / leftovers; returns bytes freed.
    let deleteFiles: () -> Int64
}

/// On-disk size helpers (allocated bytes, so "freed" matches what the OS reports).
enum FileSizes {
    static func allocatedBytes(at url: URL, fileManager fm: FileManager = .default) -> Int64 {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]
        func size(_ u: URL) -> Int64 {
            let v = try? u.resourceValues(forKeys: keys)
            return Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? v?.fileSize ?? 0)
        }
        guard isDir.boolValue else { return size(url) }
        var total: Int64 = 0
        if let e = fm.enumerator(at: url, includingPropertiesForKeys: Array(keys)) {
            for case let u as URL in e { total += size(u) }
        }
        return total
    }

    static func label(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
