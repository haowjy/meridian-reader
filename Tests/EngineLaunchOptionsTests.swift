import XCTest
@testable import MeridianReader

/// The engine and diagnostics launch arguments, all parsed by `LaunchOptions`.
final class EngineLaunchOptionsTests: XCTestCase {
    func testEngineArguments() {
        let none = LaunchOptions(arguments: ["Reader"])
        XCTAssertNil(none.selectsEngine)
        XCTAssertNil(none.engineProbe)
        XCTAssertNil(none.kokoroStress)

        let all = LaunchOptions(arguments: [
            "Reader", "-uiTesting", "-selectEngine", "test.voice", "-kokoroUnits", "cpuOnly",
            "-engineProbe", "-probeOnly", "Kokoro,Test Voice", "-probeStress",
            "-KokoroStress", "CoreML", "-KokoroStressCalls", "0", "-KokoroStressFresh",
        ])
        XCTAssertEqual(all.selectsEngine, TestVoiceProvider.id)
        XCTAssertEqual(all.kokoroUnits, "cpuOnly")
        XCTAssertEqual(all.engineProbe, .init(engines: ["kokoro", "test voice"], stressCalls: 20))
        XCTAssertEqual(all.kokoroStress, .init(route: .coreml, calls: 1, fresh: true))
        XCTAssertEqual(LaunchOptions(arguments: ["-engineProbe", "-probeStress", "-probeStressN", "5"]).engineProbe?.stressCalls, 5)
        XCTAssertNil(LaunchOptions(arguments: ["-KokoroStress", "gpu"]).kokoroStress, "unknown route")
    }
}
