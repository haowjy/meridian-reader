import SwiftUI

/// The browser's field capsule: 📄 at the leading end toggles the page's reader view. At the
/// trailing end, regular width has 🎧 (listen to the page; shown only on a readable page, `listen`
/// non-nil; a `PlayStateButton`: grey when the page isn't what you hear, accent with bars when it
/// is) and compact width has ↻ (`reload`: reload, or stop while the page loads). Compact never has
/// 🎧: play and pause live in the chrome's own button.
///
/// ```
/// ( 📄 news.example.org/…              ↻ )     compact
/// ((📄) news.example.org/…             ↻ )     compact, reader view (📄 lit)
/// ((📄) investing.example.com            )     compact, Library Read (no ↻)
/// ( 📄 news.example.org/…              🎧 )    regular
/// ```
///
/// In the compact chrome the field's width decides what shows (`ChromeMetrics.readerIconWidth`):
/// folded to one row beside ‹ and ▶ the 🔍 / 📄 give way and the address truncates. ↻ / ✕ never
/// does: it is a whole 44 pt control at the field's trailing end, its glyph the chrome's own,
/// centred in the capsule's end (concentric with it), so the text gives way to it.
///
/// `holdMenu` (the compact Browser's menu, which has no ⋯ in its chrome) opens on a press and hold of
/// the leading glyph, 📄 or 🔍, as a system menu; a tap on 📄 still toggles the reader view.
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
        /// The page shows as its reader view: 📄 lit, a tap shows the web page again (Library Read:
        /// opens the page in the Browser).
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
    /// The menu a press and hold on the leading glyph opens (nil: none).
    var holdMenu: [[MenuRow]]?
    /// 📄's tap. nil with a `holdMenu` (Library Read on a page with no web address): the lit 📄 has
    /// nothing to show, so a tap opens the menu and it reads as *More*.
    var onOpenReader: (() -> Void)? = {}
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
    private static var readerSize: CGFloat { ChromeMetrics.endGlyphSlot }
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
            if let reload {
                Button(action: onReload) {
                    Image(systemName: reload == .stop ? Icons.close : Icons.reload)
                        .font(controlFont)
                        .foregroundStyle(Palette.ink)
                        .frame(width: reloadSide, height: reloadSide)
                        .tapTarget(reloadSide)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(reload == .stop ? Verbs.stopLoading : Verbs.reload)
                .accessibilityIdentifier("addressReload")
                .chromeLargeContent(reload == .stop ? Verbs.stopLoading : Verbs.reload,
                                    symbol: reload == .stop ? Icons.close : Icons.reload)
            }
            accessory
        }
        // In the chrome a 24 pt glyph slot (📄, 🔍, 🎤, ⊗) sits `endInset` in from the capsule's end, so it is
        // concentric with the end cap; ↻ / ✕ is a circle as tall as the capsule at its very end, centred the same
        // way (tapped 44). On the band a 44 pt button (↻ / ✕, 🎧) sits 2 pt in.
        .bottomChromeField(leading: reader == .showing ? leadingInset * (1 - readerReveal) : leadingInset,
                           trailing: reload != nil || listen != nil
                               ? (isChromeField ? 0 : Spacing.xxs / 2)
                               : Accessory.self == EmptyView.self ? Spacing.s
                               : isChromeField ? ChromeMetrics.endInset : Spacing.xxs)
    }

    /// ↻ / ✕'s frame: the capsule's height in the chrome, `Control.tap` on the band.
    private var reloadSide: CGFloat { isChromeField ? Control.chrome : Control.tap }

    /// The leading glyph slot's inset: concentric with the end cap in the chrome.
    private var leadingInset: CGFloat { isChromeField ? ChromeMetrics.endInset : Spacing.s }

    @ViewBuilder
    private var leading: some View {
        switch reader {
        // 🔍 when there is nothing to read or while editing: the same slot, glyph and frame as
        // the Library's `SearchField`, so both fields line up. A caption-size hint, not a control.
        case .hidden, .searching:
            let glyph = Image(systemName: Icons.search)
                .font(isChromeField ? BottomChrome.chromeGlyph : .caption)
                .foregroundStyle(Palette.secondaryInk)
                .frame(width: ChromeMetrics.endGlyphSlot * readerReveal, height: ChromeMetrics.endGlyphSlot)
                .opacity(readerReveal)
                .clipped()
            if let holdMenu, reader == .hidden {
                // Nothing to read: the glyph holds the page's menu, and a tap does nothing.
                Menu { MenuRows(blocks: holdMenu) } label: { glyph.tapTarget(ChromeMetrics.endGlyphSlot) } primaryAction: {}
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .allowsHitTesting(readerReveal > 0.5)
                    .accessibilityHidden(readerReveal < 0.5)
                    .accessibilityLabel(Verbs.more)
                    .accessibilityIdentifier("addressMenu")
            } else {
                glyph.accessibilityHidden(true)
            }
        case .extracting:
            ProgressView()
                .controlSize(.small)
                .frame(width: Self.readerSize * readerReveal, height: Self.readerSize)
                .opacity(readerReveal)
        case .available:
            readerControl {
                Image(systemName: Icons.reader)
                    .font(controlFont)
                    .foregroundStyle(Palette.accent)
                    .frame(width: Self.readerSize * readerReveal, height: Self.readerSize)
                    .opacity(readerReveal)
                    .tapTarget(Self.readerSize)
            }
            .allowsHitTesting(readerReveal > 0.5)
            .accessibilityHidden(readerReveal < 0.5)
            .accessibilityLabel(Verbs.openInReader)
            .accessibilityIdentifier("addressReader")
            .chromeLargeContent(Verbs.openInReader, symbol: Icons.reader)
            .transition(.opacity)
        case .showing:
            // The reader view shows: the icon sits in a lit capsule inset from the field's edge,
            // concentric with it (the pill's lit segment, the same fill).
            let side = Control.chrome
            readerControl {
                Image(systemName: Icons.readerShowing)
                    .font(controlFont)
                    .foregroundStyle(Palette.accent)
                    .frame(width: side, height: side)
                    .background { Circle().fill(Palette.lit).frame(width: ChromeMetrics.innerCircle, height: ChromeMetrics.innerCircle) }
                    // The capsule's end, `hitOutset` past it: 44 pt to tap.
                    .contentShape(ChromeHitShape())
                    .frame(width: side * readerReveal, alignment: .leading)
                    .opacity(readerReveal)
                    .clipped()
            }
            .allowsHitTesting(readerReveal > 0.5)
            .accessibilityHidden(readerReveal < 0.5)
            .accessibilityLabel(onOpenReader == nil ? Verbs.more : Verbs.showWebPage)
            .accessibilityAddTraits(.isSelected)
            .accessibilityIdentifier("addressReader")
            .chromeLargeContent(onOpenReader == nil ? Verbs.more : Verbs.showWebPage, symbol: Icons.readerShowing)
            .transition(.opacity)
        }
    }
}

extension AddressField {
    /// 📄: a tap toggles the reader view; with a `holdMenu`, a press and hold opens it (with no
    /// `onOpenReader`, a tap does).
    @ViewBuilder
    fileprivate func readerControl(@ViewBuilder _ label: () -> some View) -> some View {
        if let holdMenu {
            if let onOpenReader {
                Menu { MenuRows(blocks: holdMenu) } label: { label() } primaryAction: { onOpenReader() }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
            } else {
                Menu { MenuRows(blocks: holdMenu) } label: { label() }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
            }
        } else {
            Button(action: { onOpenReader?() }, label: label)
                .buttonStyle(.plain)
        }
    }
}

extension AddressField where Accessory == EmptyView {
    init(reader: ReaderButton = .hidden, listen: PlayState? = nil, reload: ReloadButton? = nil,
         onOpenReader: (() -> Void)? = {}, onListen: @escaping () -> Void = {},
         onReload: @escaping () -> Void = {}, @ViewBuilder field: () -> Field) {
        self.init(reader: reader, listen: listen, reload: reload, onOpenReader: onOpenReader, onListen: onListen,
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
