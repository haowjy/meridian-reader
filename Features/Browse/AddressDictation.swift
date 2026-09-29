import AVFoundation
import Foundation
import Observation
import Speech

// MARK: - Seams (mocked in unit tests)

enum DictationPermission: Equatable {
    case granted
    case denied(String)
}

/// What the recognizer reports (always delivered on the main actor).
enum DictationEvent: Equatable {
    case partial(String)
    case final(String)
    case failed(String)
}

@MainActor
protocol DictationRecognizing: AnyObject {
    /// Microphone + speech recognition permission (prompts the first time).
    func requestPermission() async -> DictationPermission
    /// Starts the mic and recognition. Throws if the mic / recognizer can't start.
    func start(onEvent: @escaping @MainActor (DictationEvent) -> Void) throws
    /// Stops the mic and recognition. Late events after this are ignored by the caller.
    func stop()
}

/// Audio-session hand-off around a dictation: Listen pauses before the mic opens and gets its
/// session (and playback, if it was playing) back after the mic closes.
@MainActor
protocol DictationAudioHandoff: AnyObject {
    func willStartDictation()
    func didEndDictation()
}

enum DictationState: Equatable {
    case idle
    /// Asking for permission / opening the mic.
    case starting
    case listening
}

// MARK: - State machine

/// Address-bar dictation. Streams partial transcripts through `onTranscript`, stops on a second
/// tap, on silence (`silenceTimeout` after the last new words; `noSpeechTimeout` if nothing was
/// heard), on a final result, or on `cancel()`.
@MainActor
@Observable
final class AddressDictation {
    private(set) var state: DictationState = .idle
    private(set) var transcript = ""
    /// Permission / availability problem to show the user (nil when fine).
    var errorMessage: String?
    /// Streaming text for the field.
    @ObservationIgnored var onTranscript: ((String) -> Void)?

    var isActive: Bool { state != .idle }
    var isListening: Bool { state == .listening }

    @ObservationIgnored private let recognizer: DictationRecognizing
    @ObservationIgnored private let audio: DictationAudioHandoff?
    @ObservationIgnored private let silenceTimeout: Duration
    @ObservationIgnored private let noSpeechTimeout: Duration
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var audioHandedOff = false
    @ObservationIgnored private var silenceTask: Task<Void, Never>?

    init(recognizer: DictationRecognizing,
         audio: DictationAudioHandoff?,
         silenceTimeout: Duration = .milliseconds(1600),
         noSpeechTimeout: Duration = .seconds(6)) {
        self.recognizer = recognizer
        self.audio = audio
        self.silenceTimeout = silenceTimeout
        self.noSpeechTimeout = noSpeechTimeout
    }

    /// Mic button: start if idle, otherwise stop (keeping what was heard).
    func toggle() {
        if state == .idle { start() } else { stop() }
    }

    /// Enters `.starting` synchronously, so the UI reflects the tap immediately.
    func start() {
        guard state == .idle else { return }
        generation += 1
        let gen = generation
        errorMessage = nil
        transcript = ""
        state = .starting
        Task { await self.begin(gen) }
    }

    /// Second tap / silence: stop listening and keep the transcript in the field.
    func stop() { finish(error: nil) }

    /// Cancel editing: stop listening (the caller restores the field).
    func cancel() { finish(error: nil) }

    private func begin(_ gen: Int) async {
        let permission = await recognizer.requestPermission()
        guard gen == generation, state == .starting else { return } // cancelled meanwhile
        if case .denied(let message) = permission {
            finish(error: message)
            return
        }
        audio?.willStartDictation()
        audioHandedOff = true
        do {
            try recognizer.start { [weak self] event in self?.handle(event, gen: gen) }
            state = .listening
            armSilenceTimer(noSpeechTimeout, gen: gen)
        } catch {
            finish(error: "Dictation couldn’t start: \(error.localizedDescription)")
        }
    }

    private func handle(_ event: DictationEvent, gen: Int) {
        guard gen == generation, state == .listening else { return }
        switch event {
        case .partial(let text):
            guard text != transcript else { return }
            transcript = text
            onTranscript?(text)
            armSilenceTimer(silenceTimeout, gen: gen)
        case .final(let text):
            if text != transcript {
                transcript = text
                onTranscript?(text)
            }
            finish(error: nil)
        case .failed(let message):
            // "No speech detected" etc. after words were heard is just the end of the utterance.
            finish(error: transcript.isEmpty ? message : nil)
        }
    }

    private func armSilenceTimer(_ timeout: Duration, gen: Int) {
        silenceTask?.cancel()
        silenceTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, let self, gen == self.generation else { return }
            self.stop()
        }
    }

    private func finish(error: String?) {
        guard state != .idle else { return }
        generation += 1 // late recognizer events / timers are now stale
        silenceTask?.cancel()
        silenceTask = nil
        let wasHandedOff = audioHandedOff
        audioHandedOff = false
        if wasHandedOff {
            recognizer.stop()
            audio?.didEndDictation()
        }
        state = .idle
        if let error { errorMessage = error }
    }
}

// MARK: - Listen hand-off

/// Pauses Listen while the mic is open, then restores its `.playback`/`.spokenAudio` session and
/// resumes it if it was playing. If Listen wasn't holding the session, the session is released
/// (notifying others, so music can resume).
@MainActor
final class ListenDictationHandoff: DictationAudioHandoff {
    private weak var speech: SpeechController?
    private(set) var resumeListenAfterDictation = false

    init(speech: SpeechController) { self.speech = speech }

    func willStartDictation() {
        guard let speech else { return }
        resumeListenAfterDictation = speech.isPlaying
        if resumeListenAfterDictation { speech.pause() }
    }

    func didEndDictation() {
        guard let speech else { return }
        let session = speech.audioSession
        session.configure() // back to Listen's category after the recorder's
        if resumeListenAfterDictation {
            speech.resume()
        } else if !session.isActive, session.managesSystemSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        resumeListenAfterDictation = false
    }
}

// MARK: - On-device recognizer

/// `SFSpeechRecognizer` fed from the mic, on-device when the locale supports it.
@MainActor
final class SystemDictationRecognizer: DictationRecognizing {
    private let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer()
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var tapInstalled = false

    func requestPermission() async -> DictationPermission {
        let speechStatus: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard speechStatus == .authorized else {
            return .denied("Speech recognition is off for Reader. You can turn it on in Settings › Reader.")
        }
        let micGranted = await AVAudioApplication.requestRecordPermission()
        guard micGranted else {
            return .denied("Microphone access is off for Reader. You can turn it on in Settings › Reader.")
        }
        guard let recognizer, recognizer.isAvailable else {
            return .denied("Dictation isn’t available for your language right now.")
        }
        return .granted
    }

    func start(onEvent: @escaping @MainActor (DictationEvent) -> Void) throws {
        guard let recognizer else { throw DictationError.unavailable }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setActive(true)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .search
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw DictationError.noMicrophone }
        Self.installTap(on: input, format: format, request: request)
        tapInstalled = true
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            tapInstalled = false
            throw error
        }
        self.request = request
        task = Self.recognitionTask(recognizer, request: request, onEvent: onEvent)
    }

    func stop() {
        if engine.isRunning { engine.stop() }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }

    // Built outside the main actor: these callbacks run on audio / recognizer queues.
    private nonisolated static func installTap(on input: AVAudioInputNode, format: AVAudioFormat,
                                               request: SFSpeechAudioBufferRecognitionRequest) {
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    private nonisolated static func recognitionTask(
        _ recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        onEvent: @escaping @MainActor (DictationEvent) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            let event: DictationEvent?
            if let result {
                let text = result.bestTranscription.formattedString
                event = result.isFinal ? .final(text) : .partial(text)
            } else if let error {
                event = .failed(error.localizedDescription)
            } else {
                event = nil
            }
            guard let event else { return }
            Task { @MainActor in onEvent(event) }
        }
    }

    enum DictationError: LocalizedError {
        case unavailable, noMicrophone
        var errorDescription: String? {
            switch self {
            case .unavailable: return "Speech recognition isn’t available."
            case .noMicrophone: return "No microphone input."
            }
        }
    }
}
