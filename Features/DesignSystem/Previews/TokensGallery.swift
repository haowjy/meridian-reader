#if DEBUG
import SwiftUI

/// The tokens on one page: colours (the player's too), the type scale, spacing and radii.
struct TokensGallery: View {
    private let colours: [(String, Color)] = [
        ("paper", Palette.paper), ("chrome", Palette.chrome), ("ink", Palette.ink),
        ("secondaryInk", Palette.secondaryInk), ("tertiaryInk", Palette.tertiaryInk),
        ("accent", Palette.accent), ("onAccent", Palette.onAccent),
        ("playingTint", Palette.playingTint),
        ("playerBackground", Palette.playerBackground), ("playerChrome", Palette.playerChrome),
        ("playerCard", Palette.playerCard), ("playerTrack", Palette.playerTrack), ("playerInk", Palette.playerInk),
        ("playerDimInk", Palette.playerDimInk), ("playerSecondaryInk", Palette.playerSecondaryInk),
        ("playerTertiaryInk", Palette.playerTertiaryInk),
        ("playerAccent", Palette.playerAccent), ("onPlayerAccent", Palette.onPlayerAccent),
    ]
    private let spacing: [(String, CGFloat)] = [
        ("xxs", Spacing.xxs), ("xs", Spacing.xs), ("s", Spacing.s), ("m", Spacing.m), ("l", Spacing.l),
        ("xl", Spacing.xl),
    ]
    private let radii: [(String, CGFloat)] = [("card", Radius.card), ("pill", Radius.pill)]

    var body: some View {
        PreviewGallery {
            PreviewState("colour") {
                ForEach(colours, id: \.0) { name, colour in
                    HStack(spacing: Spacing.s) {
                        RoundedRectangle(cornerRadius: Spacing.xs)
                            .fill(colour)
                            .overlay(RoundedRectangle(cornerRadius: Spacing.xs).stroke(Palette.secondaryInk.opacity(0.3)))
                            .frame(width: Spacing.xl * 2, height: Spacing.xl)
                        Text(name).typeStyle(.row).foregroundStyle(Palette.ink)
                    }
                }
            }
            PreviewState("type") {
                ForEach(TypeStyle.allCases, id: \.self) { style in
                    Text("\(String(describing: style)) \(Int(style.size))").typeStyle(style).foregroundStyle(Palette.ink)
                }
            }
            PreviewState("spacing") {
                ForEach(spacing, id: \.0) { name, value in
                    HStack(spacing: Spacing.s) {
                        Palette.accent.frame(width: value, height: Spacing.s)
                        Text("\(name) \(Int(value))").typeStyle(.caption).foregroundStyle(Palette.secondaryInk)
                    }
                }
            }
            PreviewState("radius") {
                HStack(spacing: Spacing.m) {
                    ForEach(radii, id: \.0) { name, value in
                        VStack(spacing: Spacing.xxs) {
                            RoundedRectangle(cornerRadius: value, style: .continuous)
                                .fill(Palette.chrome)
                                .frame(width: value * 3, height: value * 2)
                            Text("\(name) \(Int(value))").typeStyle(.caption).foregroundStyle(Palette.secondaryInk)
                        }
                    }
                }
            }
        }
    }
}

#Preview("Tokens · light", traits: .sizeThatFitsLayout) { TokensGallery().previewVariant(.light) }
#Preview("Tokens · dark", traits: .sizeThatFitsLayout) { TokensGallery().previewVariant(.dark) }
#Preview("Tokens · AX5", traits: .sizeThatFitsLayout) { TokensGallery().previewVariant(.largestText) }
#endif
