import AVFoundation
import UIKit
import XCTest
@testable import MeridianReader

/// The in-flight marker around a guarded engine call.
final class EngineCrashGuardTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("crashguard-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A swipe-kill of the running app ends the call it's in: no crash at the next launch, and
    /// no call started while the process ends writes another marker.
    func testATerminateClearsTheMarker() {
        let guardian = EngineCrashGuard(directory: directory)
        guardian.beginCall(engine: .kokoro, chars: 120, route: "onnx", article: UUID(), paragraph: 2)
        NotificationCenter.default.post(name: UIApplication.willTerminateNotification, object: nil)
        guardian.beginCall(engine: .kokoro, chars: 80, route: "onnx", article: UUID(), paragraph: 3)
        XCTAssertNil(EngineCrashGuard(directory: directory).consumeCrashInfo())
    }

    func testTheMarkerRecordsThePhaseAndFootprint() throws {
        EngineCrashGuard(directory: directory).beginCall(engine: .kokoro, chars: 120, route: "onnx", phase: .background)
        let crash = try XCTUnwrap(EngineCrashGuard(directory: directory).consumeCrashInfo())
        XCTAssertEqual(crash.phase, "background")
        XCTAssertGreaterThan(crash.footprintMB ?? 0, 0)
    }

    /// Two calls in flight when the process died: one crash, ambiguous (it can't say which call
    /// did it), and a finished call leaves no marker.
    func testTwoMarkersAreOneAmbiguousCrash() throws {
        let guardian = EngineCrashGuard(directory: directory)
        guardian.beginCall(engine: .kokoro, chars: 120, route: "onnx", paragraph: 2)
        guardian.beginCall(engine: .phonon, chars: 80, paragraph: 5)
        guardian.endCall(guardian.beginCall(engine: .phonon, chars: 60, paragraph: 6))
        let crash = try XCTUnwrap(EngineCrashGuard(directory: directory).consumeCrashInfo())
        XCTAssertTrue(crash.isAmbiguous)
        XCTAssertNil(EngineCrashGuard(directory: directory).consumeCrashInfo())
        guardian.beginCall(engine: .kokoro, chars: 120, route: "onnx", paragraph: 2)
        XCTAssertEqual(EngineCrashGuard(directory: directory).consumeCrashInfo()?.isAmbiguous, false)
    }
}


/// C129: a crash never switches engine or voice, and an install mid-call isn't a crash.
final class EngineStopRecoveryTests: XCTestCase {
    func testONNXCrashesResumeSilentlyThenPause() {
        var count = 0
        XCTAssertEqual(KokoroCrashRecovery.onCrash(onONNX: true, onnxCrashCount: &count), .resumeOnONNX)
        XCTAssertEqual(KokoroCrashRecovery.onCrash(onONNX: true, onnxCrashCount: &count), .pauseForRetry)
        XCTAssertEqual(count, 0)
        XCTAssertEqual(KokoroCrashRecovery.onCrash(onONNX: false, onnxCrashCount: &count), .resumeOnONNX)
    }

    func testRecoverStaysOnKokoroWithFewerThreads() {
        let defaults = UserDefaults(suiteName: "EngineStopRecoveryTests")!
        defaults.removePersistentDomain(forName: "EngineStopRecoveryTests")
        let settings = KokoroRouteSettings(defaults: defaults)
        settings.cpuThreads = 5
        let crash = EngineCrashGuard.CrashInfo(engine: .kokoro, route: "onnx", articleKey: nil, paragraph: 3,
                                               phase: "active", at: Date())
        let first = KokoroCrashRecovery.recover(from: crash, playing: nil, settings: settings)
        guard case .stay = first else { return XCTFail("\(first)") }
        XCTAssertEqual(settings.cpuThreads, 4)
        let second = KokoroCrashRecovery.recover(from: crash, playing: nil, settings: settings)
        guard case .pauseForRetry = second else { return XCTFail("\(second)") }
        XCTAssertEqual(settings.cpuThreads, 3)
        XCTAssertEqual(KokoroCrashRecovery.retryThreads(after: 2), 2)
    }

    func testMarkerFromAnotherBuildIsReinstallNotCrash() {
        var info = EngineCrashGuard.CrashInfo(engine: .kokoro, route: "onnx", articleKey: nil, paragraph: 1,
                                              phase: "active", at: Date(), footprintMB: 1017, build: "1-100")
        XCTAssertEqual(info.verdict(lastActivity: nil, currentBuild: "2-200"), .reinstalled)
        XCTAssertEqual(info.verdict(lastActivity: nil, currentBuild: "1-100"), .engineCrash)
        info.build = nil
        XCTAssertEqual(info.verdict(lastActivity: nil, currentBuild: "2-200"), .engineCrash)
        XCTAssertEqual(EngineCrashGuard.crashInfo(from: ["build": "9-9"], engine: .kokoro).build, "9-9")
    }

    /// An engine with no recovery of its own (Phonon's case) died mid-call: at the next launch it
    /// pauses for Retry in the same voice; nothing moves the default to another engine.
    @MainActor
    func testACrashPausesForRetryInTheSameVoice() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("crashpause-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let suite = "EngineStopRecoveryTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let crashGuard = EngineCrashGuard(directory: dir.appendingPathComponent("guard"))
        crashGuard.beginCall(engine: TestVoiceProvider.id, chars: 120, article: UUID(), paragraph: 2)
        let tts = LocalTTSCoordinator(
            engines: EngineRegistry(providers: [TestVoiceProvider()], gate: { _ in true }), defaults: defaults,
            audioCache: ArticleAudioCache(root: dir.appendingPathComponent("TTSCache")),
            crashGuard: crashGuard,
            pendingBakes: PendingBakeJobStore(storeURL: dir.appendingPathComponent("PendingBakeJobs.json"), defaults: defaults),
            resumePoints: ListenResumePointStore(url: dir.appendingPathComponent("listen_resume.json")),
            renderPolicy: SingleCallPolicy())
        XCTAssertNotNil(tts.launchCrash)
        XCTAssertTrue(tts.isPausedForRetry)
        XCTAssertTrue(tts.synthQueue.isPausedForRetry)
        XCTAssertEqual(tts.defaultSelection.engine, TestVoiceProvider.id)
        XCTAssertEqual(tts.pendingResume?.paragraph, 2)
    }

    /// Two Kokoro calls died together: it can't say which, so Kokoro's own recovery (one thread
    /// fewer) doesn't run; it pauses for Retry in the same voice.
    @MainActor
    func testAnAmbiguousCrashPausesWithoutSteppingThreadsDown() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("crashambiguous-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let suite = "EngineStopRecoveryTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = KokoroRouteSettings(defaults: defaults)
        settings.cpuThreads = 5
        let crashGuard = EngineCrashGuard(directory: dir.appendingPathComponent("guard"))
        crashGuard.beginCall(engine: .kokoro, chars: 120, route: "onnx", article: UUID(), paragraph: 2)
        crashGuard.beginCall(engine: .kokoro, chars: 90, route: "onnx", article: UUID(), paragraph: 3)
        let tts = LocalTTSCoordinator(
            engines: EngineRegistry(providers: [FluidAudioProvider(routeSettings: settings)], gate: { _ in true }),
            defaults: defaults, audioCache: ArticleAudioCache(root: dir.appendingPathComponent("TTSCache")),
            crashGuard: crashGuard,
            pendingBakes: PendingBakeJobStore(storeURL: dir.appendingPathComponent("PendingBakeJobs.json"), defaults: defaults),
            resumePoints: ListenResumePointStore(url: dir.appendingPathComponent("listen_resume.json")),
            renderPolicy: SingleCallPolicy())
        XCTAssertEqual(tts.launchCrash?.isAmbiguous, true)
        XCTAssertTrue(tts.isPausedForRetry)
        XCTAssertEqual(settings.cpuThreads, 5)
        XCTAssertEqual(settings.onnxCrashCount, 0)
        XCTAssertEqual(tts.defaultSelection.engine, .kokoro)
    }
}
