import Foundation
@testable import MeridianReader

/// `ListenUnitSource` for player tests: every paragraph is rendered as `rendered` (nil: nothing
/// rendered, and every chunk fails as an engine error), one chunk per paragraph, an idle worker.
/// `prepare` can be held open with a gate (a model load in flight).
@MainActor
final class FakeUnitSource: ListenUnitSource {
    struct EngineFailure: LocalizedError { var errorDescription: String? { "fake engine failure" } }

    let articleID = UUID()
    let paragraphs: [String]
    let engineName = "Fake"
    var rendersInBackground = false
    private let rendered: URL?
    private let prepareGate: TestGate?
    /// Texts rendered with Apple, in order.
    private(set) var appleRenders: [String] = []
    private(set) var focused: [Int] = []

    init(paragraphs: [String], rendered: URL?, prepareGate: TestGate? = nil) {
        self.paragraphs = paragraphs
        self.rendered = rendered
        self.prepareGate = prepareGate
    }

    func prepare() async throws {
        if let prepareGate { await prepareGate.wait() }
    }

    func renderedParagraph(_ paragraph: Int) -> RenderedParagraph? {
        rendered.map { RenderedParagraph(url: $0, chunkDurations: nil) }
    }

    func chunks(paragraph: Int) -> [String] { [paragraphs[paragraph]] }
    func chunkDurations(paragraph: Int) -> [TimeInterval]? { nil }

    func chunk(paragraph: Int, chunk: Int) async throws -> GlobalSynthQueue.ChunkResolution {
        guard let rendered else { throw EngineFailure() }
        return .paragraph(rendered, startTime: 0)
    }

    func isChunkReady(paragraph: Int, chunk: Int) -> Bool { rendered != nil }
    func workerStatus(paragraph: Int) -> RenderWorkerStatus { .idle }

    func renderApple(_ text: String, to destination: URL) async throws {
        appleRenders.append(text)
        try LocalPCMWriter.write(FakeSynthHost.tone(seconds: 30, sampleRate: 24_000), sampleRate: 24_000, to: destination)
    }

    func focus(paragraph: Int) { focused.append(paragraph) }
}

/// An async latch: `wait()` suspends until `open()`; `waiting` counts the callers held so far.
actor TestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var waiting = 0

    func wait() async {
        guard !isOpen else { return }
        waiting += 1
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}
