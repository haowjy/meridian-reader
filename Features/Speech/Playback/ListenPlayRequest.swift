import Foundation

/// What the controller asks `LocalListenEngine` to play.
struct ListenPlayRequest {
    var articleID: UUID
    var document: ParagraphDocument
    /// Document UTF-16 offset to start at: a paragraph start, a scrubbed sentence start, or the
    /// word being spoken when an utterance restarts.
    var utf16Offset: Int
    var startPaused: Bool
    /// C138a: the article's engine and voice. Every file the play reads or asks for is in it.
    var selection: VoiceSelection
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
    /// Paragraphs after the playhead already rendered in the current voice (a count, for the
    /// debug panel; the listening time ready ahead is `LocalListenPlayer.readyAheadSeconds`).
    var renderedParagraphsAhead = 0
}
