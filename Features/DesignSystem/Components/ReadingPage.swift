import SwiftUI

/// Where a reading page is shown.
enum ReadingShowing {
    /// Regular width (the Reader, Now Playing): a `Sheet` over the surface that opened it; its close
    /// pill (`close`), grabber and pull down call `onClose` once it has gone.
    case sheet(close: Close, onClose: () -> Void)
    /// Compact width's Listen: a `Sheet` over the screen, chrome and all (`Sheet`'s `largePullTargets`).
    /// A pull down (VoiceOver: the escape gesture) closes it, then `onClose`. Its band is the player card
    /// on glass at the foot, with what it was over left as it was.
    case cover(onClose: () -> Void)
    /// Compact width's in-place readers (the Library's Read, the Browser's reader mode): under the
    /// bottom chrome. No sheet, pill, grabber or pull down; the header (`banner`, the top group) is
    /// clear, so the text scrolls under what floats in it.
    case inPlace(ReadingInPlace)

    /// The sheet's close pill, at the leading edge of its top bar:
    /// - `.back("Browser")`: "‹ Browser", the Reader; it names what is underneath.
    /// - `.collapse("Pride and Prejudice")`: "⌄ Pride and Prejudice", Now Playing; it names where
    ///   the page plays from and shrinks the sheet back into the bar.
    enum Close: Equatable {
        case back(String)
        case collapse(String)
    }
}

/// What a reading page shown in place needs from the compact chrome, as plain values and closures
/// (the shell supplies them; the design system never names it).
struct ReadingInPlace {
    /// The room the chrome's two rows take at the bottom (above the home indicator's strip): the end
    /// of the text scrolls to just above it. A reader's chrome never folds, so only full screen changes
    /// what floats at the foot.
    var bottomClearance: CGFloat
    /// The home indicator's strip (the window's bottom safe area). The page in place is laid out
    /// through the bottom safe area, under the chrome, so it can't measure the strip itself.
    var homeIndicator: CGFloat
    /// The text, scrolled by a finger, to this offset from its top.
    var scrolled: (CGFloat) -> Void
    /// The text moved without a finger deciding anything: the chrome measures from here.
    var anchored: (CGFloat) -> Void
    /// Full screen, owned by the compact chrome: the reading page reads it here and the centre tap
    /// toggles it; a scroll in Scroll mode can too (`ChromeScroll`). The whole chrome goes or comes back
    /// with it.
    var fullScreen: Binding<Bool>
    /// Something else is on screen over this page: it leaves the status bar to what is showing.
    var covered = false
}

/// A reading page: the text between a top bar and a bottom band, in the reading theme. The Reader
/// (`ReaderSheet`) and Now Playing (`NowPlayingSheet`) are the same page with different bands.
///
/// Regular width puts it in a `Sheet` with a grabber and a close pill. Compact width's Listen is
/// the same sheet as a cover, the grabber at its top over its header (the top group) and its band a
/// card on glass. Compact width's in-place readers draw it edge to edge with the text and a clear
/// header (the top group) over it: the top bar, the `band` and `floating` are the sheet's, and what
/// is at the foot is the chrome's.
struct ReadingPage<Trailing: View, Banner: View, Reading: View, Band: View, Floating: View,
                   OverText: View>: View {
    let showing: ReadingShowing
    let chrome: ReadingChrome
    let palette: ReadingPalette
    /// The top bar's trailing controls: Aa, then ☝︎. A cover has no top bar.
    @ViewBuilder var trailing: Trailing
    /// Under the top bar, in the header (compact width's top group, the ☝︎ hint): the text's top
    /// inset grows with it.
    @ViewBuilder var banner: Banner
    @ViewBuilder var text: Reading
    /// The integrated bottom band: title, scrub, transport, all flat on the page background.
    @ViewBuilder var band: Band
    /// Floats just above the bottom band's hairline (a toast).
    @ViewBuilder var floating: Floating
    /// Floats over the text: just above the band (Jump to Audio, the full screen play button).
    @ViewBuilder var overText: OverText

    init(showing: ReadingShowing, chrome: ReadingChrome, palette: ReadingPalette,
         @ViewBuilder trailing: () -> Trailing, @ViewBuilder banner: () -> Banner,
         @ViewBuilder text: () -> Reading, @ViewBuilder band: () -> Band,
         @ViewBuilder floating: () -> Floating, @ViewBuilder overText: () -> OverText) {
        self.showing = showing
        self.chrome = chrome
        self.palette = palette
        self.trailing = trailing()
        self.banner = banner()
        self.text = text()
        self.band = band()
        self.floating = floating()
        self.overText = overText()
        // Before the first frame, so a page opened in full screen never flashes its bars.
        chrome.present(showing)
    }

    var body: some View {
        switch showing {
        case .sheet(let close, let onClose):
            Sheet(onDismiss: onClose, palette: palette, chrome: chrome) {
                VStack(spacing: 0) {
                    // The same row in the Reader and Now Playing: the close pill
                    // leading, Aa then ☝︎ trailing, so they sit at the same place whichever is up.
                    HStack(spacing: Spacing.s) {
                        ClosePill(close: close)
                        Spacer(minLength: 0)
                        trailing
                    }
                    .padding(.horizontal, Spacing.pageMargin)
                    .padding(.bottom, Spacing.xs)
                    banner
                }
            } content: {
                text
            } band: {
                ReadingBottomBand { band } floating: { floating }
            } overText: {
                overText
            }
        case .cover(let onClose):
            // No top bar: the header is the top group, the grabber between its corner buttons
            // (`ReadingTopGroup.carriesGrabber`), then the ☝︎ hint.
            Sheet(onDismiss: onClose, palette: palette, chrome: chrome, largePullTargets: true, headerHasGrabber: true) {
                banner
            } content: {
                text
            } band: {
                CoverBand { band } floating: { floating }
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

/// The page drawn in place: the page's colour edge to edge, `ReadingBars` over it (its header clear), the status bar
/// and home indicator following full screen, and the chrome host told what the text does.
private struct InPlaceFrame<Header: View, Content: View, OverText: View>: View {
    let place: ReadingInPlace
    let chrome: ReadingChrome
    let palette: ReadingPalette
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content
    @ViewBuilder var overText: OverText

    @State private var statusBarHeight: CGFloat = 0

    /// No band of its own: the card is the chrome's. A zero-height band, not `EmptyView`, which
    /// `ReadingBars` measures as the whole screen's room (the text's bottom inset was 812 pt, so
    /// the middle of the visible text was off the page and a jump to the audio left it at the top).
    var body: some View {
        // A clear header: the top group floats over the text, which scrolls under it.
        ReadingBars(chrome: chrome, headerBackground: Color.clear, headerSlide: statusBarHeight,
                    bottomClearance: place.bottomClearance, homeIndicator: place.homeIndicator, header: header,
                    content: content, band: Color.clear.frame(height: 0), overText: overText)
            .background(palette.background.ignoresSafeArea())
            .readingSurface(palette)
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { statusBarHeight = $0 }
            .systemBars(lightStatusBar: palette.isDark && !place.covered, hidden: chrome.hidden && !place.covered)
    }
}

/// A cover's band: the player card on the chrome's glass, at the chrome's margins, floating over the
/// text, which runs on under it to the screen's foot (no fade). `floating` (a toast) sits on its top.
private struct CoverBand<Content: View, Floating: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var floating: Floating

    @Environment(\.readingPalette) private var reading

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.surface, style: .continuous)
        content
            // The card stays compact: its text grows only so far (its glyphs offer the large content viewer).
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .clipShape(shape)
            .chromeSurface(shape, fill: BottomChrome.fieldFill(reading), interactive: false)
            .environment(\.chromeSkin, ChromeSkin.current)
            .padding(.horizontal, Spacing.bandMargin)
            .padding(.bottom, Spacing.xs)
            .overlay(alignment: .top) { floating }
    }
}

/// The pill that closes the sheet it sits in (`ReadingShowing.Close`).
private struct ClosePill: View {
    let close: ReadingShowing.Close
    @Environment(\.dismissSheet) private var dismissSheet

    var body: some View {
        PillButton(title, systemImage: symbol, style: .neutral, size: .compact) { dismissSheet() }
            .accessibilityLabel(label)
            .accessibilityValue(value)
            .accessibilityIdentifier(identifier)
    }

    /// The Reader's and Now Playing's pills sit at the same place but are told apart: a
    /// Reader can stay under Now Playing.
    private var identifier: String {
        switch close {
        case .back: "readerClose"
        case .collapse: "nowPlayingClose"
        }
    }

    private var title: String {
        switch close {
        case .back(let title), .collapse(let title): title
        }
    }

    private var symbol: String {
        switch close {
        case .back: Icons.back
        case .collapse: Icons.collapse
        }
    }

    private var label: String {
        switch close {
        case .back(let title): String(localized: "Back to \(title)")
        case .collapse: String(localized: "Close Listen")
        }
    }

    private var value: String {
        switch close {
        case .back: ""
        case .collapse(let from): String(localized: "Playing from \(from)")
        }
    }
}
