import Foundation

/// C138a: the one voice an article (or a book) speaks in: an engine and one of its voices,
/// together. The single source of truth for what plays, renders, prepares and is looked up in
/// the audio cache. Resolved once per article (its own, else its book's, else, for a brand-new
/// article, the Settings default) and passed explicitly; nothing in playback or rendering reads a
/// global engine or voice.
///
/// Stored as `"<engine id>/<voice id>"` ("local.kokoro/af_heart", "apple/com.apple.voice.premium.en-US.Ava";
/// an empty voice id for Apple is the system voice for the article's language).
struct VoiceSelection: Hashable, Sendable, CustomStringConvertible {
    let engine: SpeechEngineID
    let voice: String

    init(engine: SpeechEngineID, voice: String) {
        self.engine = engine
        self.voice = voice
    }

    /// From its stored form; nil for anything else.
    init?(stored: String) {
        guard let slash = stored.firstIndex(of: "/") else { return nil }
        let engine = String(stored[..<slash])
        guard !engine.isEmpty else { return nil }
        self.engine = SpeechEngineID(engine)
        self.voice = String(stored[stored.index(after: slash)...])
    }

    var stored: String { "\(engine.rawValue)/\(voice)" }
    var description: String { stored }
    var isApple: Bool { engine == .apple }
}
