import SwiftUI

/// The layout of a reading page (the Reader, Now Playing): the text fills the screen down to its
/// foot, and the header (top bar, the ☝︎ hint) and the bottom band are drawn over it. The text's
/// scroll view insets its content by their measured heights (`ReadingChrome.insets`), so the first
/// line starts below the header and the last scrolls clear of the band. Full screen
/// (`ReadingChrome.hidden`) slides the bars off their edges (fades them under Reduce Motion); the
/// insets stay as they are, so the text never moves when the bars go or come back.
///
/// `Sheet` (regular width) and `ReadingInPlace` (compact width) both draw this; they differ in what
/// surrounds it. `bottomClearance` is the room under the band that something else occupies (the
/// compact chrome, whose card is the band there): the text keeps clear of it, folded or not.
/// `overTextClearance` is how far above the bottom what floats over the text (Jump to Audio with the
/// bars up, the play button in full screen) sits while the bars show: above the card, or above the
/// folded row.
struct ReadingBars<HeaderBackground: View, Header: View, Content: View, Band: View, OverText: View>: View {
    let chrome: ReadingChrome
    /// The header's shape and colour (a sheet's rounded top, or a plain rectangle).
    let headerBackground: HeaderBackground
    /// How far above the header the screen's top edge is: the header slides this much more than
    /// its own height when it hides.
    let headerSlide: CGFloat
    var bottomClearance: CGFloat = 0
    var overTextClearance: CGFloat?
    let header: Header
    let content: Content
    let band: Band
    let overText: OverText

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.readingAppearance) private var appearance
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var headerHeight: CGFloat = 0
    @State private var bandHeight: CGFloat = 0
    /// The home indicator's inset (the bottom safe area).
    @State private var bottomInset: CGFloat = 0

    var body: some View {
        let hidden = chrome.hidden
        let slides = hidden && !reduceMotion
        ZStack(alignment: .top) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(.container, edges: .bottom)
            // Pages mode is for reading: nothing floats over its text while the bars are hidden
            // (C108); with them shown, Jump to Audio sits above the band, as in Scroll.
            // Jump's own rule is `ReadingChrome.showsJumpToAudio` (C128): bars up only, both modes.
            if appearance.layout != .pages || !hidden {
                overText
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, (hidden ? chrome.pageFooter : overTextClearance ?? bandHeight + bottomClearance) + Spacing.s)
            }
            header
                .background { headerBackground }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                    headerHeight = $0
                    chrome.insets.top = $0
                }
                .offset(y: slides ? -(headerHeight + headerSlide) : 0)
                .opacity(hidden ? 0 : 1)
                .allowsHitTesting(!hidden)
                .accessibilityHidden(hidden)
        }
        .overlay(alignment: .bottom) {
            band
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bandHeight = $0 }
                .padding(.bottom, bottomClearance)
                .offset(y: slides ? bandHeight + bottomInset + bottomClearance : 0)
                .opacity(hidden ? 0 : 1)
                .allowsHitTesting(!hidden)
                .accessibilityHidden(hidden)
        }
        .animation(reduceMotion ? (hidden ? Motion.fadeOut : Motion.fadeIn) : Motion.standard, value: hidden)
        .animation(reduceMotion ? nil : Motion.standard, value: overTextClearance)
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomInset = $0 }
        .onChange(of: bandHeight + bottomInset + bottomClearance, initial: true) { _, bottom in chrome.insets.bottom = bottom }
        .onChange(of: bottomInset, initial: true) { _, inset in chrome.homeIndicator = inset }
        // The bars stay while VoiceOver runs.
        .onChange(of: voiceOver) { _, on in if on { chrome.show() } }
        .environment(\.readingChrome, chrome)
    }
}
