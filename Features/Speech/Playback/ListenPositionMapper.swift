import Foundation

/// Maps between document positions and the local player's audio for one play. A paragraph's audio
/// is its synth chunks in order (`ChunkOffsets` finds where each chunk starts in the text); inside
/// a chunk, position is proportional by characters.
struct ListenPositionMapper {
    let document: ParagraphDocument
    /// Synth chunks of a paragraph's text (the render queue's plan).
    private let chunkPlan: (String) -> [String]
    private var startsCache: [Int: [Int]] = [:]

    init(document: ParagraphDocument, chunkPlan: @escaping (String) -> [String]) {
        self.document = document
        self.chunkPlan = chunkPlan
    }

    /// Where playback of document offset `utf16` starts: its paragraph, the synth chunk holding it
    /// and how far into that chunk (0 at a paragraph start).
    mutating func startPoint(utf16: Int) -> (paragraph: Int, chunk: Int, fraction: Double) {
        guard !document.isEmpty else { return (0, 0, 0) }
        let paragraph = document.index(containingUTF16Offset: utf16)
        let within = utf16 - document.startUTF16Offset(forParagraph: paragraph)
        guard within > 0 else { return (paragraph, 0, 0) }
        let loc = ChunkOffsets.locate(offset: within, starts: chunkStarts(paragraph: paragraph),
                                      length: length(of: paragraph))
        return (paragraph, loc.chunk, loc.fraction)
    }

    /// The document spot `time` seconds into the file of `unit` (`duration` long).
    mutating func position(of unit: ChunkPlaybackQueue.Item, time: TimeInterval,
                           duration: TimeInterval) -> (paragraph: Int, utf16: Int)? {
        let p = unit.paragraphIndex
        guard document.paragraphs.indices.contains(p) else { return nil }
        let length = length(of: p)
        let starts = chunkStarts(paragraph: p)
        let fractionOfFile = duration > 0 ? min(1, time / duration) : 0
        let within: Int
        switch unit.source {
        case .appleFallback(let fromChunk, _):
            // The rest of the paragraph from `fromChunk` as one Apple file: proportional by characters.
            let from = starts[min(fromChunk, starts.count - 1)]
            within = from + Int(Double(length - from) * fractionOfFile)
        case .baked, .stitched:
            // The stitched paragraph file: locate the chunk from its recorded durations.
            let loc = ChunkOffsets.locate(time: time, fileDuration: duration,
                                          durations: unit.chunkDurations, chunkCount: starts.count)
            within = loc.chunk < 0
                ? Int(Double(length) * loc.fraction)
                : ChunkOffsets.offset(chunk: loc.chunk, fraction: loc.fraction, starts: starts, length: length)
        case .chunk(let k):
            within = ChunkOffsets.offset(chunk: k, fraction: fractionOfFile, starts: starts, length: length)
        }
        return (p, document.startUTF16Offset(forParagraph: p) + max(0, min(within, max(0, length - 1))))
    }

    /// Where each synth chunk of `paragraph` starts (paragraph UTF-16 offsets).
    private mutating func chunkStarts(paragraph: Int) -> [Int] {
        if let cached = startsCache[paragraph] { return cached }
        let text = document.paragraphs[paragraph]
        let starts = ChunkOffsets.starts(paragraph: text, chunks: chunkPlan(text))
        startsCache[paragraph] = starts
        return starts
    }

    private func length(of paragraph: Int) -> Int { document.paragraphs[paragraph].utf16.count }
}
