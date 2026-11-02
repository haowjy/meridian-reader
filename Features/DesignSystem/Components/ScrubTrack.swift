import SwiftUI

/// The scrubber's look: track, buffered spans, fill and thumb, at `value` (0…1). Grows a little
/// while dragged. Draws only; the owner handles the drag (the Reader's scrub row, `ReaderScrubRow`).
/// On the reading page the fill and thumb are its accent on its track.
struct ScrubTrack: View {
    let value: Double
    /// Spans that already have audio, as fractions of the track.
    var buffered: [ClosedRange<Double>] = []
    var isDragging = false

    @Environment(\.readingPalette) private var reading

    var body: some View {
        let fill = reading?.accent ?? Palette.accent
        let empty = reading?.track ?? Palette.track
        GeometryReader { g in
            let w = max(1, g.size.width)
            let shown = min(max(0, value), 1)
            let thumb: CGFloat = isDragging ? 20 : 12
            let track: CGFloat = isDragging ? 6 : 4
            ZStack(alignment: .leading) {
                Capsule().fill(empty).frame(height: track)
                ForEach(Array(buffered.enumerated()), id: \.offset) { _, span in
                    Capsule()
                        .fill(fill.opacity(0.28))
                        .frame(width: max(track, w * (span.upperBound - span.lowerBound)), height: track)
                        .offset(x: w * span.lowerBound)
                }
                .accessibilityHidden(true)
                Capsule().fill(fill).frame(width: w * shown, height: track)
                Circle()
                    .fill(fill)
                    .frame(width: thumb, height: thumb)
                    .shadow(color: Palette.scrim.opacity(isDragging ? 0.18 : 0), radius: 3, y: 1)
                    .offset(x: w * shown - thumb / 2)
            }
            .frame(width: w, height: g.size.height)
        }
    }
}

#if DEBUG
struct ScrubTrackGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("start") { ScrubTrack(value: 0).frame(height: Control.small) }
            PreviewState("part-way, buffered ahead") {
                ScrubTrack(value: 0.42, buffered: [0.42...0.7]).frame(height: Control.small)
            }
            PreviewState("dragging") {
                ScrubTrack(value: 0.6, buffered: [0.6...0.8], isDragging: true).frame(height: Control.small)
            }
            PreviewState("on a dark reading page") {
                ScrubTrack(value: 0.42, buffered: [0.42...0.7]).frame(height: Control.small)
                    .onReadingPreview()
            }
        }
    }
}

#Preview("ScrubTrack · light", traits: .sizeThatFitsLayout) { ScrubTrackGallery().previewVariant(.light) }
#Preview("ScrubTrack · dark", traits: .sizeThatFitsLayout) { ScrubTrackGallery().previewVariant(.dark) }
#Preview("ScrubTrack · AX5", traits: .sizeThatFitsLayout) { ScrubTrackGallery().previewVariant(.largestText) }
#endif
