import SwiftUI

/// How far through something is: the accent (the player's on Now Playing) filling a track from
/// the leading edge. It takes no touches.
///
/// - `.groove`: a capsule on a faint ink track, inside content (a folder header's bar,
///   `barHeight` tall).
/// - `.edge`: square ends on a faint accent track, running edge to edge along chrome (the
///   prepared audio line on the bottom band's top edge, `edgeHeight` tall).
struct ProgressLine: View {
    enum Track {
        case groove
        case edge
    }

    /// 0…1.
    let fraction: Double
    let height: CGFloat
    let track: Track

    /// A folder header's bar.
    static let barHeight: CGFloat = 3
    /// The prepared audio line along the top edge of the bottom chrome.
    static let edgeHeight: CGFloat = 2

    @Environment(\.readingPalette) private var reading

    var body: some View {
        let accent = reading?.accent ?? Palette.accent
        GeometryReader { g in
            let fill = g.size.width * min(max(0, fraction), 1)
            ZStack(alignment: .leading) {
                switch track {
                case .groove:
                    Capsule().fill(reading?.track ?? Palette.track)
                    Capsule().fill(accent).frame(width: fill)
                case .edge:
                    Rectangle().fill(accent.opacity(Palette.washOpacity))
                    Rectangle().fill(accent).frame(width: fill)
                }
            }
        }
        .frame(height: height)
        .allowsHitTesting(false)
    }
}

#if DEBUG
struct ProgressLineGallery: View {
    var body: some View {
        PreviewGallery {
            ForEach([0.05, 0.4, 0.95], id: \.self) { fraction in
                PreviewState("\(Int(fraction * 100))%, a header's bar") {
                    ProgressLine(fraction: fraction, height: ProgressLine.barHeight, track: .groove)
                        .padding(.horizontal, Spacing.pageMargin)
                }
                PreviewState("\(Int(fraction * 100))%, over the bottom band") {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: Spacing.xl)
                        RoundedRectangle(cornerRadius: Radius.card)
                            .fill(Palette.chrome)
                            .frame(height: BottomChrome.rowHeight)
                            .padding(.horizontal, BottomChrome.horizontalMargin)
                            .padding(.vertical, Spacing.xs)
                            .frame(maxWidth: .infinity)
                            .background(.bar)
                            .overlay(alignment: .top) {
                                ProgressLine(fraction: fraction, height: ProgressLine.edgeHeight, track: .edge)
                            }
                    }
                }
            }
        }
    }
}

#Preview("ProgressLine · light", traits: .sizeThatFitsLayout) { ProgressLineGallery().previewVariant(.light) }
#Preview("ProgressLine · dark", traits: .sizeThatFitsLayout) { ProgressLineGallery().previewVariant(.dark) }
#Preview("ProgressLine · AX5", traits: .sizeThatFitsLayout) { ProgressLineGallery().previewVariant(.largestText) }
#endif
