import SwiftUI

/// The browser's field capsule: 📄 at the leading end opens the Reader (in Follow's chapter
/// preview it swaps the page for its Reader text and back), 🎧 at the trailing end listens to the
/// page. 🎧 shows only on a readable page (`listen` non-nil) and is a
/// `PlayStateButton`: grey when the page isn't what you hear, accent with bars when it is.
///
/// ```
/// ( 📄 news.example.org/…              🎧 )
/// ```
///
/// `field` is the text itself: the page's address while idle, the `TextField` while editing.
/// `accessory` sits at the trailing end while editing, in 🎧's place (🎤).
struct AddressField<Field: View, Accessory: View>: View {
    enum ReaderButton {
        /// Nothing to read (start page, an unreadable page): 🔍, as in the Library's field.
        case hidden
        /// Editing the address: a magnifying glass.
        case searching
        /// Extracting the page for the Reader: a spinner.
        case extracting
        /// The page is readable: 📄.
        case available
        /// The Reader text shows in the page's place (Follow's chapter preview): 📄 filled, which
        /// goes back to the page.
        case showing
    }

    var reader: ReaderButton = .hidden
    /// The page's play state; nil when the page isn't readable (no 🎧).
    var listen: PlayState?
    var onOpenReader: () -> Void = {}
    var onListen: () -> Void = {}
    @ViewBuilder var field: Field
    @ViewBuilder var accessory: Accessory

    /// The 📄 glyph's frame.
    private static var readerSize: CGFloat { Glyph.fieldLeading }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            leading
            field
                .typeStyle(.row)
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let listen {
                PlayStateButton(state: listen, look: .badge(idleSymbol: Icons.listen), action: onListen)
                    .accessibilityIdentifier("addressListen")
                    .transition(.opacity)
            }
            accessory
        }
        .bottomChromeField(leading: Spacing.s, trailing: listen == nil && Accessory.self == EmptyView.self
                           ? Spacing.s : Spacing.xxs)
    }

    @ViewBuilder
    private var leading: some View {
        switch reader {
        // 🔍 when there is nothing to read or while editing: the same slot, glyph and frame as
        // the Library's `SearchField`, so both fields line up.
        case .hidden, .searching:
            Image(systemName: Icons.search)
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
                .frame(width: Glyph.fieldLeading, height: Glyph.fieldLeading)
                .accessibilityHidden(true)
        case .extracting:
            ProgressView()
                .controlSize(.small)
                .frame(width: Self.readerSize, height: Self.readerSize)
        case .available, .showing:
            Button(action: onOpenReader) {
                Image(systemName: reader == .showing ? Icons.readerShowing : Icons.reader)
                    .font(.body)
                    .foregroundStyle(Palette.accent)
                    .frame(width: Self.readerSize, height: Self.readerSize)
                    .tapTarget(Self.readerSize)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(reader == .showing ? "Show Web Page" : "Open in Reader")
            .accessibilityIdentifier("addressReader")
            .transition(.opacity)
        }
    }
}

extension AddressField where Accessory == EmptyView {
    init(reader: ReaderButton = .hidden, listen: PlayState? = nil, onOpenReader: @escaping () -> Void = {},
         onListen: @escaping () -> Void = {}, @ViewBuilder field: () -> Field) {
        self.init(reader: reader, listen: listen, onOpenReader: onOpenReader, onListen: onListen,
                  field: field, accessory: { EmptyView() })
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
            PreviewState("the Reader text showing (Follow's preview)") {
                AddressField(reader: .showing) { Text("royalroad.com/fiction/1/chapter/2") }
            }
            PreviewState("extracting for the Reader") {
                AddressField(reader: .extracting, listen: .idle) { Text("news.example.org") }
            }
            PreviewState("editing") {
                AddressField(reader: .searching) {
                    TextField("Search or enter address", text: $text)
                } accessory: {
                    Image(systemName: Icons.dictate).foregroundStyle(Palette.secondaryInk).fieldControlFrame()
                }
            }
        }
    }
}

#Preview("AddressField · light", traits: .sizeThatFitsLayout) { AddressFieldGallery().previewVariant(.light) }
#Preview("AddressField · dark", traits: .sizeThatFitsLayout) { AddressFieldGallery().previewVariant(.dark) }
#Preview("AddressField · AX5", traits: .sizeThatFitsLayout) { AddressFieldGallery().previewVariant(.largestText) }
#endif
