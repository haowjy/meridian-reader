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
}

/// One selectable voice of an engine.
struct EngineVoice: Hashable, Sendable, Identifiable {
    let id: String
    /// Row title ("Heart").
    let label: String
    /// Row subtitle ("Warm, American").
    var detail: String = ""
    /// Bundled preview clip (m4a resource name, no extension, in `VoicePreviews/`), if any.
    var previewResource: String? = nil
}

/// Device floor for an engine. Evaluated by `DeviceChipGate.meets(_:)`.
struct HardwareRequirement: Sendable, Equatable {
    var minimumOSMajor: Int = 17
    var minimumChip: DeviceChipGeneration? = nil
    var allowsSimulator: Bool = true
    /// Short human requirement, e.g. "iPhone 13 or newer (A15+)".
    var summary: String = ""

    static let none = HardwareRequirement()
}

/// Everything the shared core needs to know about an engine. Core code reads these
/// capabilities; it never switches on concrete engine types.
struct EngineDescriptor: Sendable, Identifiable {
    let id: SpeechEngineID
    /// Settings row title ("Kokoro (on-device)").
    let displayName: String
    /// Debug overlay / logs / "Preparing X…" ("Kokoro").
    let shortName: String
    /// Settings subtitle before the model is downloaded.
    let subtitle: String
    /// Shows "Ready (recommended)" and wins `EngineRegistry.defaultLocalEngineID`.
    var isRecommended = false
    /// Settings order among engines (ascending).
    let sortOrder: Int

    /// Settings' Voice section for this engine; empty when its voices are picked elsewhere (Apple).
    var voices: [EngineVoice] = []
    /// Extra voices shown under *More voices* below `voices` (Phonon's full bundle).
    var moreVoices: [EngineVoice] = []
    /// `voices` + `moreVoices`: everything selectable.
    var allVoices: [EngineVoice] { voices + moreVoices }
    var defaultVoiceID: String? = nil
    /// UserDefaults key for the selected voice (nil → "reader.tts.voice.<id>").
    var voiceDefaultsKey: String? = nil
    var hardware: HardwareRequirement = .none
    /// Languages the engine can speak, as base language codes ("en"). Empty = any language
    /// (Apple). An article whose effective language isn't listed speaks with Apple instead.
    var supportedLanguages: [String] = []
    /// What only an on-device model has. An engine is on-device exactly when this is set: it
    /// renders audio ahead into the cache through the render queue. nil for Apple.
    let onDevice: OnDeviceTraits?

    var resolvedVoiceDefaultsKey: String { voiceDefaultsKey ?? "reader.tts.voice.\(id.rawValue)" }

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
        if let stored, allVoices.contains(where: { $0.id == stored }) { return stored }
        return defaultVoiceID ?? voices.first?.id
    }

    /// Cache voice key of this engine's audio in `engineVoice` (nil: its default voice); nil for
    /// an engine that renders nothing ahead.
    func cacheVoiceID(engineVoice: String?) -> String? {
        onDevice.map { "\($0.cacheVoicePrefix).\(engineVoice ?? defaultVoiceID ?? "default")" }
    }
}

/// What an on-device engine adds to its descriptor.
struct OnDeviceTraits: Sendable {
    /// The voice half of the engine's `ArticleAudioCache` keys: "<prefix>.<engine voice id>",
    /// e.g. "kokoro.af_heart". Must stay stable per engine or existing caches stop matching.
    let cacheVoicePrefix: String
    /// Per-call chunk sizing used by `TextChunker` (units = chars, digits ×3).
    let limits: TextChunker.Limits
    /// The engine can die uncatchably inside a model call: every call is wrapped in
    /// `EngineCrashGuard`, and this cause goes in the notice after a crash ("Kokoro stopped
    /// unexpectedly"). nil: not guarded.
    var crashNotice: String? = nil
}

/// An engine a provider has removed. At launch (once, idempotent) the
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
