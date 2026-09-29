import Foundation

/// Controls the silence at chunk joins.
///
/// Kokoro (ONNX) pads every call with ≈320 ms of leading and ≈500 ms of trailing silence, so each
/// join between two chunks was ≈0.8 s of dead air — even where the text was cut mid-sentence at a
/// comma (natural pause there ≈0.2–0.4 s). Measured on The Forgotten p6, 2026-09-25: 18 joins,
/// lead 290–380 ms, trail 410–620 ms. This trims each chunk to a short lead-in and a trailing
/// pause that matches the text boundary, so joins sound like Kokoro's own in-chunk pauses
/// (sentence ≈0.35–0.6 s, comma ≈0.2–0.4 s). Pure; unit-tested.
enum ChunkEdgeTrim {
    enum Boundary: String, Equatable {
        case paragraphEnd, sentence, clause, word
    }

    /// Silence kept before the first voiced frame.
    static let leadMs = 40
    /// Voiced = 10 ms frame RMS above this (Kokoro's silence floor is ≈0.0005 after gain).
    static let threshold: Float = 0.003
    static let frameMs = 10
    static let fadeMs = 5

    /// Trailing silence kept after the last voiced frame (the join pause ≈ this + `leadMs`).
    static func trailMs(_ b: Boundary) -> Int {
        switch b {
        case .paragraphEnd: return 520
        case .sentence: return 360
        case .clause: return 180
        case .word: return 40
        }
    }

    /// What kind of cut follows this chunk's text.
    /// `nextWord`: first word of the following chunk — a cut before a conjunction ("…toilet
    /// paper | and canned food") is a clause join and gets the clause pause.
    static func boundary(after text: String, nextWord: String? = nil, isLastInParagraph: Bool) -> Boundary {
        if isLastInParagraph { return .paragraphEnd }
        let closers: Set<Character> = ["\"", "'", "”", "’", ")", "]", "»"]
        var tail = Substring(text.trimmingCharacters(in: .whitespaces))
        while let c = tail.last, closers.contains(c) { tail = tail.dropLast() }
        guard let last = tail.last else { return .word }
        if ".!?…".contains(last) { return .sentence }
        if ",;:—–-".contains(last) { return .clause }
        if let nextWord, TextChunker.startsClause(nextWord) { return .clause }
        return .word
    }

    /// Trim leading silence to `leadMs` and trailing silence to exactly `trailMs` (pads with zeros
    /// if Kokoro left less), with 5 ms fades at the new edges. All-silent input is returned as-is.
    static func trim(_ samples: [Float], sampleRate: Int, trailMs: Int, leadMs: Int = leadMs,
                     threshold: Float = threshold) -> [Float] {
        let frame = max(1, sampleRate * frameMs / 1000)
        let frames = samples.count / frame
        guard frames > 0 else { return samples }
        func voiced(_ f: Int) -> Bool {
            var sum: Float = 0
            let start = f * frame
            for i in start..<(start + frame) { sum += samples[i] * samples[i] }
            return (sum / Float(frame)).squareRoot() > threshold
        }
        guard let first = (0..<frames).first(where: voiced),
              let last = (0..<frames).reversed().first(where: voiced) else { return samples }
        let lead = sampleRate * leadMs / 1000
        let trail = sampleRate * trailMs / 1000
        let start = max(0, first * frame - lead)
        let voicedEnd = min(samples.count, (last + 1) * frame)
        let end = min(samples.count, voicedEnd + trail)
        var out = Array(samples[start..<end])
        let missing = voicedEnd + trail - end
        if missing > 0 { out.append(contentsOf: repeatElement(0, count: missing)) }
        let fade = min(out.count / 2, sampleRate * fadeMs / 1000)
        if fade > 0 {
            for i in 0..<fade {
                let g = Float(i) / Float(fade)
                out[i] *= g
                out[out.count - 1 - i] *= g
            }
        }
        return out
    }
}
