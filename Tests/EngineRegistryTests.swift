import XCTest
@testable import Reader

/// Registry / capability tests. Also pins the persisted ids + cache voice keys so the DI
/// refactor can't silently invalidate existing Kokoro caches or settings.
@MainActor
final class EngineRegistryTests: XCTestCase {
    private func appRegistry(gate: @escaping (HardwareRequirement) -> Bool = { _ in true }) -> EngineRegistry {
        EngineRegistry(providers: [AppleSpeechProvider(), FluidAudioProvider()], gate: gate)
    }

    func testPersistedIDsAndCacheKeysUnchanged() {
        XCTAssertEqual(SpeechEngineID.apple.rawValue, "apple")
        XCTAssertEqual(SpeechEngineID.kokoro.rawValue, "local.kokoro")
        XCTAssertEqual(SpeechEngineID.retiredChatterboxNano.rawValue, "local.chatterbox-nano")
        let kokoro = FluidAudioProvider.kokoroDescriptor
        XCTAssertEqual(kokoro.cacheVoiceID(engineVoice: "af_heart", appleVoice: "com.apple.voice.x"), "kokoro.af_heart")
        XCTAssertEqual(kokoro.cacheVoiceID(engineVoice: nil, appleVoice: nil), "kokoro.af_heart")
        XCTAssertEqual(kokoro.resolvedVoiceDefaultsKey, "reader.tts.kokoroVoice")
        let retired = FluidAudioProvider().retiredEngines
        XCTAssertEqual(retired.map(\.id), [.retiredChatterboxNano])
        XCTAssertEqual(retired.first?.replacement, .kokoro)
        XCTAssertEqual(ArticleAudioCache.legacyEngineID, SpeechEngineID.retiredChatterboxNano.rawValue)
    }

    func testSettingsOrderDefaultsAndCapabilities() {
        let registry = appRegistry()
        XCTAssertEqual(registry.descriptors.map(\.id), [.apple, .kokoro], "Kokoro is the only local engine")
        XCTAssertFalse(registry.contains(.retiredChatterboxNano))
        XCTAssertNil(registry.makeHost(for: .retiredChatterboxNano, voice: nil))
        XCTAssertEqual(registry.systemDescriptor?.id, .apple)
        XCTAssertEqual(registry.defaultLocalEngineID, .kokoro)
        XCTAssertFalse(registry.descriptor(.apple)!.supportsBakeCache)
        XCTAssertTrue(registry.descriptor(.kokoro)!.supportsBakeCache)
        XCTAssertTrue(registry.descriptor(.kokoro)!.crashGuarded)
        XCTAssertEqual(registry.limits(for: .kokoro), .kokoroCPU, "ONNX CPU route is the default")
        XCTAssertTrue(registry.isEngineVoiceKey("kokoro.af_bella"))
        XCTAssertFalse(registry.isEngineVoiceKey("com.apple.voice.compact.en-US.Samantha"))
        XCTAssertFalse(registry.isEngineVoiceKey("system"))
    }

    func testHardwareGateAndBlockReason() {
        // Device that fails every chip floor: Apple still available, locals blocked with a reason.
        let registry = appRegistry(gate: { $0.minimumChip == nil })
        XCTAssertTrue(registry.supports(.apple))
        XCTAssertFalse(registry.supports(.kokoro))
        XCTAssertEqual(registry.blockReason(.kokoro), "Insufficient hardware. Needs iPhone 13 / recent iPad (A15+).")
        XCTAssertEqual(registry.blockReason(.retiredChatterboxNano), "Unknown voice engine.")
        XCTAssertNil(registry.blockReason(.apple))
    }

    func testKokoroCrashFallsBackToApple() {
        XCTAssertEqual(appRegistry().crashFallback(for: .kokoro), .apple)
    }

    func testCrashFallbackPrefersInstalledLocalThenApple() {
        let fake = FakeEngineProvider()
        let registry = EngineRegistry(providers: [AppleSpeechProvider(), fake], gate: { _ in true })
        XCTAssertEqual(registry.crashFallback(for: .kokoro), FakeEngineProvider.fakeID)
        fake.installed = false
        XCTAssertEqual(registry.crashFallback(for: .kokoro), .apple)
        XCTAssertEqual(registry.crashFallback(for: FakeEngineProvider.fakeID), .apple)
    }

    func testNewProviderAppearsWithoutCoreChanges() {
        let registry = EngineRegistry(providers: [AppleSpeechProvider(), FluidAudioProvider(), FakeEngineProvider()],
                                      gate: { _ in true })
        XCTAssertEqual(registry.localDescriptors.map(\.id), [.kokoro, FakeEngineProvider.fakeID])
        XCTAssertNotNil(registry.makeHost(for: FakeEngineProvider.fakeID, voice: nil))
        XCTAssertNil(registry.makeHost(for: .apple, voice: nil))
    }

    func testCrashGuardRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("crashguard-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let guardian = EngineCrashGuard(directory: dir)
        XCTAssertNil(guardian.consumeCrashMarker(legacyEngine: .kokoro))
        guardian.beginCall(engine: .kokoro, chars: 42, context: "t")
        guardian.endCall()
        XCTAssertNil(guardian.consumeCrashMarker(legacyEngine: nil), "clean call leaves no marker")
        guardian.beginCall(engine: .kokoro, chars: 42, context: "t") // process "dies" here
        XCTAssertEqual(guardian.consumeCrashMarker(legacyEngine: nil), .kokoro)
        XCTAssertEqual(guardian.crashCount, 1)
        // Pre-DI marker (no engine field) is attributed to the legacy engine.
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"chars":10}"#.utf8).write(to: dir.appendingPathComponent("kokoro_inflight.json"))
        XCTAssertEqual(guardian.consumeCrashMarker(legacyEngine: .kokoro), .kokoro)
    }
}
