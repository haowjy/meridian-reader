import SwiftUI

/// Where a reading page (the Reader, Now Playing) is shown.
enum ReadingShowing {
    /// Regular width: a `Sheet` over the surface that opened it; its close pill (`close`), grabber and
    /// pull down call `onClose` once it has gone.
    case sheet(close: SheetClosePill.Kind, onClose: () -> Void)
    /// Compact width: in place under the bottom chrome. No sheet, pill, grabber or pull down.
    case inPlace(ReadingInPlace)
}

/// What a reading page shown in place needs from the compact chrome, as plain values and closures
/// (the shell supplies them; the design system never names it).
struct ReadingInPlace {
    /// The chrome is one row: the band steps away, the text keeps its inset.
    var collapsed: Bool
    /// The room row 2 of the chrome takes at the bottom, expanded or collapsed.
    var bottomClearance: CGFloat
    /// The text, scrolled by a finger, to this offset from its top.
    var scrolled: (CGFloat) -> Void
    /// The text moved without a finger deciding anything: the collapse measures from here.
    var anchored: (CGFloat) -> Void
    /// The bars came back by a pull down at the top of the text.
    var pulledDownAtTop: () -> Void
    /// Full screen, owned by the compact chrome: the reading page reads and toggles it here, and the
    /// whole chrome goes or comes back with it.
    var fullScreen: Binding<Bool>
}

/// A reading page: the text between a top bar and a bottom band, in the reading theme. The Reader
/// (`ReaderSheet`) and Now Playing (`NowPlayingSheet`) are the same page with different bands.
///
/// Regular width puts it in a `Sheet` with a grabber and a close pill; compact width draws it in
/// place, edge to edge, with only Aa and ☝︎ in the top bar (`ReadingBars` lays out both).
struct ReadingPage<Trailing: View, Banner: View, Reading: View, Band: View, Floating: View,
                   OverText: View>: View {
    let showing: ReadingShowing
    let chrome: ReadingChrome
    let palette: ReadingPalette
    /// The top bar's trailing controls: Aa, then ☝︎.
    @ViewBuilder var trailing: Trailing
    /// Under the top bar, in the header (the ☝︎ hint): the text's top inset grows with it.
    @ViewBuilder var banner: Banner
    @ViewBuilder var text: Reading
    /// The integrated bottom band: title, scrub, transport, all flat on the page background.
    @ViewBuilder var band: Band
    /// Floats just above the bottom band's hairline (a toast).
    @ViewBuilder var floating: Floating
    /// Floats over the text just above the band.
    @ViewBuilder var overText: OverText

    var body: some View {
        switch showing {
        case .sheet(let close, let onClose):
            Sheet(onDismiss: onClose, palette: palette, chrome: chrome) {
                VStack(spacing: 0) {
                    SheetTopBar { SheetClosePill(kind: close) } trailing: { trailing }
                    banner
                }
            } content: {
                text
            } band: {
                ReadingBottomBand { band } floating: { floating }
            } overText: {
                overText
            }
        case .inPlace(let place):
            InPlaceFrame(place: place, chrome: chrome, palette: palette) {
                VStack(spacing: 0) {
                    SheetTopBar { EmptyView() } trailing: { trailing }
                        .padding(.top, Spacing.xs)
                    banner
                }
            } content: {
                text
            } band: {
                ReadingBottomBand { band } floating: { floating }
            } overText: {
                overText
            }
        }
    }
}

/// The page drawn in place: the page's colour edge to edge, `ReadingBars` over it, the status bar
/// and home indicator following full screen, and the chrome host told what the text does.
private struct InPlaceFrame<Header: View, Content: View, Band: View, OverText: View>: View {
    let place: ReadingInPlace
    let chrome: ReadingChrome
    let palette: ReadingPalette
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content
    @ViewBuilder var band: Band
    @ViewBuilder var overText: OverText

    @State private var statusBarHeight: CGFloat = 0

    init(place: ReadingInPlace, chrome: ReadingChrome, palette: ReadingPalette,
         @ViewBuilder header: () -> Header, @ViewBuilder content: () -> Content,
         @ViewBuilder band: () -> Band, @ViewBuilder overText: () -> OverText) {
        self.place = place
        self.chrome = chrome
        self.palette = palette
        self.header = header()
        self.content = content()
        self.band = band()
        self.overText = overText()
        // Before the first frame, so a page opened in full screen never flashes its bars.
        chrome.attach(place)
    }

    var body: some View {
        ReadingBars(chrome: chrome, headerBackground: palette.background, headerSlide: statusBarHeight,
                    bottomClearance: place.bottomClearance, bandAway: place.collapsed, header: header,
                    content: content, band: band, overText: overText)
            .background(palette.background.ignoresSafeArea())
            .readingSurface(palette)
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { statusBarHeight = $0 }
            .systemBars(lightStatusBar: palette.isDark, hidden: chrome.hidden)
    }
}
