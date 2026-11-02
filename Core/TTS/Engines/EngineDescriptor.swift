import Foundation

/// Stable engine identifier. Persisted in every stored `VoiceSelection` and in every
/// `TTSCache/<article>/index.json` entry, so raw values must never change once shipped.
/// Ids for concrete engines are declared by their provider (e.g. `FluidAudioProvider`); the shared
/// core knows none.
struct SpeechEngineID: RawRepresentable, Hashable, Codable, Sendable, Identifiable, CustomStringConvertible {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }

    var id: String { rawValue }
    var description: String { rawValue }
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
    /// What the device needs, after "Needs": "an iPhone 13 or newer".
    var summary: String = ""

    static let none = HardwareRequirement()
}

/// Everything the shared core needs to know about an engine. Core code reads these
/// capabilities; it never switches on concrete engine types. Every engine is an on-device model
/// that renders audio ahead into the cache through the render queue.
struct EngineDescriptor: Sendable, Identifiable {
    let id: SpeechEngineID
    /// Settings section title ("Kokoro").
    let displayName: String
    /// Debug overlay / logs / "Preparing X…" ("Kokoro").
    let shortName: String
    /// Shows "Ready (recommended)" and wins `EngineRegistry.defaultLocalEngineID`.
    var isRecommended = false
    /// Settings order among engines (ascending).
    let sortOrder: Int

    /// Settings' Voice section for this engine.
    var voices: [EngineVoice] = []
    /// Extra voices shown under *More voices* below `voices` (Phonon's full bundle).
    var moreVoices: [EngineVoice] = []
    /// `voices` + `moreVoices`: everything selectable.
    var allVoices: [EngineVoice] { voices + moreVoices }
    var defaultVoiceID: String? = nil
    /// UserDefaults key for the selected voice (nil → "reader.tts.voice.<id>").
    var voiceDefaultsKey: String? = nil
    var hardware: HardwareRequirement = .none
    /// Languages the engine can speak, as base language codes ("en"). Empty = any language. An
    /// article detected in a language it doesn't list isn't read (`ListenLanguage.unspoken`).
    var supportedLanguages: [String] = []
    /// Its cache keys, chunk limits and crash guarding.
    let onDevice: OnDeviceTraits

    var resolvedVoiceDefaultsKey: String { voiceDefaultsKey ?? "reader.tts.voice.\(id.rawValue)" }

    /// True if the engine can speak `languageCode` (any BCP-47 form; compared by base language).
    func supportsLanguage(_ languageCode: String) -> Bool {
        supportedLanguages.isEmpty
            || supportedLanguages.contains(ListenLanguage.baseCode(languageCode))
    }

    /// Voice to use for a stored selection: the stored id if it's still offered, else the default.
    func resolvedVoice(_ stored: String?) -> String? {
        if let stored, allVoices.contains(where: { $0.id == stored }) { return stored }
        return defaultVoiceID ?? voices.first?.id
    }

    /// Cache voice key of this engine's audio in `engineVoice` (nil: its default voice).
    func cacheVoiceID(engineVoice: String?) -> String {
        "\(onDevice.cacheVoiceNamespace).\(engineVoice ?? defaultVoiceID ?? "default")"
    }

    /// The engine voice a cache voice key of this engine names, in any revision ("kokoro.af_heart"
    /// → "af_heart", "phonon@1792483937.Zoey" → "Zoey"); nil for another engine's key.
    func engineVoice(fromCacheVoice key: String) -> String? {
        let prefix = onDevice.cacheVoicePrefix
        guard key.hasPrefix(prefix) else { return nil }
        let rest = key.dropFirst(prefix.count)
        switch rest.first {
        case ".": return String(rest.dropFirst())
        case "@": return rest.firstIndex(of: ".").map { String(rest[rest.index(after: $0)...]) }
        default: return nil
        }
    }
}

/// What an on-device engine adds to its descriptor.
struct OnDeviceTraits: Sendable {
    /// The voice half of the engine's `ArticleAudioCache` keys: "<prefix>.<engine voice id>",
    /// e.g. "kokoro.af_heart". Must stay stable per engine or existing caches stop matching.
    let cacheVoicePrefix: String
    /// Which model renders the audio, for an engine whose model can change under the same voices:
    /// part of every cache voice key ("phonon@1792483937.Zoey"), so audio another model rendered
    /// never plays or counts as prepared for this one. Known without loading the model. nil: the
    /// keys carry none ("kokoro.af_heart"). Changing it re-renders every article's audio.
    var cacheRevision: String? = nil
    /// Per-call chunk sizing used by `TextChunker` (units = chars, digits ×3).
    let limits: TextChunker.Limits
    /// The engine can die uncatchably inside a model call: every call is wrapped in
    /// `EngineCrashGuard`.
    var isCrashGuarded = false

    /// A cache voice key up to its voice: the prefix, with the revision when there is one.
    var cacheVoiceNamespace: String { cacheRevision.map { "\(cacheVoicePrefix)@\($0)" } ?? cacheVoicePrefix }
}

/// An engine a provider has removed. At launch (once, idempotent) its cached article audio is
/// deleted and `deleteFiles` removes its models; a stored default in it takes the built-in
/// default (`LocalTTSCoordinator.loadDefaultSelection`).
struct RetiredEngine: @unchecked Sendable {
    let id: SpeechEngineID
    let displayName: String
    /// UserDefaults flag set after the cleanup ran.
    let doneKey: String
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

    /// A download's size in megabytes, as iOS's Voice screen writes it: "0.5 MB", "164 MB" (one
    /// decimal under 10 MB, whole megabytes above).
    static func megabytes(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_000_000
        let number = mb.formatted(.number.precision(.fractionLength(mb < 10 ? 1 : 0)))
        return String(localized: "\(number) MB")
    }
}
