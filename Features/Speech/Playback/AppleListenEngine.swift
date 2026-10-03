import AVFoundation
import Foundation

/// Listen through `AVSpeechSynthesizer`: one utterance holding the rest of the article from the
/// start offset. Progress comes from the delegate (`willSpeakRange`), so no polling.
@MainActor
final class AppleListenEngine: NSObject, ListenEngine, AVSpeechSynthesizerDelegate {
    let name = "Apple"
    var onEvent: ((PlaybackEngineEvent) -> Void)?

    nonisolated(unsafe) private let synthesizer = AVSpeechSynthesizer()
    private var request: ListenPlayRequest?
    /// Document offset where the current utterance's text begins.
    private var utteranceBaseOffset = 0
    /// Document offset of the word being spoken (restart point for a speed change).
    private var spokenOffset = 0
    private var rate = 1.0
    /// Set while an utterance is being replaced, so the replaced one's finish isn't taken for the
    /// end of the article.
    private var suppressCancelSideEffects = false
    private var playGeneration = 0

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func play(_ request: ListenPlayRequest) {
        playGeneration += 1
        let generation = playGeneration
        suppressCancelSideEffects = true
        stop()
        self.request = request
        utteranceBaseOffset = request.utf16Offset
        spokenOffset = request.utf16Offset
        if !request.startPaused {
            let text = (request.document.joinedText as NSString).substring(from: request.utf16Offset)
            let utterance = AVSpeechUtterance(string: text)
            utterance.rate = Float(AVSpeechUtteranceDefaultSpeechRate) * Float(rate)
            if let voice = request.appleVoice { utterance.voice = voice }
            synthesizer.speak(utterance)
        }
        // Paused: hold nothing. `speak` + an immediate `pauseSpeaking` doesn't stick (the utterance
        // hasn't started, so it speaks anyway); Resume finds nothing held and plays the playhead.
        DispatchQueue.main.async { [weak self] in
            guard let self, generation == self.playGeneration else { return }
            self.suppressCancelSideEffects = false
        }
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
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    /// An utterance's rate is fixed once spoken: re-speak from the word being spoken (a paused
    /// utterance is dropped, and Resume plays from the playhead at the new speed).
    func setRate(_ multiplier: Double) {
        guard multiplier != rate else { return }
        rate = multiplier
        guard var restart = request, synthesizer.isSpeaking || synthesizer.isPaused else { return }
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
    var needsPlaybackPolling: Bool { false }
    func estimatedPosition() -> (paragraph: Int, utf16Offset: Int)? { nil }
    func appDidBecomeActive() {}

    var debug: ListenEngineDebug {
        ListenEngineDebug(isSpeaking: synthesizer.isSpeaking, isPaused: synthesizer.isPaused,
                          renderMode: "Apple TTS (AVSpeechSynthesizer) · \(AppRunState.shared.phase.rawValue)")
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.onEvent?(.becameAudible) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        Task { @MainActor in self.onEvent?(.becamePaused) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        Task { @MainActor in self.onEvent?(.becameAudible) }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            guard let document = self.request?.document else { return }
            let utf16 = self.utteranceBaseOffset + characterRange.location
            self.spokenOffset = utf16
            let paragraph = document.isEmpty ? 0 : document.index(containingUTF16Offset: utf16)
            self.onEvent?(.playheadAdvanced(paragraph: paragraph, utf16Offset: utf16))
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard !self.suppressCancelSideEffects else { return }
            guard !self.synthesizer.isSpeaking, !self.synthesizer.isPaused else { return }
            let length = ((self.request?.document.joinedText ?? "") as NSString).length
            guard length == 0 || self.spokenOffset >= max(0, length - 8) else { return }
            self.onEvent?(.finished)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {}
}
