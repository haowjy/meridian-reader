import Foundation

/// One adapter per voice library (Apple, FluidAudio, speech-swift, …). Registers the engines
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
}

extension SpeechEngineProvider {
    var retiredEngines: [RetiredEngine] { [] }
    func prepareVoice(_ voice: String, for id: SpeechEngineID) async throws {}
}

/// Composition-root registry of every engine. Built once at launch (`AppComposition`) and
/// injected into SpeechController → LocalTTSCoordinator → LocalModelSpeechEngine.
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

    var systemDescriptor: EngineDescriptor? { descriptors.first { $0.kind == .system } }
    var localDescriptors: [EngineDescriptor] { descriptors.filter { $0.kind == .onDevice } }
    var retiredEngines: [RetiredEngine] { providers.flatMap(\.retiredEngines) }

    /// Engine that sizes chunks / keys the cache when no local engine is active yet:
    /// the recommended on-device engine (Kokoro today), else the first one.
    var defaultLocalEngineID: SpeechEngineID {
        (localDescriptors.first { $0.isRecommended } ?? localDescriptors.first)?.id ?? .apple
    }

    func shortName(_ id: SpeechEngineID) -> String { descriptor(id)?.shortName ?? id.rawValue }
    func displayName(_ id: SpeechEngineID) -> String { descriptor(id)?.displayName ?? id.rawValue }

    /// Chunk limits for `id` (unknown → the most conservative registered limits).
    func limits(for id: SpeechEngineID) -> TextChunker.Limits {
        if let d = descriptor(id) { return d.limits }
        return localDescriptors.map(\.limits).min { $0.hardMax < $1.hardMax } ?? .kokoro
    }

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
        return d.kind == .system || p.isInstalled(id)
    }

    func deleteModels(_ id: SpeechEngineID) throws {
        try byID[id]?.1.deleteModels(id)
    }

    func prepareVoice(_ voice: String, for id: SpeechEngineID) async throws {
        try await byID[id]?.1.prepareVoice(voice, for: id)
    }

    /// True if `voiceID` is some engine's prefixed cache voice key (not an Apple voice id).
    func isEngineVoiceKey(_ voiceID: String) -> Bool {
        descriptors.contains {
            if case .prefixed(let p) = $0.cacheVoiceKey { return voiceID.hasPrefix(p + ".") }
            return false
        }
    }

    /// After `crashed` died mid-call: another supported, installed on-device engine, else Apple.
    func crashFallback(for crashed: SpeechEngineID) -> SpeechEngineID {
        localDescriptors.first { $0.id != crashed && supports($0.id) && isInstalled($0.id) }?.id ?? .apple
    }
}
