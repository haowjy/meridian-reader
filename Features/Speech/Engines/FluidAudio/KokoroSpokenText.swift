import Foundation

/// Kokoro-only spoken-text tweaks applied at render (not at plan time).
///
/// Closing a mid-sentence chunk that ends on a bare word with a comma lets Kokoro release the
/// last phoneme instead of clipping (C137). Join pause still comes from `ChunkEdgeTrim` on the
/// renderer. Must not change letters or digits — planned chunk text still reassembles to
/// `TTSTextNormalize.normalize(paragraph)` for SubParagraphPosition / cache invariants.
enum KokoroSpokenText {
    static func closeOpenEnd(_ text: String) -> String {
        guard let last = text.last, last.isLetter || last.isNumber else { return text }
        return text + ","
    }
}
