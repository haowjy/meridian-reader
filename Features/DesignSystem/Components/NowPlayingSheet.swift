import SwiftUI

/// What you hear, opened up (`ReadingPage`): on regular width a `Sheet` over everything that
/// shrinks back into the Now Playing bar, on compact width in place under the bottom chrome. In the
/// Reader's colours and type (the reading theme, `palette`): the spoken paragraph highlighted in
/// full ink, the others dimmed.
///
/// ```
/// ┌──────────────────────────────────────┐
/// │                 ───                  │ <- grabber (the sheet's)
/// │ ( v Pride and Prejudice ) (Aa) (^)  │ <- `SheetTopBar`, as in the Reader: the pill (the sheet's)
/// │ `banner` (the ^ hint, while on)      │   names where it plays from and shrinks it; Aa, `accessory`
/// │ `text`: dimmed, SPOKEN in full ink   │   The text fills the page, under the header and the
/// │         dimmed                  (↑)  │   band; it follows the audio. (↑) is Jump to Audio, right
/// │                                      │   edge, 12 pt above the card; after you scroll away, bars up only (C128)
/// │ ─────────────────────────────────────│ <- hairline divider
/// │ [art] Title          time left (Voice)│ <- title; Voice trailing (aligned right)
/// │ [━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━] │ <- scrub row
/// │ [🔖]  [⏮]    (⏸)    [⏭]   [⋯]      │ <- transport
/// └──────────────────────────────────────┘
/// ```
///
/// It goes full screen as the Reader does (`ReadingChrome`): the floating play / pause is
/// `playState` / `onPlayPause`, the only control over the text then; Jump to Audio shows only with
/// the bars up (C128), a round 44 pt glass button at the right edge, 12 pt above the card (the folded row, once
/// the chrome folds), in the thumb's reach and off the middle of the screen; its arrow points to the sentence
/// (`direction`). On regular width the pill, the grabber and a pull down shrink it
/// (the showing's `onClose`, after it has gone). `floating` floats just above the bottom band's hairline (a
/// toast), as in the Reader.
struct NowPlayingSheet<Band: View, Reading: View, TextAppearance: View, Accessory: View, Banner: View,
                       Floating: View>: View {
    let showing: ReadingShowing
    /// What you hear, for the play / pause floating in full screen.
    let playState: PlayState
    /// The text scrolled away from the audio: offer to jump back to the spoken sentence.
    var showsJumpToAudio = false
    /// Which way the spoken sentence is from the visible text: Jump to Audio's arrow.
    var jumpDirection: JumpDirection = .up
    let onPlayPause: () -> Void
    var onJumpToAudio: () -> Void = {}
    /// The reading theme's colours, as the Reader's.
    var palette: ReadingPalette = .app
    /// Aa (`TextAppearanceButton` and its panel), just before `accessory`, as in the Reader.
    @ViewBuilder var textAppearance: TextAppearance
    /// The control at the trailing end of the top bar (☝︎, `JumpModeButton`).
    @ViewBuilder var accessory: Accessory
    /// Under the top bar, in the header (the ☝︎ hint), as in the Reader.
    @ViewBuilder var banner: Banner
    @ViewBuilder var text: Reading
    /// The integrated bottom band: title, scrub, transport, all flat on the page background.
    @ViewBuilder var band: Band
    /// Floats just above the bottom band's hairline, as in the Reader (a toast).
    @ViewBuilder var floating: Floating

    @State private var chrome = ReadingChrome()

    var body: some View {
        ReadingPage(showing: showing, chrome: chrome, palette: palette) {
            textAppearance
            accessory
        } banner: {
            banner
        } text: {
            text
        } band: {
            band
        } floating: {
            floating
        } overText: {
            ZStack {
                // Both sit above the card, at the right edge, and never show together: Jump to Audio
                // with the bars up, the floating play / pause in full screen.
                // The clearance is measured from the top of the chrome's box; the card starts
                // `topPadding` below it, so the button comes down that much to sit 12 above the card.
                jumpToAudio
                    .offset(y: ChromeMetrics.topPadding)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                FloatingPlayButton(state: playState, action: onPlayPause)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }

    /// Floats over the text at its right edge, just above the card, so the text keeps running under it.
    private var jumpToAudio: some View {
        JumpToAudioButton(chrome: chrome, awayFromAudio: showsJumpToAudio, direction: jumpDirection,
                          action: onJumpToAudio)
    }
}

/// Jump to Audio: a round glass button a bar high (36 pt, tapped in 44), the app's round-button face (`chromeSurface`, the
/// reading card's fill before iOS 26), an arrow that points to the spoken sentence. Its own view so
/// it reads `chrome.hidden` in its own body: this page builds its overText before the compact chrome
/// attaches (`ReadingChrome.attach`), so a read made by the page's body would only watch the
/// sheet's own copy of full screen and miss the compact chrome's. It leaves with a fast fade the
/// moment full screen begins and returns only on exit (C128). It sits at the right edge, level with
/// the card's edge (`Spacing.s`); how far above the card is `ReadingBars`'s over-text clearance (the
/// same as the floating play / pause's, which never shows at the same time), so it keeps its 12 pt
/// from the card, or the folded row, as the chrome folds.
struct JumpToAudioButton: View {
    let chrome: ReadingChrome
    let awayFromAudio: Bool
    let direction: JumpDirection
    let action: () -> Void

    @Environment(\.readingPalette) private var reading
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The circle: a bar's height. Its tap area is `minTapTarget`.
    static let size = ChromeMetrics.barHeight

    var body: some View {
        let shows = chrome.showsJumpToAudio(awayFromAudio: awayFromAudio)
        ZStack {
            if shows {
                Button(action: action) {
                    Image(systemName: direction == .up ? Icons.jumpToAudioUp : Icons.jumpToAudioDown)
                        .font(BottomChrome.chromeGlyph)
                        .foregroundStyle(reading?.ink ?? Palette.ink)
                        .frame(width: Self.size, height: Self.size)
                        .tapTarget(Self.size)
                        .chromeSurface(Circle(), fill: BottomChrome.fieldFill(reading))
                        .environment(\.chromeSkin, ChromeSkin.current)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Verbs.jumpToAudio)
                .accessibilityHint(direction == .up
                    ? String(localized: "Scrolls up to the sentence being read.")
                    : String(localized: "Scrolls down to the sentence being read."))
                .accessibilityIdentifier("nowPlayingJumpToAudio")
                .chromeLargeContent(Verbs.jumpToAudio, symbol: direction == .up ? Icons.jumpToAudioUp : Icons.jumpToAudioDown)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, Spacing.s)
        // Reduce Motion: a cross-fade, no spring.
        .animation(shows ? (reduceMotion ? Motion.fadeIn : Motion.snappy) : Motion.fadeOut, value: shows)
    }
}

/// Transport row in the five-slot grid: `[leading] [⏮] (⏸) [⏭] [more]`. Now Playing puts 🔖
/// first and ⋯ last; the Reader puts speed (`1×`) first and ⋯ last. The play button is the big round disc
/// and reads "Play" / "Pause" like any player's. The row keeps the grid's 44 pt height, so every slot (and ⋯) sits where it does on the other surfaces; the
/// disc reaches past it by half the difference. The row keeps that room above it, and below it
/// too where the home indicator's inset doesn't already give it (a phone with a Home button).
struct NowPlayingTransport<Leading: View, More: View>: View {
    let state: PlayState
    var canSkipBack = true
    var canSkipForward = true
    let onSkipBack: () -> Void
    let onSkipForward: () -> Void
    let onPlayPause: () -> Void
    /// Long-press on play / pause (developer options: the listen debug panel); nil = none.
    var onPlayLongPress: (() -> Void)?
    /// Slot 1: 🔖.
    @ViewBuilder var leading: Leading
    /// Slot 5: ⋯.
    @ViewBuilder var more: More

    @Environment(\.readingPalette) private var reading
    @State private var bottomInset: CGFloat = 0

    private static var discOverhang: CGFloat {
        (BottomChrome.transportDiscSize - BottomChrome.rowHeight) / 2
    }

    var body: some View {
        BottomToolbarLayout {
            leading
                .toolbarSlot(0)
            Button(action: onSkipBack) { Image(systemName: Icons.previous).toolbarIconFrame() }
                .disabled(!canSkipBack)
                .accessibilityLabel("Previous paragraph")
                .toolbarSlot(1)
            PlayStateButton(state: state, look: .disc, action: onPlayPause)
                .accessibilityLabel(state == .playing ? Verbs.pause : Verbs.play)
                .accessibilityIdentifier("listenPlayPause")
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.6).onEnded { _ in onPlayLongPress?() },
                                     including: onPlayLongPress == nil ? .subviews : .all)
                .frame(height: BottomChrome.rowHeight)
                .toolbarSlot(2)
            Button(action: onSkipForward) { Image(systemName: Icons.next).toolbarIconFrame() }
                .disabled(!canSkipForward)
                .accessibilityLabel("Next paragraph")
                .toolbarSlot(3)
            more
                .toolbarSlot(BottomToolbarLayout.moreSlot)
        }
        .padding(.top, Self.discOverhang)
        .padding(.bottom, max(0, Self.discOverhang - bottomInset))
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomInset = $0 }
        .tint(reading?.ink ?? Palette.ink)
    }
}

#if DEBUG
struct NowPlayingSheetGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("playing, following the audio") {
                frame(.playing, note: nil, back: false)
            }
            PreviewState("paused, scrolled away, sleep timer, saved") {
                frame(.paused, note: "🌙 Sleep in 23 min", back: true, saved: true)
            }
        }
    }

    private func frame(_ state: PlayState, note: String?, back: Bool, saved: Bool = false) -> some View {
        let palette = ReadingTheme.sepia.palette(accent: .jade)
        let map = ReaderScrubMap(paragraphs: (1...20).map { "Paragraph \($0)." })
        return NowPlayingSheet(showing: .sheet(close: .collapse("Pride and Prejudice"), onClose: {}), playState: state,
                               showsJumpToAudio: back, onPlayPause: {}, palette: palette) {
            TextAppearanceButton(isOpen: false) {}
        } accessory: {
            JumpModeButton(isOn: false) {}
        } banner: {
            EmptyView()
        } text: {
            SampleReading(title: "Chapter 12", detail: ["Pride and Prejudice", "9 min left"], spoken: true)
        } band: {
            VStack(spacing: Spacing.xs) {
                HStack(spacing: Spacing.s) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Chapter 12: Hunsford").typeStyle(.row, weight: .semibold).lineLimit(1)
                            .foregroundStyle(palette.ink)
                        Text("9 min left").typeStyle(.caption).foregroundStyle(palette.secondaryInk).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VoiceChromeButton(identifier: "previewVoice") {}
                }
                ReaderScrubRow(map: map, position: 0.42, buffered: [0.42...0.6],
                               onScrubPreview: { _ in }, onScrubCommit: { _ in }, isCapsule: false) {
                    Text("1×").typeStyle(.caption).foregroundStyle(palette.ink).fieldTextFrame()
                }
                if let note {
                    Text(note)
                        .typeStyle(.caption)
                        .foregroundStyle(palette.secondaryInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Spacing.xs)
                }
                NowPlayingTransport(state: state, onSkipBack: {}, onSkipForward: {}, onPlayPause: {}) {
                    SaveToggleButton(isSaved: saved, identifier: "preview", onToggle: {})
                } more: {
                    Image(systemName: Icons.more).toolbarIconFrame()
                }
            }
        } floating: {
            EmptyView()
        }
        .frame(height: 700)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
    }
}

#Preview("NowPlayingSheet · light", traits: .sizeThatFitsLayout) { NowPlayingSheetGallery().previewVariant(.light) }
#Preview("NowPlayingSheet · dark", traits: .sizeThatFitsLayout) { NowPlayingSheetGallery().previewVariant(.dark) }
#Preview("NowPlayingSheet · AX5", traits: .sizeThatFitsLayout) { NowPlayingSheetGallery().previewVariant(.largestText) }
#endif
