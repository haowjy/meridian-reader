import SwiftUI

/// One adapter per voice library (FluidAudio for Kokoro, Phonon). Registers the engines
/// it provides and builds their synth hosts. Only provider files import the library.
/// What a provider needs to decide its hooks (launch arguments, settings) comes in at its init,
/// from `AppComposition.makeProviders()`.
@MainActor
protocol SpeechEngineProvider: AnyObject {
    var name: String { get }
    var descriptors: [EngineDescriptor] { get }
    /// Engines this provider removed; cleaned up once at launch (selection, cache, files).
    var retiredEngines: [RetiredEngine] { get }
    /// How each of its engines runs (its lane, whether it takes a thread count), as data. The
    /// render policy picks among an engine's own routes only.
    var routes: [RenderRoute] { get }
    /// New synth host that runs `route` (one of `routes`; nil for another).
    func makeHost(for route: RenderRoute, voice: String?) -> LocalSynthHost?
    /// Model files for `id` look present on disk.
    func isInstalled(_ id: SpeechEngineID) -> Bool
    /// Make sure `voice`'s files are on disk (prepare if needed) before it's selected.
    /// No-op for engines whose voices ship with the model.
    func prepareVoice(_ voice: String, for id: SpeechEngineID) async throws
    /// One voice pack's files are on disk (Kokoro `<voice>.bin`). False for engines without packs.
    func isVoicePackInstalled(_ voice: String, for id: SpeechEngineID) -> Bool
    /// Settings may offer *Remove Download* for this pack (Heart is protected when alone).
    func canDeleteVoicePack(_ voice: String, for id: SpeechEngineID) -> Bool
    /// Remove one voice pack's download. No-op when `canDeleteVoicePack` is false.
    func deleteVoicePack(_ voice: String, for id: SpeechEngineID) throws
    /// The previous process died inside a call of one of this provider's engines (`crash.engine`).
    /// nil: the default (pause for Retry, `LocalTTSCoordinator.recover`). `playing` is the last
    /// session resume point.
    func recover(from crash: EngineCrashGuard.CrashInfo, playing: ListenResumeTarget?) -> CrashRecovery?
    /// Where this provider keeps files it downloads or can make again (models, voices): kept out
    /// of backups at launch (`BackupExclusion`).
    var regenerableDirectories: [URL] { get }
    /// The settings this library stores itself (each engine's voice key aside), for
    /// `-resetLibrary` to clear (`EngineRegistry.storedKeys`).
    var storedKeys: [String] { get }
    /// This library's launch steps, run after every retired engine's cleanup
    /// (`EngineRegistry.launchMigrations`).
    var launchMigrations: [LaunchMigration] { get }
    /// This library's sections of the Listen debug panel (its own settings and diagnostics).
    func debugSections(speech: SpeechController) -> AnyView
}

extension SpeechEngineProvider {
    var retiredEngines: [RetiredEngine] { [] }
    func prepareVoice(_ voice: String, for id: SpeechEngineID) async throws {}
    func isVoicePackInstalled(_ voice: String, for id: SpeechEngineID) -> Bool { false }
    func canDeleteVoicePack(_ voice: String, for id: SpeechEngineID) -> Bool { false }
    func deleteVoicePack(_ voice: String, for id: SpeechEngineID) throws {}
    func recover(from crash: EngineCrashGuard.CrashInfo, playing: ListenResumeTarget?) -> CrashRecovery? { nil }
    var regenerableDirectories: [URL] { [] }
    var storedKeys: [String] { [] }
    var launchMigrations: [LaunchMigration] { [] }
    func debugSections(speech: SpeechController) -> AnyView { AnyView(EmptyView()) }
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
        precondition(providers.contains { !$0.descriptors.isEmpty }, "No engine registered")
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
        for d in all {
            precondition(map[d.id]?.1.routes.contains { $0.engine == d.id } == true, "No route for \(d.id)")
        }
    }

    /// `id`'s routes, from its provider (read each time: a route's thread cap is a setting).
    func routes(for id: SpeechEngineID) -> [RenderRoute] {
        byID[id]?.1.routes.filter { $0.engine == id } ?? []
    }

    func descriptor(_ id: SpeechEngineID) -> EngineDescriptor? { byID[id]?.0 }
    func contains(_ id: SpeechEngineID) -> Bool { byID[id] != nil }

    var retiredEngines: [RetiredEngine] { providers.flatMap(\.retiredEngines) }
    var regenerableDirectories: [URL] { providers.flatMap(\.regenerableDirectories) }
    /// Every setting the registered engines store: each engine's voice and each library's own.
    var storedKeys: [String] { descriptors.map(\.resolvedVoiceDefaultsKey) + providers.flatMap(\.storedKeys) }
    /// Launch steps, in order: retired engines' cleanup, then each library's own
    /// (`AppComposition.prepareAudioCache`).
    var launchMigrations: [LaunchMigration] {
        retiredEngines.map(RetiredEngineCleanup.init) + providers.flatMap(\.launchMigrations)
    }

    /// The engine a fresh install speaks in, and that sizes chunks / keys the cache while no engine
    /// is loaded: the recommended one (Phonon today), else the first.
    var defaultEngine: EngineDescriptor {
        descriptors.first { $0.isRecommended } ?? descriptors[0]
    }

    func shortName(_ id: SpeechEngineID) -> String { descriptor(id)?.shortName ?? id.rawValue }
    func displayName(_ id: SpeechEngineID) -> String { descriptor(id)?.displayName ?? id.rawValue }

    func supports(_ id: SpeechEngineID) -> Bool {
        guard let d = descriptor(id) else { return false }
        return gate(d.hardware)
    }

    /// Why `id` can't run here, for its Settings section ("Needs an iPhone 13 or newer."); nil: it can.
    func blockReason(_ id: SpeechEngineID) -> String? {
        guard let d = descriptor(id) else { return String(localized: "This voice isn’t available.") }
        guard !gate(d.hardware) else { return nil }
        return String(localized: "Needs \(d.hardware.summary).")
    }

    /// The same where the voice library isn't named around it (▶'s toast): "Kokoro needs an
    /// iPhone 13 or newer."; nil: it can run here.
    func cantRunNotice(_ id: SpeechEngineID) -> String? {
        guard let d = descriptor(id) else { return String(localized: "This voice isn’t available.") }
        guard !gate(d.hardware) else { return nil }
        return String(localized: "\(d.shortName) needs \(d.hardware.summary).")
    }

    func makeHost(for route: RenderRoute, voice: String?) -> LocalSynthHost? {
        byID[route.engine]?.1.makeHost(for: route, voice: voice)
    }

    func isInstalled(_ id: SpeechEngineID) -> Bool {
        byID[id]?.1.isInstalled(id) ?? false
    }

    func prepareVoice(_ voice: String, for id: SpeechEngineID) async throws {
        try await byID[id]?.1.prepareVoice(voice, for: id)
    }

    func isVoicePackInstalled(_ voice: String, for id: SpeechEngineID) -> Bool {
        byID[id]?.1.isVoicePackInstalled(voice, for: id) ?? false
    }

    func canDeleteVoicePack(_ voice: String, for id: SpeechEngineID) -> Bool {
        byID[id]?.1.canDeleteVoicePack(voice, for: id) ?? false
    }

    func deleteVoicePack(_ voice: String, for id: SpeechEngineID) throws {
        try byID[id]?.1.deleteVoicePack(voice, for: id)
    }

    /// The selection a cache voice key was made in: "kokoro.af_heart" → Kokoro's Heart; nil for a
    /// key no registered engine writes.
    func selection(forCacheVoice voiceID: String) -> VoiceSelection? {
        for d in descriptors {
            if let voice = d.engineVoice(fromCacheVoice: voiceID) { return VoiceSelection(engine: d.id, voice: voice) }
        }
        return nil
    }

    /// The crashed engine's provider decides how to recover (nil: the default rule).
    func recover(from crash: EngineCrashGuard.CrashInfo, playing: ListenResumeTarget?) -> CrashRecovery? {
        guard let id = crash.engine, supports(id) else { return nil }
        return byID[id]?.1.recover(from: crash, playing: playing)
    }
}
