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
        let synth = LocalSynthService(engines: registry)
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
}
