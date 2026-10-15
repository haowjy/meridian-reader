import SwiftUI

/// How far the running downloads have got (decision D16): a 2 pt line along the top edge of the
/// bottom chrome, the accent (the player's on Now Playing) filling a faint accent track from the
/// leading edge. Out of the way:
/// it takes no touches and moves nothing around it; it fades in while downloads run and out when
/// they end (the caller's transition).
struct DownloadProgressLine: View {
    /// 0…1.
    let fraction: Double

    static let height: CGFloat = 2

    @Environment(\.onPlayerPalette) private var onPlayer

    var body: some View {
        let accent = onPlayer ? Palette.playerAccent : Palette.accent
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Rectangle().fill(accent.opacity(Palette.washOpacity))
                Rectangle()
                    .fill(accent)
                    .frame(width: g.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: Self.height)
        .animation(Motion.standard, value: fraction)
        .allowsHitTesting(false)
    }
}

#if DEBUG
struct DownloadProgressLineGallery: View {
    var body: some View {
        PreviewGallery {
            ForEach([0.05, 0.4, 0.95], id: \.self) { fraction in
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
                            .overlay(alignment: .top) { DownloadProgressLine(fraction: fraction) }
                    }
                }
            }
        }
    }
}

#Preview("DownloadProgressLine · light", traits: .sizeThatFitsLayout) { DownloadProgressLineGallery().previewVariant(.light) }
#Preview("DownloadProgressLine · dark", traits: .sizeThatFitsLayout) { DownloadProgressLineGallery().previewVariant(.dark) }
#Preview("DownloadProgressLine · AX5", traits: .sizeThatFitsLayout) { DownloadProgressLineGallery().previewVariant(.largestText) }
#endif
