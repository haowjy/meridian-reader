import XCTest
@testable import Reader

@MainActor
private final class MockRecognizer: DictationRecognizing {
    var permission: DictationPermission = .granted
    var startError: Error?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var onEvent: (@MainActor (DictationEvent) -> Void)?
    /// Holds `requestPermission` until `grant()` (simulates the system prompt).
    var holdPermission = false
    private var permissionContinuation: CheckedContinuation<Void, Never>?

    func requestPermission() async -> DictationPermission {
        if holdPermission {
            await withCheckedContinuation { permissionContinuation = $0 }
        }
        return permission
    }

    func releasePermission() {
        permissionContinuation?.resume()
        permissionContinuation = nil
    }

    func start(onEvent: @escaping @MainActor (DictationEvent) -> Void) throws {
        startCount += 1
        if let startError { throw startError }
        self.onEvent = onEvent
    }

    func stop() { stopCount += 1 }

    func send(_ event: DictationEvent) { onEvent?(event) }
}

@MainActor
private final class MockHandoff: DictationAudioHandoff {
    private(set) var log: [String] = []
    func willStartDictation() { log.append("begin") }
    func didEndDictation() { log.append("end") }
}

/// Address-bar dictation state machine (mock recognizer; no mic, no audio session).
@MainActor
final class AddressDictationTests: XCTestCase {
    private func make(silence: Duration = .seconds(30), noSpeech: Duration = .seconds(30))
        -> (AddressDictation, MockRecognizer, MockHandoff, TextSink) {
        let rec = MockRecognizer()
        let audio = MockHandoff()
        let d = AddressDictation(recognizer: rec, audio: audio, silenceTimeout: silence, noSpeechTimeout: noSpeech)
        let sink = TextSink()
        d.onTranscript = { sink.texts.append($0) }
        return (d, rec, audio, sink)
    }

    private final class TextSink { var texts: [String] = [] }

    private func settle() async {
        for _ in 0..<5 { await Task.yield() }
    }

    func testStreamsPartialsAndStopsOnSecondTap() async {
        let (d, rec, audio, sink) = make()
        d.toggle()
        XCTAssertEqual(d.state, .starting, "reflects the tap immediately")
        await settle()
        XCTAssertEqual(d.state, .listening)
        XCTAssertEqual(audio.log, ["begin"], "Listen hands off before the mic opens")
        XCTAssertEqual(rec.startCount, 1)

        rec.send(.partial("best"))
        rec.send(.partial("best pizza"))
        rec.send(.partial("best pizza")) // duplicate: ignored
        XCTAssertEqual(sink.texts, ["best", "best pizza"])
        XCTAssertEqual(d.transcript, "best pizza")

        d.toggle() // second tap
        XCTAssertEqual(d.state, .idle)
        XCTAssertEqual(rec.stopCount, 1)
        XCTAssertEqual(audio.log, ["begin", "end"], "session handed back exactly once")
        XCTAssertEqual(d.transcript, "best pizza", "keeps what was heard")
        XCTAssertNil(d.errorMessage)

        rec.send(.partial("late words")) // after stop: ignored
        XCTAssertEqual(sink.texts, ["best", "best pizza"])
    }

    func testFinalResultEndsDictation() async {
        let (d, rec, audio, sink) = make()
        d.start()
        await settle()
        rec.send(.partial("weather"))
        rec.send(.final("weather tomorrow"))
        XCTAssertEqual(d.state, .idle)
        XCTAssertEqual(sink.texts.last, "weather tomorrow")
        XCTAssertEqual(audio.log, ["begin", "end"])
    }

    func testStopsAfterSilence() async throws {
        let (d, rec, audio, _) = make(silence: .milliseconds(80))
        d.start()
        await settle()
        rec.send(.partial("hello"))
        XCTAssertEqual(d.state, .listening)
        try await Task.sleep(for: .milliseconds(40))
        rec.send(.partial("hello there")) // new words re-arm the timer
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(d.state, .listening, "timer restarted by new words")
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(d.state, .idle, "stopped on silence")
        XCTAssertEqual(d.transcript, "hello there")
        XCTAssertEqual(audio.log, ["begin", "end"])
        XCTAssertEqual(rec.stopCount, 1)
    }

    func testStopsWhenNothingIsHeard() async throws {
        let (d, _, audio, _) = make(noSpeech: .milliseconds(60))
        d.start()
        await settle()
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(d.state, .idle)
        XCTAssertEqual(audio.log, ["begin", "end"])
        XCTAssertNil(d.errorMessage, "silence is not an error")
    }

    func testPermissionDeniedShowsMessageAndNeverTouchesAudio() async {
        let (d, rec, audio, _) = make()
        rec.permission = .denied("Microphone access is off.")
        d.start()
        await settle()
        XCTAssertEqual(d.state, .idle)
        XCTAssertEqual(d.errorMessage, "Microphone access is off.")
        XCTAssertEqual(rec.startCount, 0)
        XCTAssertEqual(rec.stopCount, 0)
        XCTAssertEqual(audio.log, [], "Listen is not paused when the mic never opens")
    }

    func testCancelWhilePermissionPromptIsUp() async {
        let (d, rec, audio, _) = make()
        rec.holdPermission = true
        d.start()
        await settle()
        XCTAssertEqual(d.state, .starting)
        d.cancel()
        XCTAssertEqual(d.state, .idle)
        rec.releasePermission()
        await settle()
        XCTAssertEqual(d.state, .idle, "late grant doesn't reopen the mic")
        XCTAssertEqual(rec.startCount, 0)
        XCTAssertEqual(audio.log, [])
    }

    func testStartFailureRestoresAudio() async {
        struct Boom: Error {}
        let (d, rec, audio, _) = make()
        rec.startError = Boom()
        d.start()
        await settle()
        XCTAssertEqual(d.state, .idle)
        XCTAssertNotNil(d.errorMessage)
        XCTAssertEqual(audio.log, ["begin", "end"], "session handed back even if the mic failed")
    }

    func testRecognizerErrorAfterWordsIsNotShown() async {
        let (d, rec, _, _) = make()
        d.start()
        await settle()
        rec.send(.partial("news"))
        rec.send(.failed("No speech detected"))
        XCTAssertEqual(d.state, .idle)
        XCTAssertNil(d.errorMessage)
        XCTAssertEqual(d.transcript, "news")
    }

    func testRecentSearches() {
        var list: [String] = []
        list = RecentSearches.adding("swift charts", to: list)
        list = RecentSearches.adding("kokoro tts", to: list)
        list = RecentSearches.adding("Swift Charts", to: list)
        XCTAssertEqual(list, ["Swift Charts", "kokoro tts"], "newest first, case-insensitive dedupe")
        for i in 0..<20 { list = RecentSearches.adding("q\(i)", to: list) }
        XCTAssertEqual(list.count, RecentSearches.maxEntries)
        XCTAssertEqual(RecentSearches.decode(RecentSearches.encode(list)), list)

        XCTAssertTrue(RecentSearches.isSearch("best pizza"))
        XCTAssertFalse(RecentSearches.isSearch("example.com"))
        XCTAssertFalse(RecentSearches.isSearch("https://www.google.com/search?q=x"))
        XCTAssertFalse(RecentSearches.isSearch("   "))
    }
}
