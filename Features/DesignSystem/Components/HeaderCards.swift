import SwiftUI

/// A folder header's switch: a symbol and a title over one line of detail, and the switch at the
/// trailing edge, on a card the width of the header. A folder's Download toggle.
///
/// ```
/// ╭──────────────────────────────────────────╮
/// │ ⬇ Download                         ( ●) │
/// │   On · new pages download too            │
/// ╰──────────────────────────────────────────╯
/// ```
struct SwitchCard: View {
    let title: String
    let symbol: String
    /// Under the title: what on and off mean now ("Off · downloads when played or tapped").
    let detail: String
    @Binding var isOn: Bool
    var identifier: String = "switchCard"

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Label(title, systemImage: symbol)
                    .typeStyle(.row)
                    .foregroundStyle(Palette.ink)
                Text(detail)
                    .typeStyle(.caption)
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(2)
            }
        }
        .tint(Palette.accent)
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .background(Palette.chrome, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityIdentifier(identifier)
    }
}

/// A short notice in a header, in the caution colour on its wash: something is held up and will
/// carry on by itself ("Royal Road asked to slow down. Chapter 42 in 2 min, then slower.").
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

/// One line in a header that opens more about it: a symbol and the line in the accent, then ›
/// ("Following · fetched 41 of 107 ›").
struct HeaderLink: View {
    let symbol: String
    let text: String
    var identifier: String = "headerLink"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xxs) {
                Label(text, systemImage: symbol)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Image(systemName: Icons.disclosure)
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            .typeStyle(.caption, weight: .semibold)
            .foregroundStyle(Palette.accent)
            .frame(minHeight: BottomChrome.minTapTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

#if DEBUG
struct HeaderCardsGallery: View {
    @State private var on = true
    @State private var off = false

    var body: some View {
        PreviewGallery {
            PreviewState("header link") {
                HeaderLink(symbol: Icons.follow, text: "Following · fetching chapter text 4 of 107") {}
            }
            PreviewState("notice") {
                NoticeCard(symbol: Icons.waiting,
                           text: "Royal Road asked to slow down (429). Chapter 42 in 2 min, then slower.")
            }
            PreviewState("switch, off") {
                SwitchCard(title: "Download", symbol: Icons.download, detail: "Off · downloads when played or tapped", isOn: $off)
            }
            PreviewState("switch, on") {
                SwitchCard(title: "Download", symbol: Icons.download, detail: "On · 12 of 107 downloaded", isOn: $on)
            }
        }
    }
}

#Preview("HeaderCards · light", traits: .sizeThatFitsLayout) { HeaderCardsGallery().previewVariant(.light) }
#Preview("HeaderCards · dark", traits: .sizeThatFitsLayout) { HeaderCardsGallery().previewVariant(.dark) }
#Preview("HeaderCards · AX5", traits: .sizeThatFitsLayout) { HeaderCardsGallery().previewVariant(.largestText) }
#endif
