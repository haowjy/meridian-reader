import Foundation

/// Where a local-engine playback unit's audio comes from.
enum UnitSource: Equatable {
    /// The whole stitched paragraph CAF from the bake cache, played from its start (or from a
    /// sub-paragraph start time).
    case baked
    /// One synth chunk's CAF, played while the rest of the paragraph is still rendering.
    case chunk(Int)
    /// The stitched paragraph CAF, played from the boundary of chunk `fromChunk` to its end
    /// (the paragraph finished rendering while the producer was waiting on that chunk).
    case stitched(fromChunk: Int)

    /// The engine chunk this unit starts at (nil = the whole baked paragraph).
    var startChunk: Int? {
        switch self {
        case .baked: return nil
        case .chunk(let k), .stitched(let k): return k
        }
    }

    /// Would playing both units (of the same paragraph) play some audio twice? A baked paragraph
    /// covers every chunk; engine units overlap at the same chunk.
    func overlaps(_ other: UnitSource) -> Bool {
        switch (self, other) {
        case (.baked, _), (_, .baked):
            return true
        default:
            return startChunk == other.startChunk
        }
    }

    /// Short tag for the listen debug log ("", "c2", "s2").
    var debugTag: String {
        switch self {
        case .baked: return ""
        case .chunk(let k): return "c\(k)"
        case .stitched(let k): return "s\(k)"
        }
    }

    /// Timing-log kind: "baked" (whole paragraph CAF) or "chunk" (engine chunk or stitched
    /// remainder).
    var timingKind: String {
        switch self {
        case .baked: return "baked"
        case .chunk, .stitched: return "chunk"
        }
    }
}
