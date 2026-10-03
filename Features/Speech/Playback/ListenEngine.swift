import AVFoundation
import Foundation

/// One way of producing Listen audio: Apple's synthesizer or an on-device engine's file player.
/// `SpeechController.speak` binds one per utterance (`ListenRoute`) and sends it every command until
/// stop or the next `speak`. Engines report what happened through `onEvent` — audible, paused, the
/// spot being spoken, finished — and never change the session themselves; the session moves only
/// on those reports. See docs/LISTEN_PLAYBACK.md.
@MainActor
protocol ListenEngine: AnyObject {
    /// Diagnostics / timing-log name ("Apple", "Kokoro").
    var name: String { get }
    /// Facts for the session (audible, paused, position, status, finished). Set once by the controller.
    var onEvent: ((PlaybackEngineEvent) -> Void)? { get set }

    /// Start at `request.utf16Offset`. Paused: take the spot without sounding; `resume` or a new
    /// `play` sounds it.
    func play(_ request: ListenPlayRequest)
    /// Confirmed with `becamePaused` once the audio holds.
    func pause()
    /// Continue what `pause` held (no-op when nothing is held).
    func resume()
    func stop()
    /// Listen speed multiplier (1 = normal). A setting every engine keeps, bound or not; what is
    /// playing changes speed in place where the engine can, else from the word being spoken.
    func setRate(_ multiplier: Double)

    var snapshot: PlaybackEngineSnapshot { get }
    /// Playing, nothing audible, and more audio is on its way ("Preparing next…").
    var isWaitingForAudio: Bool { get }
    /// Listen-bar note about where the audio playing now comes from (nil: the engine's own voice).
    var sourceNote: String? { get }
    /// Back in the foreground (the on-device engine re-renders audio it had to defer).
    func appDidBecomeActive()
    /// Engine-side numbers for the Listen debug panel.
    var debug: ListenEngineDebug { get }
}

/// What the controller asks the bound engine to play.
struct ListenPlayRequest {
    var articleID: UUID
    var document: ParagraphDocument
    /// Document UTF-16 offset to start at: a paragraph start, a scrubbed sentence start, or the
    /// word being spoken when an utterance restarts.
    var utf16Offset: Int
    var startPaused: Bool
    /// The Apple voice for this article's language (Apple speech, and the on-device engine's
    /// Apple fallback renders).
    var appleVoice: AVSpeechSynthesisVoice?
}

/// Engine-side fields of `ListenDebugSnapshot`.
struct ListenEngineDebug {
    var isSpeaking = false
    var isPaused = false
    var bufferedCount = 0
    var awaitingMore = false
    var producerActive = false
    var epoch = 0
    var currentCAF = "—"
    var secondsSinceEnqueue: Double?
    var lastHandoffGapMs: Double = 0
    var lastHandoffWasPrimed = false
    var starveEventCount = 0
    /// How audio is produced right now (route, app phase).
    var renderMode = ""
    /// Paragraphs after the playhead already rendered in the current voice.
    var readyAhead = 0
}
