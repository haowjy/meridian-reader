import SwiftUI

/// The browser's field capsule: 📄 at the leading end toggles the page's reader view. At the
/// trailing end, regular width has 🎧 (listen to the page; shown only on a readable page, `listen`
/// non-nil; a `PlayStateButton`: grey when the page isn't what you hear, accent with bars when it
/// is) and compact width has ↻ (`reload`: reload, or stop while the page loads), with Aa before it
/// while the page shows as its reader view (`appearance`). Compact never has 🎧: play and pause live
/// in the chrome's own button.
///
/// ```
/// ( 📄 news.example.org/…              ↻ )     compact
/// ( 📄 news.example.org/…         Aa   ↻ )     compact, reader view
/// ( 📄 news.example.org/…              🎧 )    regular
/// ```
///
/// In the compact chrome the field's width decides what shows (`ChromeMetrics.readerIconWidth`):
/// folded to one row beside ‹ and ▶ the 🔍 / 📄 give way and the address truncates. ↻ / ✕ never
/// does: it is a whole 44 pt control at the field's trailing end, its glyph the chrome's own,
/// centred in the capsule's end (concentric with it), so the text gives way to it.
///
/// `field` is the text itself: the page's address while idle, the `TextField` while editing.
/// `accessory` sits at the trailing end while editing, in the trailing button's place (🎤).
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
        /// The page shows as its reader view: 📄 lit, a tap shows the web page again.
        case showing
    }

    /// The compact trailing button.
    enum ReloadButton {
        case reload
        /// The page is loading: ✕ stops it.
        case stop
    }

    var reader: ReaderButton = .hidden
    /// The page's play state; nil when the page isn't readable (no 🎧).
    var listen: PlayState?
    /// Compact width: ↻ / ✕ at the trailing end; nil (regular width, the start page) draws none.
    var reload: ReloadButton?
    /// Aa before ↻ while the Browser shows a page's reader (compact width): opens the text appearance
    /// panel pointing at it. The binding is the panel's open state; nil draws no Aa.
    var appearance: Binding<Bool>?
    var onOpenReader: () -> Void = {}
    var onListen: () -> Void = {}
    var onReload: () -> Void = {}
    @ViewBuilder var field: Field
    @ViewBuilder var accessory: Accessory

    @Environment(\.isChromeField) private var isChromeField
    @Environment(\.chromeFieldWidth) private var chromeWidth

    /// How much of the reader icon and of reload the chrome's field has room for (1 outside the
    /// chrome, and while editing: the address is being typed).
    private var readerReveal: CGFloat {
        guard let chromeWidth, reader != .searching else { return 1 }
        return ChromeMetrics.ramp(chromeWidth, ChromeMetrics.readerIconWidth)
    }

    /// The 📄 glyph's frame.
    private static var readerSize: CGFloat { Glyph.fieldLeading }
    /// The field's control glyphs: the chrome's own in the compact chrome, else body text size.
    private var controlFont: Font { isChromeField ? BottomChrome.chromeGlyph : .body }

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
            if let appearance {
                Button { appearance.wrappedValue.toggle() } label: {
                    Image(systemName: Icons.textAppearance)
                        .font(controlFont)
                        .foregroundStyle(appearance.wrappedValue ? Palette.accent : Palette.ink)
                        .frame(width: BottomChrome.minTapTarget, height: BottomChrome.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .textAppearancePopover(isPresented: appearance, arrowEdge: .bottom)
                .accessibilityLabel(Verbs.textAppearance)
                .accessibilityIdentifier("readerAppearance")
                .chromeLargeContent(Verbs.textAppearance, symbol: Icons.textAppearance)
            }
            if let reload {
                Button(action: onReload) {
                    Image(systemName: reload == .stop ? Icons.close : Icons.reload)
                        .font(controlFont)
                        .foregroundStyle(Palette.ink)
                        .frame(width: BottomChrome.minTapTarget, height: BottomChrome.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(reload == .stop ? Verbs.stopLoading : Verbs.reload)
                .accessibilityIdentifier("addressReload")
                .chromeLargeContent(reload == .stop ? Verbs.stopLoading : Verbs.reload,
                                    symbol: reload == .stop ? Icons.close : Icons.reload)
            }
            accessory
        }
        .bottomChromeField(leading: reader == .showing ? Spacing.s * (1 - readerReveal) : Spacing.s,
                           // ↻ / ✕'s 44 pt square sits 2 pt in from the capsule's end: its glyph centres on the
                           // end's curve like the 📄 at the other end.
                           trailing: reload != nil || appearance != nil ? (ChromeMetrics.barHeight - BottomChrome.minTapTarget) / 2
                           : listen == nil && Accessory.self == EmptyView.self ? Spacing.s : Spacing.xxs)
    }

    @ViewBuilder
    private var leading: some View {
        switch reader {
        // 🔍 when there is nothing to read or while editing: the same slot, glyph and frame as
        // the Library's `SearchField`, so both fields line up. A caption-size hint, not a control.
        case .hidden, .searching:
            Image(systemName: Icons.search)
                .font(isChromeField ? BottomChrome.chromeGlyph : .caption)
                .foregroundStyle(Palette.secondaryInk)
                .frame(width: Glyph.fieldLeading * readerReveal, height: Glyph.fieldLeading)
                .opacity(readerReveal)
                .clipped()
                .accessibilityHidden(true)
        case .extracting:
            ProgressView()
                .controlSize(.small)
                .frame(width: Self.readerSize * readerReveal, height: Self.readerSize)
                .opacity(readerReveal)
        case .available:
            Button(action: onOpenReader) {
                Image(systemName: Icons.reader)
                    .font(controlFont)
                    .foregroundStyle(Palette.accent)
                    .frame(width: Self.readerSize * readerReveal, height: Self.readerSize)
                    .opacity(readerReveal)
                    .tapTarget(Self.readerSize)
            }
            .buttonStyle(.plain)
            .allowsHitTesting(readerReveal > 0.5)
            .accessibilityHidden(readerReveal < 0.5)
            .accessibilityLabel(Verbs.openInReader)
            .accessibilityIdentifier("addressReader")
            .chromeLargeContent(Verbs.openInReader, symbol: Icons.reader)
            .transition(.opacity)
        case .showing:
            // The reader view shows: the icon sits in a lit capsule inset from the field's edge,
            // concentric with it (the pill's lit segment, the same fill).
            let side = ChromeMetrics.barHeight
            Button(action: onOpenReader) {
                Image(systemName: Icons.readerShowing)
                    .font(controlFont)
                    .foregroundStyle(Palette.accent)
                    .frame(width: side, height: side)
                    .background { Circle().fill(Palette.lit).padding(ChromeMetrics.litInset) }
                    .contentShape(Circle())
                    .frame(width: side * readerReveal, alignment: .leading)
                    .opacity(readerReveal)
                    .clipped()
            }
            .buttonStyle(.plain)
            .allowsHitTesting(readerReveal > 0.5)
            .accessibilityHidden(readerReveal < 0.5)
            .accessibilityLabel(Verbs.showWebPage)
            .accessibilityAddTraits(.isSelected)
            .accessibilityIdentifier("addressReader")
            .chromeLargeContent(Verbs.showWebPage, symbol: Icons.readerShowing)
            .transition(.opacity)
        }
    }
}

extension AddressField where Accessory == EmptyView {
    init(reader: ReaderButton = .hidden, listen: PlayState? = nil, reload: ReloadButton? = nil,
         appearance: Binding<Bool>? = nil, onOpenReader: @escaping () -> Void = {}, onListen: @escaping () -> Void = {},
         onReload: @escaping () -> Void = {}, @ViewBuilder field: () -> Field) {
        self.init(reader: reader, listen: listen, reload: reload, appearance: appearance, onOpenReader: onOpenReader, onListen: onListen,
                  onReload: onReload, field: field, accessory: { EmptyView() })
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
            PreviewState("compact, readable") {
                AddressField(reader: .available, reload: .reload) { Text("news.example.org") }
            }
            PreviewState("compact, loading") {
                AddressField(reader: .available, reload: .stop) { Text("news.example.org") }
            }
            PreviewState("compact, reader view showing") {
                AddressField(reader: .showing, reload: .reload) { Text("news.example.org") }
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
