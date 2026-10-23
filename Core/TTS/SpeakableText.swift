import Foundation

/// Lightweight builder for listen-path speakable text.
///
/// Pipeline: `prepare` → `normalize` (shared) → `grammar` (Kokoro only) → `split` (engine Limits).
/// Displayed reader HTML is untouched — this is synth prep only.
struct SpeakableText: Sendable {
    private var text: String
    private var grammarKind: SpeakableGrammar = .none

    private init(text: String, grammarKind: SpeakableGrammar = .none) {
        self.text = text
        self.grammarKind = grammarKind
    }

    static func prepare(_ paragraph: String) -> SpeakableText {
        SpeakableText(text: paragraph)
    }

    /// Shared meaning-preserving cleanup (`TTSTextNormalize`).
    func normalize() -> SpeakableText {
        SpeakableText(text: TTSTextNormalize.normalize(text), grammarKind: grammarKind)
    }

    /// Kokoro-only paragraph grammar; no-op for `.none` (Phonon / Apple).
    func grammar(_ kind: SpeakableGrammar) -> SpeakableText {
        let next: String
        switch kind {
        case .none:
            next = text
        case .kokoro:
            next = KokoroGrammar.prepareParagraph(text)
        }
        return SpeakableText(text: next, grammarKind: kind)
    }

    /// Current speakable string (after normalize / grammar so far).
    var value: String { text }

    /// Synth chunks for the engine's Limits. Input should already be normalized (and grammar
    /// applied when needed). Does not re-normalize.
    func split(limits: TextChunker.Limits) -> [String] {
        TextChunker.chunks(forNormalized: text, limits: limits)
    }
}
