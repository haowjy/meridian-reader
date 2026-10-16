import XCTest
@testable import MeridianReader

/// The on-device model side: one host's models resident at a time.
@MainActor
final class LocalSynthServiceTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("LocalSynthService-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    /// A route or thread change rebuilds the host while the worker is mid-call: the old host's
    /// session goes (after that call) before the new host builds one.
    func testAReloadDuringARenderNeverHoldsTwoSessions() async throws {
        let sessions = FakeSessionCount()
        let provider = FakeEngineProvider(config: .init(latency: 0.4, sessions: sessions))
        let registry = EngineRegistry(providers: [AppleSpeechProvider(), provider], gate: { _ in true })
        let synth = LocalSynthService(engines: registry, crashGuard: EngineCrashGuard(directory: root.appendingPathComponent("guard")))
        await synth.load(FakeEngineProvider.fakeID, voice: nil).value
        let firstHost = try XCTUnwrap(provider.lastHost)

        let render = Task {
            try await synth.renderChunkToFile(text: "A sentence for the worker to render.",
                                              destination: root.appendingPathComponent("c.caf"),
                                              request: ChunkRenderRequest(chunk: 0))
        }
        while firstHost.startedCalls == 0 { try await Task.sleep(for: .milliseconds(10)) }
        await synth.reload(FakeEngineProvider.fakeID, voice: nil).value
        _ = try await render.value

        XCTAssertEqual(synth.state, .ready(FakeEngineProvider.fakeID))
        XCTAssertFalse(provider.lastHost === firstHost, "the reload built a new host")
        XCTAssertEqual(firstHost.calls.map(\.ok), [true], "the call in flight finished")
        XCTAssertEqual(sessions.peak, 1)
    }

    /// A guarded engine's call leaves its in-flight marker in the coordinator's crash guard, the
    /// one the next launch reads to tell whether the engine killed the process.
    func testAGuardedCallIsMarkedInTheCoordinatorsCrashGuard() async throws {
        let provider = FakeEngineProvider(config: .init(latency: 0.4))
        provider.crashNotice = "test"
        let stack = TestSpeech(providers: [provider])
        defer { stack.tearDown() }
        let tts = stack.tts
        await tts.selectEngine(FakeEngineProvider.fakeID)
        let host = try XCTUnwrap(provider.lastHost)
        let marker = stack.guardDirectory.appending(path: "engine_inflight.json")

        let render = Task {
            try await tts.synth.renderChunkToFile(text: "A sentence for the engine to render.",
                                                  destination: root.appendingPathComponent("c.caf"),
                                                  request: ChunkRenderRequest(chunk: 0))
        }
        while host.startedCalls == 0 { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path), "marked while the call runs")
        _ = try await render.value
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), "cleared when it returns")
    }

    /// The engine probe, the stress run and the CPU bench load models of their own: the app's
    /// host goes first and the queue holds, then both come back.
    func testRenderingQuietLetsTheHostGoUntilTheWorkEnds() async {
        let sessions = FakeSessionCount()
        let stack = TestSpeech(providers: [FakeEngineProvider(config: .init(sessions: sessions))])
        defer { stack.tearDown() }
        let tts = stack.tts
        await tts.selectEngine(FakeEngineProvider.fakeID)
        XCTAssertEqual(sessions.live, 1)

        var duringWork: (sessions: Int, paused: Bool)?
        await tts.withRenderingQuiet {
            duringWork = (sessions.live, tts.synthQueue.isPausedForProbe)
        }
        XCTAssertEqual(duringWork?.sessions, 0, "the app's host had gone")
        XCTAssertEqual(duringWork?.paused, true)
        XCTAssertFalse(tts.synthQueue.isPausedForProbe)
        XCTAssertTrue(tts.usesLocalEngine, "the engine stays selected; the next render loads it")
    }
}
