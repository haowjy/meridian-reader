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
    /// The room the chrome keeps at the bottom, folded or not: the text keeps clear of it.
    var bottomClearance: CGFloat
    /// How far above the bottom what floats over the text sits: above the card while the chrome is
    /// expanded, above the capsule once folded.
    var overTextClearance: CGFloat
    /// The text, scrolled by a finger, to this offset from its top.
    var scrolled: (CGFloat) -> Void
    /// The text moved without a finger deciding anything: the fold measures from here.
    var anchored: (CGFloat) -> Void
    /// Full screen, owned by the compact chrome: the reading page reads and toggles it here, and the
    /// whole chrome goes or comes back with it.
    var fullScreen: Binding<Bool>
    /// Something else is on screen over this page: it leaves the status bar and the chrome's fold
    /// to what is showing.
    var covered = false
}

/// A reading page: the text between a top bar and a bottom band, in the reading theme. The Reader
/// (`ReaderSheet`) and Now Playing (`NowPlayingSheet`) are the same page with different bands.
///
/// Regular width puts it in a `Sheet` with a grabber and a close pill. Compact width draws it in
/// place, edge to edge, with nothing but the text (and the ☝︎ hint): the top bar's `trailing`, the
/// `band` and `floating` are the sheet's, and the page hands the chrome host its player card
/// instead (`ChromeCard`).
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
    /// Floats over the text: just above the band (Jump to Audio, the full screen play button).
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
                banner
            } content: {
                text
            } overText: {
                overText
            }
        }
    }
}

/// The page drawn in place: the page's colour edge to edge, `ReadingBars` over it, the status bar
/// and home indicator following full screen, and the chrome host told what the text does.
private struct InPlaceFrame<Header: View, Content: View, OverText: View>: View {
    let place: ReadingInPlace
    let chrome: ReadingChrome
    let palette: ReadingPalette
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content
    @ViewBuilder var overText: OverText

    @State private var statusBarHeight: CGFloat = 0

    init(place: ReadingInPlace, chrome: ReadingChrome, palette: ReadingPalette,
         @ViewBuilder header: () -> Header, @ViewBuilder content: () -> Content,
         @ViewBuilder overText: () -> OverText) {
        self.place = place
        self.chrome = chrome
        self.palette = palette
        self.header = header()
        self.content = content()
        self.overText = overText()
        // Before the first frame, so a page opened in full screen never flashes its bars.
        chrome.attach(place)
    }

    /// No band of its own: the card is the chrome's. A zero-height band, not `EmptyView`, which
    /// `ReadingBars` measures as the whole screen's room (the text's bottom inset was 812 pt, so
    /// the middle of the visible text was off the page and a jump to the audio left it at the top).
    var body: some View {
        ReadingBars(chrome: chrome, headerBackground: palette.background, headerSlide: statusBarHeight,
                    bottomClearance: place.bottomClearance, overTextClearance: place.overTextClearance, header: header,
                    content: content, band: Color.clear.frame(height: 0), overText: overText)
            .background(palette.background.ignoresSafeArea())
            .readingSurface(palette)
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { statusBarHeight = $0 }
            .systemBars(lightStatusBar: palette.isDark && !place.covered, hidden: chrome.hidden && !place.covered)
    }
}
