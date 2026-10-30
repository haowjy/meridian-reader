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
    /// bottom chrome. No sheet, pill, grabber or pull down, and nothing over the text.
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
    /// The room the chrome keeps at the bottom, folded or not: the text keeps clear of it.
    var bottomClearance: CGFloat
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
/// Regular width puts it in a `Sheet` with a grabber and a close pill. Compact width's Listen is
/// the same sheet as a cover, the grabber alone at its top and its band a card on glass. Compact
/// width's in-place readers draw it edge to edge with nothing but the text: the top bar, the
/// `band`, `floating` and `overText` are the sheet's, and what is around the text is the chrome's.
struct ReadingPage<Trailing: View, Banner: View, Reading: View, Band: View, Floating: View,
                   OverText: View>: View {
    let showing: ReadingShowing
    let chrome: ReadingChrome
    let palette: ReadingPalette
    /// The top bar's trailing controls: Aa, then ☝︎. A cover has no top bar.
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
                    // The same row in the Reader and Now Playing (decision D24): the close pill
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
            // No top bar: the grabber alone (its controls are in the player card).
            Sheet(onDismiss: onClose, palette: palette, chrome: chrome, largePullTargets: true) {
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
            }
        }
    }
}

/// The page drawn in place: the page's colour edge to edge, `ReadingBars` over it, the status bar
/// and home indicator following full screen, and the chrome host told what the text does.
private struct InPlaceFrame<Header: View, Content: View>: View {
    let place: ReadingInPlace
    let chrome: ReadingChrome
    let palette: ReadingPalette
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content

    @State private var statusBarHeight: CGFloat = 0

    init(place: ReadingInPlace, chrome: ReadingChrome, palette: ReadingPalette,
         @ViewBuilder header: () -> Header, @ViewBuilder content: () -> Content) {
        self.place = place
        self.chrome = chrome
        self.palette = palette
        self.header = header()
        self.content = content()
        // Before the first frame, so a page opened in full screen never flashes its bars.
        chrome.attach(place)
    }

    /// No band of its own: the card is the chrome's. A zero-height band, not `EmptyView`, which
    /// `ReadingBars` measures as the whole screen's room (the text's bottom inset was 812 pt, so
    /// the middle of the visible text was off the page and a jump to the audio left it at the top).
    var body: some View {
        ReadingBars(chrome: chrome, headerBackground: palette.background, headerSlide: statusBarHeight,
                    bottomClearance: place.bottomClearance, header: header,
                    content: content, band: Color.clear.frame(height: 0), overText: EmptyView())
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
            .padding(.bottom, ChromeMetrics.homeClearance)
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

    /// The Reader's and Now Playing's pills sit at the same place (D24) but are told apart: a
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
        case .collapse: String(localized: "Close Now Playing")
        }
    }

    private var value: String {
        switch close {
        case .back: ""
        case .collapse(let from): String(localized: "Playing from \(from)")
        }
    }
}
