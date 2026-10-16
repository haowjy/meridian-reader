import SwiftUI

/// A few lines of text as the reading page shows them, for Settings › Reading: the page colour,
/// a dimmed line, the spoken line highlighted with its sentence underlined, in the chosen
/// typeface, size and line spacing. It changes as the choices do.
struct ReadingSample: View {
    let palette: ReadingPalette
    let font: ReadingFont
    /// The text size step's scale (`ReadingTextSize`).
    let textScale: Double
    let lineSpacing: ReadingLineSpacing

    @ScaledMetric(relativeTo: .body) private var body19: CGFloat = TypeStyle.body.size

    var body: some View {
        let size = body19 * textScale
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Tides rise and fall twice a day.")
                .foregroundStyle(palette.dimInk)
            (Text("Where a bay narrows, the water piles up.").underline(color: palette.underline)
                + Text(" High water can reach several metres."))
                .foregroundStyle(palette.ink)
                .padding(.horizontal, Spacing.xxs)
                .background(palette.highlight, in: RoundedRectangle(cornerRadius: Spacing.xxs))
                .padding(.horizontal, -Spacing.xxs)
        }
        .font(.system(size: size, design: font.design))
        .lineSpacing(size * (lineSpacing.multiple - 1.2))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.m)
        .background(palette.background, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(palette.hairline))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("readingSample")
    }
}

#if DEBUG
struct ReadingSampleGallery: View {
    var body: some View {
        PreviewGallery {
            ForEach(ReadingTheme.allCases) { theme in
                PreviewState(theme.title) {
                    ReadingSample(palette: theme.palette(accent: .jade), font: .serif, textScale: 1, lineSpacing: .normal)
                }
            }
        }
    }
}

#Preview("ReadingSample · light", traits: .sizeThatFitsLayout) { ReadingSampleGallery().previewVariant(.light) }
#Preview("ReadingSample · dark", traits: .sizeThatFitsLayout) { ReadingSampleGallery().previewVariant(.dark) }
#Preview("ReadingSample · AX5", traits: .sizeThatFitsLayout) { ReadingSampleGallery().previewVariant(.largestText) }
#endif
