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
