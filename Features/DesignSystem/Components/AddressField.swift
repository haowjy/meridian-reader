import SwiftUI

/// The browser's field capsule: 📄 at the leading end opens the Reader, 🎧 at the trailing end
/// listens to the page. 🎧 shows only on a readable page (`listen` non-nil) and is a
/// `PlayStateButton`: grey when the page isn't what you hear, accent with bars when it is.
///
/// ```
/// ( 📄 news.example.org/…              🎧 )
/// ```
///
/// `field` is the text itself: the page's address while idle, the `TextField` while editing.
struct AddressField<Field: View>: View {
    enum ReaderButton {
        /// Nothing to read (start page, an unreadable page, while editing): an empty slot.
        case hidden
        /// Extracting the page for the Reader: a spinner.
        case extracting
        /// The page is readable: 📄.
        case available
    }

    var reader: ReaderButton = .hidden
    /// The page's play state; nil when the page isn't readable (no 🎧).
    var listen: PlayState?
    var onOpenReader: () -> Void = {}
    var onListen: () -> Void = {}
    @ViewBuilder var field: Field

    /// The 📄 glyph's frame.
    private static var readerSize: CGFloat { 30 }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            leading
            field
                .typeStyle(.row)
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let listen {
                PlayStateButton(state: listen, look: .badge(idleSymbol: "headphones"), action: onListen)
            }
        }
        .bottomChromeField(leading: Spacing.s, trailing: listen == nil ? Spacing.s : Spacing.xxs)
    }

    @ViewBuilder
    private var leading: some View {
        switch reader {
        case .hidden:
            Color.clear
                .frame(width: Spacing.m, height: Spacing.m)
                .accessibilityHidden(true)
        case .extracting:
            ProgressView()
                .controlSize(.small)
                .frame(width: Self.readerSize, height: Self.readerSize)
        case .available:
            Button(action: onOpenReader) {
                Image(systemName: "doc.plaintext")
                    .font(.body)
                    .foregroundStyle(Palette.accent)
                    .frame(width: Self.readerSize, height: Self.readerSize)
                    .tapTarget(Self.readerSize)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open in Reader")
        }
    }
}

#if DEBUG
struct AddressFieldGallery: View {
    @State private var text = "example.org/tides"

    var body: some View {
        PreviewGallery {
            PreviewState("start page") {
                AddressField { Text("Search or enter address").foregroundStyle(Palette.secondaryInk) }
            }
            PreviewState("unreadable page") {
                AddressField { Text("maps.example.com") }
            }
            PreviewState("readable, not playing") {
                AddressField(reader: .available, listen: .idle) { Text("news.example.org") }
            }
            PreviewState("readable, extracting to listen") {
                AddressField(reader: .available, listen: .preparing) { Text("news.example.org") }
            }
            PreviewState("this page playing") {
                AddressField(reader: .available, listen: .playing) { Text("investopedia.com") }
            }
            PreviewState("this page paused") {
                AddressField(reader: .available, listen: .paused) { Text("investopedia.com") }
            }
            PreviewState("extracting for the Reader") {
                AddressField(reader: .extracting, listen: .idle) { Text("news.example.org") }
            }
            PreviewState("editing") {
                AddressField { TextField("Search or enter address", text: $text) }
            }
        }
    }
}

#Preview("AddressField · light", traits: .sizeThatFitsLayout) { AddressFieldGallery().previewVariant(.light) }
#Preview("AddressField · dark", traits: .sizeThatFitsLayout) { AddressFieldGallery().previewVariant(.dark) }
#Preview("AddressField · AX5", traits: .sizeThatFitsLayout) { AddressFieldGallery().previewVariant(.largestText) }
#endif
