import Foundation

/// The engine a live utterance speaks with, from the article's `VoiceSelection` (C138a).
/// `SpeechController.speak` picks it once and every command (pause, resume, snapshot, stop) goes
/// to it until stop or the next `speak`. Nothing moves a live utterance to another engine.
enum ListenRoute: Equatable {
    /// The article speaks in an Apple voice (empty: the best for its language).
    case apple(voice: String)
    /// The article speaks in an on-device engine's voice.
    case local(VoiceSelection)
    /// Decision D9, an explicit and unsaved exception: in the background, on a route that can't
    /// render there, Apple speaks a chapter until the app is in front again. Nothing is stored.
    case appleStandIn
}
