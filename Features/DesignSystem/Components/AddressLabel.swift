import SwiftUI

/// A page's address shown, not edited: a compact capsule (a field control's height, 36 pt) with
/// the address in caption type and the Reader swap (📄) at its trailing end. Follow's chapter
/// preview carries it in its header. It is not the browser's field (`AddressField`, 44 pt, 📄
/// leading, editable at the bottom): nothing here takes a tap but 📄, so it reads as a label for
/// a page you are only looking at.
///
/// ```
/// ( royalroad.com/fiction/40512/…/chapter-1        📄 )
/// ```
///
/// 📄 keeps its place in every state, so the capsule never changes shape: dimmed while the page
/// can't be read (loading, nothing readable), a spinner while the text is read, 📄 on the page,
/// 📄 filled while the Reader text shows (a tap goes back to the page).
struct AddressLabel: View {
    enum ReaderSwap {
        /// The page isn't loaded or has nothing to read: 📄 dimmed.
        case unavailable
        /// The page's text is being read: a spinner.
        case extracting
        /// The page shows and can be read: 📄.
        case page
        /// The Reader text shows in the page's place: 📄 filled.
        case reader
    }

    let address: String
    let swap: ReaderSwap
    let onSwap: () -> Void

    @Environment(\.readingPalette) private var reading

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            Text(address)
                .typeStyle(.caption)
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Address")
                .accessibilityValue(address)
                .accessibilityIdentifier("addressLabel")
            swapControl
        }
        .padding(.leading, Spacing.s)
        .background(Capsule().fill(BottomChrome.fieldFill(reading)))
    }

    @ViewBuilder
    private var swapControl: some View {
        if swap == .extracting {
            ProgressView()
                .controlSize(.small)
                .fieldControlFrame()
        } else {
            Button(action: onSwap) {
                Image(systemName: swap == .reader ? Icons.readerShowing : Icons.reader)
                    .foregroundStyle(Palette.accent)
                    .fieldControlFrame()
            }
            .buttonStyle(.plain)
            .disabled(swap == .unavailable)
            .opacity(swap == .unavailable ? Palette.disabledOpacity : 1)
            .accessibilityLabel(swap == .reader ? "Show Web Page" : "Show Reader Text")
            .accessibilityIdentifier("addressReader")
        }
    }
}

#if DEBUG
struct AddressLabelGallery: View {
    private let address = "royalroad.com/fiction/40512/the-copper-orchard/chapter/900001/1-first-frost"

    var body: some View {
        PreviewGallery {
            PreviewState("loading") {
                AddressLabel(address: "royalroad.com/fiction/40512", swap: .unavailable) {}
            }
            PreviewState("the page, readable") {
                AddressLabel(address: address, swap: .page) {}
            }
            PreviewState("reading the text") {
                AddressLabel(address: address, swap: .extracting) {}
            }
            PreviewState("the Reader text showing") {
                AddressLabel(address: address, swap: .reader) {}
            }
        }
    }
}

#Preview("AddressLabel · light", traits: .sizeThatFitsLayout) { AddressLabelGallery().previewVariant(.light) }
#Preview("AddressLabel · dark", traits: .sizeThatFitsLayout) { AddressLabelGallery().previewVariant(.dark) }
#Preview("AddressLabel · AX5", traits: .sizeThatFitsLayout) { AddressLabelGallery().previewVariant(.largestText) }
#endif
