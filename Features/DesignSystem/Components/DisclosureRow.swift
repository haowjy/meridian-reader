import SwiftUI

/// A row that opens its section in place, as iOS's Settings groups do: a card row (not a section
/// title) whose rows follow it while it is open. Closed, it still says what is inside: `value`
/// (the voice in use) set apart by space, and a small ring while a download runs in it.
///
/// ```
/// Phonon                                   ⌄      open: its rows follow
/// Kokoro                         Heart  ◔  ›      closed: the voice in use, a download in it
/// ```
///
/// The whole row is the tap, at least `Control.tap` high; the tap runs `onToggle` in a `Motion`
/// animation and the chevron turns with it (a cross-fade under Reduce Motion). VoiceOver reads it
/// as a button whose value says whether it is expanded.
struct DisclosureRow: View {
    let title: String
    let isOpen: Bool
    /// What the closed row shows of its rows (nil: nothing).
    var value: String?
    /// A download running in its rows, shown while it is closed.
    var downloading = false
    /// That download's fraction once its size is known (nil: starting).
    var fraction: Double?
    /// Space before the title, to line it up with the rows it opens.
    var leadingInset: CGFloat = 0
    let accessibilityID: String
    let onToggle: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? Motion.fadeIn : Motion.standard) { onToggle() }
        } label: {
            SymbolRow(title, symbol: nil) {
                if !isOpen, let value {
                    Text(value)
                        .typeStyle(.row)
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(1)
                }
                if !isOpen, downloading {
                    DownloadMark(state: fraction.map { .progress($0) } ?? .waiting, size: Glyph.small)
                }
                chevron
            }
            .padding(.leading, leadingInset)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(spokenValue)
        .accessibilityIdentifier(accessibilityID)
    }

    @ViewBuilder
    private var chevron: some View {
        let symbol = Image(systemName: Icons.expandable)
            .disclosureSymbol()
            .foregroundStyle(Palette.secondaryInk)
            .rotationEffect(.degrees(isOpen ? 90 : 0))
            .accessibilityHidden(true)
        if reduceMotion {
            // A new view per state: the turn is a fade from one to the other.
            symbol.id(isOpen).transition(.opacity)
        } else {
            symbol
        }
    }

    private var spokenValue: String {
        var parts = [isOpen ? String(localized: "Expanded") : String(localized: "Collapsed")]
        if !isOpen, let value { parts.append(value) }
        if !isOpen, downloading { parts.append(String(localized: "Downloading")) }
        return parts.joined(separator: ", ")
    }
}

#if DEBUG
struct DisclosureRowGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("open, closed with the voice in use, closed with a download") {
                VStack(spacing: 0) {
                    DisclosureRow(title: "Phonon", isOpen: true, value: "Zoey", accessibilityID: "a", onToggle: {})
                    DisclosureRow(title: "Kokoro", isOpen: false, value: "Heart", accessibilityID: "b", onToggle: {})
                    DisclosureRow(title: "Kokoro", isOpen: false, downloading: true, fraction: 0.4,
                                  accessibilityID: "c", onToggle: {})
                    DisclosureRow(title: "Kokoro", isOpen: false, downloading: true, accessibilityID: "d", onToggle: {})
                }
            }
            PreviewState("inside a section, lined up with its rows") {
                DisclosureRow(title: "More Voices", isOpen: false, leadingInset: VoiceRow.nameInset,
                              accessibilityID: "e", onToggle: {})
            }
        }
    }
}

#Preview("DisclosureRow · light", traits: .sizeThatFitsLayout) { DisclosureRowGallery().previewVariant(.light) }
#Preview("DisclosureRow · dark", traits: .sizeThatFitsLayout) { DisclosureRowGallery().previewVariant(.dark) }
#Preview("DisclosureRow · AX5", traits: .sizeThatFitsLayout) { DisclosureRowGallery().previewVariant(.largestText) }
#endif
