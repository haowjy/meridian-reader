import Foundation
@testable import Reader

/// Scripted `ListenEngine` (stands in for Apple's synthesizer): records commands and confirms
/// pause / resume at once, as an engine that holds its audio immediately would; the test emits the
/// other events (position, finished) a real engine would.
@MainActor
final class FakeListenEngine: ListenEngine {
    let name: String
    var onEvent: ((PlaybackEngineEvent) -> Void)?
    private(set) var plays: [ListenPlayRequest] = []
    private(set) var pauseCount = 0
    private(set) var resumeCount = 0
    private(set) var stopCount = 0
    private(set) var rate = 1.0
    private var speaking = false
    private var paused = false

    init(name: String = "Apple") { self.name = name }

    func play(_ request: ListenPlayRequest) {
        plays.append(request)
        speaking = !request.startPaused
        paused = false
    }

    func pause() {
        pauseCount += 1
        guard speaking else { return }
        paused = true
        onEvent?(.becamePaused)
    }

    func resume() {
        resumeCount += 1
        guard paused else { return }
        paused = false
        onEvent?(.becameAudible)
    }

    func stop() {
        stopCount += 1
        speaking = false
        paused = false
    }

    func setRate(_ multiplier: Double) { rate = multiplier }

    var snapshot: PlaybackEngineSnapshot { PlaybackEngineSnapshot(isAudible: speaking && !paused, isPaused: paused) }
    var isWaitingForAudio: Bool { false }
    var sourceNote: String? { nil }
    func appDidBecomeActive() {}
    var debug: ListenEngineDebug { ListenEngineDebug(isSpeaking: speaking, isPaused: paused) }

    func emit(_ event: PlaybackEngineEvent) {
        if event == .finished { speaking = false }
        onEvent?(event)
    }
}
