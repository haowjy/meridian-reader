import Foundation

/// Kokoro-only speakable tweaks. Phonon and Apple skip this step.
///
/// Paragraph-level rules run in `SpeakableText.grammar(.kokoro)` before split.
/// Per-chunk open-end closing runs at render (`prepareChunk`) so planned chunk text still
/// reassembles to normalize(paragraph) for SubParagraphPosition / cache invariants.
enum KokoroGrammar {
    /// Paragraph-level Kokoro rewrites after shared normalize. Identity today — hook for
    /// Kokoro-only prosody/number wording that must not apply to Phonon.
    static func prepareParagraph(_ text: String) -> String { text }

    /// Close a mid-sentence chunk that ends on a bare word with a comma so Kokoro releases the
    /// last phoneme instead of clipping (C137). Join pause still comes from `ChunkEdgeTrim`.
    static func prepareChunk(_ text: String) -> String {
        guard let last = text.last, last.isLetter || last.isNumber else { return text }
        return text + ","
    }
}

/// Which speakable-grammar pass `SpeakableText.grammar` applies.
enum SpeakableGrammar: Equatable, Sendable {
    case none
    case kokoro
}
