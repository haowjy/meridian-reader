import SwiftUI

/// A small progress ring: how far through a part-way page or chapter. Rings mean listening only
/// (a prepare's progress is `PrepareMark`): a row's listening column, a `DetailPart`'s ring.
struct ProgressRing: View {
    let fraction: Double
    var size: CGFloat = Glyph.ring

    @Environment(\.readingPalette) private var reading

    var body: some View {
        ZStack {
            Circle().stroke(reading?.track ?? Palette.track, lineWidth: Glyph.stroke)
            Circle()
                // Never a sliver: a few percent in reads as a spinner's arc (C102); the arc starts at
                // a solid dot-sized wedge, and the full track always shows round it.
                .trim(from: 0, to: fraction > 0 ? min(max(0.1, fraction), 1) : 0)
                .stroke(reading?.accent ?? Palette.accent, style: StrokeStyle(lineWidth: Glyph.stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

#if DEBUG
struct ProgressRingGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("just started, part-way, finished") {
                HStack(spacing: Spacing.m) {
                    ProgressRing(fraction: 0.02)
                    ProgressRing(fraction: 0.4)
                    ProgressRing(fraction: 1)
                }
            }
            PreviewState("on a dark reading page") {
                ProgressRing(fraction: 0.6).onReadingPreview()
            }
        }
    }
}

#Preview("ProgressRing · light", traits: .sizeThatFitsLayout) { ProgressRingGallery().previewVariant(.light) }
#Preview("ProgressRing · dark", traits: .sizeThatFitsLayout) { ProgressRingGallery().previewVariant(.dark) }
#Preview("ProgressRing · AX5", traits: .sizeThatFitsLayout) { ProgressRingGallery().previewVariant(.largestText) }
#endif
