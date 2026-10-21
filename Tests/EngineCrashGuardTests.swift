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
}


/// C129: a Kokoro stop never switches engine or voice, and an install mid-call isn't a crash.
final class EngineStopRecoveryTests: XCTestCase {
    func testONNXCrashesResumeSilentlyThenPauseNeverApple() {
        var count = 0
        XCTAssertEqual(KokoroCrashRecovery.onCrash(route: .onnxCPU, onnxCrashCount: &count), .resumeOnONNX)
        XCTAssertEqual(KokoroCrashRecovery.onCrash(route: .onnxCPU, onnxCrashCount: &count), .pauseForRetry)
        XCTAssertEqual(count, 0)
        XCTAssertEqual(KokoroCrashRecovery.onCrash(route: .coreMLGPU, onnxCrashCount: &count), .resumeOnONNX)
    }

    func testRecoverStaysOnKokoroWithFewerThreads() {
        let defaults = UserDefaults(suiteName: "EngineStopRecoveryTests")!
        defaults.removePersistentDomain(forName: "EngineStopRecoveryTests")
        let settings = KokoroRouteSettings(defaults: defaults)
        settings.cpuThreads = 5
        let crash = EngineCrashGuard.CrashInfo(engine: .kokoro, route: "onnx", articleKey: nil, paragraph: 3,
                                               phase: "active", at: Date())
        let first = KokoroCrashRecovery.recover(from: crash, playing: nil, settings: settings)
        XCTAssertNil(first.notice, "a same-voice recovery shows no banner")
        guard case .stay = first else { return XCTFail("\(first)") }
        XCTAssertEqual(settings.cpuThreads, 4)
        let second = KokoroCrashRecovery.recover(from: crash, playing: nil, settings: settings)
        guard case .pauseForRetry = second else { return XCTFail("\(second)") }
        XCTAssertEqual(second.notice, KokoroCrashRecovery.pausedNotice)
        XCTAssertFalse(second.notice!.contains("Apple"))
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

    func testKokoroVoiceGender() {
        XCTAssertEqual(VoiceCatalog.gender(ofKokoroVoice: "af_heart"), .female)
        XCTAssertEqual(VoiceCatalog.gender(ofKokoroVoice: "bm_george"), .male)
        XCTAssertNil(VoiceCatalog.gender(ofKokoroVoice: nil))
    }
}
