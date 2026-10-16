import Foundation

/// One adapter per voice library (Apple, FluidAudio). Registers the engines
/// it provides and builds their synth hosts. Only provider files import the library.
@MainActor
protocol SpeechEngineProvider: AnyObject {
    var name: String { get }
    var descriptors: [EngineDescriptor] { get }
    /// Engines this provider removed; cleaned up once at launch (selection, cache, files).
    var retiredEngines: [RetiredEngine] { get }
    /// New synth host for an on-device engine (nil for system engines / unknown ids).
    func makeHost(for id: SpeechEngineID, voice: String?) -> LocalSynthHost?
    /// Model files for `id` look present on disk.
    func isInstalled(_ id: SpeechEngineID) -> Bool
    /// Remove downloaded model files for `id`.
    func deleteModels(_ id: SpeechEngineID) throws
    /// Make sure `voice`'s files are on disk (download if needed) before it's selected.
    /// No-op for engines whose voices ship with the model.
    func prepareVoice(_ voice: String, for id: SpeechEngineID) async throws
    /// The previous process died inside a call of one of this provider's engines (`crash.engine`).
    /// nil: the default (switch away from it if it was selected). `playing` is the last session
    /// resume point.
    func recover(from crash: EngineCrashGuard.CrashInfo, playing: ListenResumeTarget?) -> CrashRecovery?
    /// The user picked `id` again after a crash moved them off it (a fresh try).
    func crashRetried(_ id: SpeechEngineID)
    /// Where this provider keeps files it downloads or can make again (models, voices): kept out
    /// of backups at launch (`BackupExclusion`).
    var regenerableDirectories: [URL] { get }
}

extension SpeechEngineProvider {
    var retiredEngines: [RetiredEngine] { [] }
    func prepareVoice(_ voice: String, for id: SpeechEngineID) async throws {}
    func recover(from crash: EngineCrashGuard.CrashInfo, playing: ListenResumeTarget?) -> CrashRecovery? { nil }
    func crashRetried(_ id: SpeechEngineID) {}
    var regenerableDirectories: [URL] { [] }
}

/// Composition-root registry of every engine. Built once at launch (`AppComposition`) and
/// injected into SpeechController → LocalTTSCoordinator → LocalSynthService.
@MainActor
final class EngineRegistry {
    let providers: [SpeechEngineProvider]
    /// All engines, Settings order.
    let descriptors: [EngineDescriptor]
    private let byID: [SpeechEngineID: (EngineDescriptor, SpeechEngineProvider)]
    /// Hardware check; injectable for tests.
    private let gate: (HardwareRequirement) -> Bool

    init(providers: [SpeechEngineProvider], gate: @escaping (HardwareRequirement) -> Bool = DeviceChipGate.meets) {
        self.providers = providers
        self.gate = gate
        var map: [SpeechEngineID: (EngineDescriptor, SpeechEngineProvider)] = [:]
        var all: [EngineDescriptor] = []
        for provider in providers {
            for d in provider.descriptors {
                precondition(map[d.id] == nil, "Duplicate engine id \(d.id) (\(provider.name))")
                map[d.id] = (d, provider)
                all.append(d)
            }
        }
        byID = map
        descriptors = all.sorted { ($0.sortOrder, $0.displayName) < ($1.sortOrder, $1.displayName) }
    }

    func descriptor(_ id: SpeechEngineID) -> EngineDescriptor? { byID[id]?.0 }
    func contains(_ id: SpeechEngineID) -> Bool { byID[id] != nil }

    /// The registered provider of type `P` (a library's own debug tools reach their provider so).
    func provider<P: SpeechEngineProvider>(_ type: P.Type) -> P? {
        providers.lazy.compactMap { $0 as? P }.first
    }

    var systemDescriptor: EngineDescriptor? { descriptors.first { $0.onDevice == nil } }
    var localDescriptors: [EngineDescriptor] { descriptors.filter { $0.onDevice != nil } }

    /// `id` is a registered on-device engine (its descriptor has `OnDeviceTraits`).
    func isOnDevice(_ id: SpeechEngineID) -> Bool { descriptor(id)?.onDevice != nil }
    var retiredEngines: [RetiredEngine] { providers.flatMap(\.retiredEngines) }
    var regenerableDirectories: [URL] { providers.flatMap(\.regenerableDirectories) }

    /// Engine that sizes chunks / keys the cache when no local engine is active yet:
    /// the recommended on-device engine (Kokoro today), else the first one.
    var defaultLocalEngineID: SpeechEngineID {
        (localDescriptors.first { $0.isRecommended } ?? localDescriptors.first)?.id ?? .apple
    }

    func shortName(_ id: SpeechEngineID) -> String { descriptor(id)?.shortName ?? id.rawValue }
    func displayName(_ id: SpeechEngineID) -> String { descriptor(id)?.displayName ?? id.rawValue }

    func supports(_ id: SpeechEngineID) -> Bool {
        guard let d = descriptor(id) else { return false }
        return gate(d.hardware)
    }

    func blockReason(_ id: SpeechEngineID) -> String? {
        guard let d = descriptor(id) else { return "Unknown voice engine." }
        guard !gate(d.hardware) else { return nil }
        return "Insufficient hardware. Needs \(d.hardware.summary)."
    }

    func makeHost(for id: SpeechEngineID, voice: String?) -> LocalSynthHost? {
        byID[id]?.1.makeHost(for: id, voice: voice)
    }

    func isInstalled(_ id: SpeechEngineID) -> Bool {
        guard let (d, p) = byID[id] else { return false }
        return d.onDevice == nil || p.isInstalled(id)
    }

    func deleteModels(_ id: SpeechEngineID) throws {
        try byID[id]?.1.deleteModels(id)
    }

    func prepareVoice(_ voice: String, for id: SpeechEngineID) async throws {
        try await byID[id]?.1.prepareVoice(voice, for: id)
    }

    /// A cache voice key as people read it: "kokoro.af_heart" → "Kokoro Heart" (the engine's short
    /// name, then the voice's), a single-voice engine's by its short name; any other key is an
    /// Apple voice ("Apple").
    func voiceLabel(forCacheVoice voiceID: String) -> String {
        for d in descriptors {
            guard let p = d.onDevice?.cacheVoicePrefix, voiceID.hasPrefix(p + ".") else { continue }
            let voice = String(voiceID.dropFirst(p.count + 1))
            guard let label = d.voices.first(where: { $0.id == voice })?.label else { return d.shortName }
            return "\(d.shortName) \(label)"
        }
        return descriptor(.apple)?.shortName ?? "Apple"
    }

    /// The crashed engine's provider decides how to recover (nil: the default rule).
    func recover(from crash: EngineCrashGuard.CrashInfo, playing: ListenResumeTarget?) -> CrashRecovery? {
        guard let id = crash.engine, supports(id) else { return nil }
        return byID[id]?.1.recover(from: crash, playing: playing)
    }

    func crashRetried(_ id: SpeechEngineID) {
        byID[id]?.1.crashRetried(id)
    }

    /// After `crashed` died mid-call: another supported, installed on-device engine, else Apple.
    func crashFallback(for crashed: SpeechEngineID) -> SpeechEngineID {
        localDescriptors.first { $0.id != crashed && supports($0.id) && isInstalled($0.id) }?.id ?? .apple
    }
}
