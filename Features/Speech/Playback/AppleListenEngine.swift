import AVFoundation
import Foundation

/// Listen through `AVSpeechSynthesizer`: one utterance holding the rest of the article from the
/// start offset. The delegate reports audible / paused (`didStart`, `didContinue`, `didPause`) and
/// the word being spoken (`willSpeakRange`), so no polling. Callbacks
/// count only for the utterance this engine spoke last and hasn't stopped: a stopped or replaced
/// utterance's late `didFinish` / `willSpeakRange` is dropped, so `didFinish` of the live one is
/// the end of the article.
@MainActor
final class AppleListenEngine: NSObject, ListenEngine, AVSpeechSynthesizerDelegate {
    let name = "Apple"
    var onEvent: ((PlaybackEngineEvent) -> Void)?
    /// The render queue's run state (the debug panel's app phase).
    private let runState: AppRunState

    /// Replaced after a media-services reset (`mediaServicesWereReset`).
    nonisolated(unsafe) private var synthesizer = AVSpeechSynthesizer()
    private var request: ListenPlayRequest?
    /// The utterance speaking or paused now (nil: stopped, or a paused `play` holding nothing).
    private(set) var utterance: AVSpeechUtterance?
    /// Document offset where the current utterance's text begins.
    private var utteranceBaseOffset = 0
    /// Document offset of the word being spoken (restart point for a speed change).
    private var spokenOffset = 0
    private var rate = 1.0

    init(runState: AppRunState = .shared) {
        self.runState = runState
        super.init()
        synthesizer.delegate = self
    }

    func play(_ request: ListenPlayRequest) {
        stop()
        self.request = request
        utteranceBaseOffset = request.utf16Offset
        spokenOffset = request.utf16Offset
        if !request.startPaused {
            let text = (request.document.joinedText as NSString).substring(from: request.utf16Offset)
            let utterance = AVSpeechUtterance(string: text)
            utterance.rate = Float(AVSpeechUtteranceDefaultSpeechRate) * Float(rate)
            if let voice = request.appleVoice { utterance.voice = voice }
            self.utterance = utterance
            synthesizer.speak(utterance)
        }
        // Paused: hold nothing. `speak` + an immediate `pauseSpeaking` doesn't stick (the utterance
        // hasn't started, so it speaks anyway); Resume finds nothing held and plays the playhead.
    }

    func pause() {
        if synthesizer.isSpeaking, !synthesizer.isPaused {
            synthesizer.pauseSpeaking(at: .word)
        }
    }

    func resume() {
        if synthesizer.isPaused { synthesizer.continueSpeaking() }
    }

    func stop() {
        utterance = nil
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    /// An utterance's rate is fixed once spoken: re-speak from the word being spoken (a paused
    /// utterance is dropped, and Resume plays from the playhead at the new speed).
    func setRate(_ multiplier: Double) {
        guard multiplier != rate else { return }
        rate = multiplier
        guard var restart = request, utterance != nil else { return }
        restart.utf16Offset = spokenOffset
        restart.startPaused = synthesizer.isPaused
        play(restart)
    }

    var snapshot: PlaybackEngineSnapshot {
        PlaybackEngineSnapshot(isAudible: synthesizer.isSpeaking && !synthesizer.isPaused,
                               isPaused: synthesizer.isPaused)
    }

    var isWaitingForAudio: Bool { false }
    var sourceNote: String? { nil }
    func appDidBecomeActive() {}

    func mediaServicesWereReset() {
        stop()
        synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
    }

    var debug: ListenEngineDebug {
        ListenEngineDebug(isSpeaking: synthesizer.isSpeaking, isPaused: synthesizer.isPaused,
                          renderMode: "Apple TTS (AVSpeechSynthesizer) · \(runState.phase.rawValue)")
    }

    // MARK: - AVSpeechSynthesizerDelegate

    /// Runs `body` on the main actor if `utterance` is still the live one.
    nonisolated private func live(_ utterance: AVSpeechUtterance, _ body: @escaping @MainActor (AppleListenEngine) -> Void) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in
            guard let current = self.utterance, ObjectIdentifier(current) == id else { return }
            body(self)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        live(utterance) { $0.onEvent?(.becameAudible) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        live(utterance) { $0.onEvent?(.becamePaused) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        live(utterance) { $0.onEvent?(.becameAudible) }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        live(utterance) { engine in
            guard let document = engine.request?.document else { return }
            let utf16 = engine.utteranceBaseOffset + characterRange.location
            engine.spokenOffset = utf16
            let paragraph = document.isEmpty ? 0 : document.index(containingUTF16Offset: utf16)
            engine.onEvent?(.position(paragraph: paragraph, utf16: utf16))
        }
    }

    /// The live utterance holds the rest of the article, so its finish is the article's end.
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        live(utterance) { engine in
            engine.utterance = nil
            engine.onEvent?(.finished)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {}
}
