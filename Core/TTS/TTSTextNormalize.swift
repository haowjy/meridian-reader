import Foundation

/// Shared light cleanup before synth (any on-device engine).
/// Whitespace collapse only — pause rewriting removed for now; engines own text
/// normalization (Kokoro via NeMo, Phonon via Gradium). Does not change displayed
/// reader HTML — listen path only.
enum TTSTextNormalize {
    /// Collapse whitespace runs (incl. newlines / NBSP) to one space and trim.
    /// Em/aside dashes and semicolons pass through unchanged; engine TN decides pauses.
    static func normalize(_ text: String) -> String {
        var s = text.replacingOccurrences(of: "\u{00A0}", with: " ")
        s = s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return s.trimmingCharacters(in: .whitespaces)
    }
}
