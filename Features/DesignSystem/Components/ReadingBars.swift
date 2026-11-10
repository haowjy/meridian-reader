import SwiftUI

/// The layout of a reading page (the Reader, Now Playing): the text fills the screen down to its
/// foot, and the header (top bar, the ☝︎ hint) and the bottom band are drawn over it. The text's
/// scroll view insets its content by what floats over it (`ReadingChrome.insets`): the header's
/// height at the top, at the foot the band and `bottomClearance` above the home indicator's strip,
/// so the first line starts below the header and the last scrolls just clear of what floats. Full
/// screen (`ReadingChrome.hidden`) slides the bars off their edges (fades them under Reduce Motion)
/// and, in Scroll mode, the bottom inset drops to the strip alone: the end of the text scrolls down
/// to the screen's lip. The text on screen doesn't move as the bars go or come back. Pages mode
/// keeps its insets (its pages are cut to them; a change would cut them again).
///
/// `Sheet` and `ReadingInPlace` (compact width's readers) both draw this; they differ in what
/// surrounds it. `bottomClearance` is the room under the band that something else occupies (the
/// compact chrome at its current fold step, whose card is the band there).
/// What floats over the text (Jump to Audio, the play button in full
/// screen) sits above the band
/// and that room while the bars show, above the strip in full screen.
struct ReadingBars<HeaderBackground: View, Header: View, Content: View, Band: View, OverText: View>: View {
    let chrome: ReadingChrome
    /// The header's shape and colour (a sheet's rounded top, or a plain rectangle).
    let headerBackground: HeaderBackground
    /// How far above the header the screen's top edge is: the header slides this much more than
    /// its own height when it hides.
    let headerSlide: CGFloat
    var bottomClearance: CGFloat = 0
    /// The home indicator's strip, when the page can't measure it (in place, laid out through the
    /// bottom safe area); nil: the page's own bottom safe area.
    var homeIndicator: CGFloat?
    let header: Header
    let content: Content
    let band: Band
    let overText: OverText

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.readingAppearance) private var appearance
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var headerHeight: CGFloat = 0
    @State private var bandHeight: CGFloat = 0
    /// The page's bottom safe area, as measured.
    @State private var measuredInset: CGFloat = 0
    /// The home indicator's inset: nothing but page text and its background goes below it.
    private var bottomInset: CGFloat { homeIndicator ?? measuredInset }

    var body: some View {
        let hidden = chrome.hidden
        let slides = hidden && !reduceMotion
        ZStack(alignment: .top) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(.container, edges: .bottom)
            // Pages mode is for reading: nothing floats over its text while the bars are hidden
            //; with them shown, the pill (Jump to Audio, Listen) sits above the band, as in Scroll.
            if appearance.layout != .pages || !hidden {
                // Placed from the home indicator's strip, not the safe area: a page in place may be
                // laid out through the bottom safe area (the Browser's reader mode is) or not (Library Read).
                overText
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, bottomInset + (hidden ? chrome.pageFooter : bandHeight + bottomClearance) + Spacing.s)
                    .ignoresSafeArea(.container, edges: .bottom)
                    // A keyboard left up elsewhere (Browse's field) must not lift it: the floating ⏸
                    // in full screen rode up by the keyboard height.
                    .ignoresSafeArea(.keyboard)
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
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { measuredInset = $0 }
        .onChange(of: floatingBottom(hidden: hidden), initial: true) { _, bottom in chrome.insets.bottom = bottom }
        .onChange(of: bottomInset, initial: true) { _, inset in chrome.homeIndicator = inset }
        // The bars stay while VoiceOver runs.
        .onChange(of: voiceOver) { _, on in if on { chrome.show() } }
        .environment(\.readingChrome, chrome)
        #if DEBUG
        .task { await chrome.opensInFullScreenIfAsked() }
        #endif
        // Nothing on a reading page takes text, so the page never avoids the keyboard; this also
        // keeps the measured bottom inset (chrome.homeIndicator) the home indicator alone.
        .ignoresSafeArea(.keyboard)
    }

    /// What floats over the foot of the text: the band and the room under it, above the home
    /// indicator's strip; in Scroll mode's full screen the strip alone. In Scroll mode the floating
    /// pill's line too while it shows (`OverTextPill`), so the last line ends above it (Pages keeps
    /// its cut; its card makes room instead, `ReadingPagesCard`).
    private func floatingBottom(hidden: Bool) -> CGFloat {
        guard appearance.layout != .pages else { return bandHeight + bottomInset + bottomClearance }
        return (hidden ? bottomInset : bandHeight + bottomInset + bottomClearance) + chrome.overTextClearance
    }
}
