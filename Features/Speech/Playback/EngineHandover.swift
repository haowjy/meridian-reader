import Foundation

/// The engine a live utterance speaks with. `SpeechController.speak` picks it once and every
/// command (pause, resume, snapshot, stop) goes to it until stop or the next `speak`.
enum ListenRoute: Equatable {
    case apple
    /// An on-device engine and its voice: a voice change makes the buffered audio stale.
    case local(SpeechEngineID, voice: String?)
}

/// What happens to the live utterance when the engine `speak` would pick now (`wanted`) is not the
/// one it is bound to — e.g. the on-device engine finished loading, or the user picked Apple.
enum EngineHandover: Equatable {
    /// Keep going on the bound engine.
    case none
    /// Re-speak from the playhead on `wanted` now (paused stays paused).
    case restartNow
    /// Apple keeps speaking the paragraph it is in; the next paragraph starts on `wanted`.
    case atNextParagraph

    /// Apple audible mid-paragraph hands over at the next paragraph start, so the voice never
    /// changes mid-sentence and Apple is never left speaking unowned. Paused Apple has nothing
    /// audible to protect. A bound on-device engine always restarts: its host is unloaded, loading
    /// again, or now speaks another voice, so its buffered audio can't continue.
    static func decide(bound: ListenRoute, wanted: ListenRoute, phase: PlaybackPhase) -> EngineHandover {
        guard bound != wanted else { return .none }
        if bound == .apple, phase == .playing { return .atNextParagraph }
        return .restartNow
    }
}
