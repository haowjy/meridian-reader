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
    /// Apple TTS for the rest of the paragraph from chunk `fromChunk` (rendered into a temp
    /// CAF, never cached): the local engine couldn't provide it in time.
    case appleFallback(fromChunk: Int, reason: FallbackReason)

    /// The engine chunk this unit starts at (nil = the whole baked paragraph).
    var startChunk: Int? {
        switch self {
        case .baked: return nil
        case .chunk(let k), .stitched(let k), .appleFallback(let k, _): return k
        }
    }

    /// Would playing both units (of the same paragraph) play some audio twice? A baked paragraph
    /// covers every chunk; engine units overlap at the same chunk; Apple fallback audio is a
    /// different rendering, so it only overlaps another Apple unit from the same chunk.
    func overlaps(_ other: UnitSource) -> Bool {
        switch (self, other) {
        case (.baked, _), (_, .baked):
            return true
        case let (.appleFallback(a, _), .appleFallback(b, _)):
            return a == b
        case (.appleFallback, _), (_, .appleFallback):
            return false
        default:
            return startChunk == other.startChunk
        }
    }

    /// Short tag for the listen debug log ("", "c2", "s2", "a2").
    var debugTag: String {
        switch self {
        case .baked: return ""
        case .chunk(let k): return "c\(k)"
        case .stitched(let k): return "s\(k)"
        case .appleFallback(let k, _): return "a\(k)"
        }
    }

    /// Timing-log kind: "baked" (whole paragraph CAF), "chunk" (engine chunk or stitched
    /// remainder) or "apple".
    var timingKind: String {
        switch self {
        case .baked: return "baked"
        case .chunk, .stitched: return "chunk"
        case .appleFallback: return "apple"
        }
    }
}

/// Why a paragraph (from some chunk on) plays with Apple TTS instead of the local engine.
enum FallbackReason: Equatable {
    /// Not rendered yet and the app is in the background, where the engine can't render.
    case background
    /// Rendering is projected to fall behind playback (`HeadStart`).
    case behind
    /// The engine failed to render it.
    case engineError

    /// Listen-bar note while this unit plays. `engine` is the local engine's short name.
    func localizedNote(engine: String) -> String {
        switch self {
        case .background: return "Apple voice – \(engine) can't render in the background"
        case .behind: return "Apple voice for this paragraph – \(engine) fell behind"
        case .engineError: return "Apple voice – \(engine) couldn't render this paragraph"
        }
    }
}
