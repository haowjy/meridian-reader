import SwiftUI

/// A short notice in a header, in the caution colour on its wash: something is held up and will
/// carry on by itself ("Royal Road asked to slow down (429). “Chapter 42: Low Tide” in 1:52,
/// then slower.").
struct NoticeCard: View {
    let symbol: String
    let text: String
    var identifier: String = "noticeCard"

    var body: some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
        }
        .typeStyle(.caption)
        .foregroundStyle(Palette.caution)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xs)
        .background(Palette.caution.opacity(Palette.washOpacity),
                    in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

/// One line in a header that opens more about it: a symbol, the line's parts, then ›. The parts
/// are set apart as a `DetailLine`'s are, by space and ink, never a separator character: the
/// lead in the accent, semibold, with the symbol and ›; the rest in secondary ink. The lead gives
/// way first, and the parts wrap rather than lose their end (`DetailLineLayout`). VoiceOver reads
/// them as one label, joined with commas.
///
/// ```
/// 📡 Following   1 chapter couldn’t load   41 of 107 fetched ›
/// ```
struct HeaderLink: View {
    let symbol: String
    let parts: [String]
    var identifier: String = "headerLink"
    let action: () -> Void

    /// `DetailLine`'s spacing: `Spacing.s` at the default text size, growing with the caption.
    @ScaledMetric(relativeTo: TypeStyle.caption.relativeTo) private var spacing = Spacing.s

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
                Image(systemName: symbol)
                    .foregroundStyle(Palette.accent)
                DetailLineLayout(spacing: spacing) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                        Text(part)
                            .fontWeight(index == 0 ? .semibold : .regular)
                            .foregroundStyle(index == 0 ? Palette.accent : Palette.secondaryInk)
                            .lineLimit(index == 0 ? 1 : nil)
                    }
                }
                Image(systemName: Icons.disclosure)
                    .imageScale(.small)
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.accent)
            }
            .typeStyle(.caption)
            .frame(minHeight: BottomChrome.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DetailLine.accessibilityLabel(parts))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(identifier)
    }
}

#if DEBUG
struct HeaderCardsGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("header link") {
                HeaderLink(symbol: Icons.follow, parts: ["Following", "3 of 107 fetched"]) {}
            }
            PreviewState("header link, a chapter failed") {
                HeaderLink(symbol: Icons.follow, parts: ["Following", "1 chapter couldn’t load", "41 of 107 fetched"]) {}
            }
            PreviewState("notice") {
                NoticeCard(symbol: Icons.waiting,
                           text: "Royal Road asked to slow down (429). “Chapter 42: Low Tide” in 1:52, then slower.")
            }
        }
    }
}

#Preview("HeaderCards · light", traits: .sizeThatFitsLayout) { HeaderCardsGallery().previewVariant(.light) }
#Preview("HeaderCards · dark", traits: .sizeThatFitsLayout) { HeaderCardsGallery().previewVariant(.dark) }
#Preview("HeaderCards · AX5", traits: .sizeThatFitsLayout) { HeaderCardsGallery().previewVariant(.largestText) }
#endif
