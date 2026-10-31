import SwiftUI

/// What you hear, opened up (`ReadingPage`): on regular width a `Sheet` over everything that
/// shrinks back into the Now Playing bar, on compact width a cover over everything, chrome too. In the
/// Reader's colours and type (the reading theme, `palette`): the spoken paragraph on the theme's
/// highlight, every paragraph in full ink. Regular width's sheet:
///
/// ```
/// ┌──────────────────────────────────────┐
/// │                 ───                  │ <- grabber (the sheet's)
/// │ ( v Pride and Prejudice ) (Aa) (^)  │ <- the top bar, as in the Reader: the pill (the sheet's)
/// │ `banner` (the ^ hint, while on)      │   names where it plays from and shrinks it; Aa, `accessory`
/// │ `text`: SPOKEN on the highlight      │   The text fills the page, under the header and the
/// │                                      │   band; it follows the audio. (↑) is Jump to Audio,
/// │          ( ↑ Jump to Audio )         │   centred, 12 pt above the band, once you scroll away
/// │ `band`: title, scrub row, transport  │ <- the bottom band
/// └──────────────────────────────────────┘
/// ```
///
/// Compact Listen has no top bar (the grabber's band alone) and its band is the player card on glass
/// (`ReaderPlayerCard`), its tools beside the transport.
///
/// It goes full screen as the Reader does (`ReadingChrome`): the floating play / pause is
/// `playState` / `onPlayPause`, at the bottom right. Jump to Audio (`JumpToAudioButton`, a thin accent pill, "↑ Jump to Audio") floats
/// centred over the text while it is away from the audio, 12 pt above the card, or above the home
/// indicator's strip in full screen; its arrow points to the sentence (`direction`). On regular
/// width the pill, the grabber and a pull down shrink it
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
    /// Aa (`TextAppearanceControl`: its `IconButton` and panel), just before `accessory`, as in the Reader.
    @ViewBuilder var textAppearance: TextAppearance
    /// The control at the trailing end of the top bar (☝︎, an `IconButton`).
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
            // Both sit on the same line above the card (above the strip in full screen): Jump to
            // Audio in the middle, the floating play / pause at the right edge.
            ZStack {
                JumpToAudioButton(shows: showsJumpToAudio, direction: jumpDirection, action: onJumpToAudio)
                FloatingPlayButton(state: playState, action: onPlayPause)
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

/// Jump to Audio: a thin accent pill, "↑ Jump to Audio", in the pills' type (row, semibold, as
/// the readers' "▶ Listen") with just 4 pt above and below, floating in the
/// middle of the line above what floats at the foot (the card, or the strip in full screen), its
/// arrow pointing to the spoken sentence. It shows only while the text is away from the audio
/// (`shows`), and fades in and out; in full screen only with the floating play / pause
/// (`ReadingChrome.showsFloating`), so the two come and go together. While it shows, Scroll mode's text leaves its line clear at the
/// end (`ReadingChrome.jumpClearance`).
struct JumpToAudioButton: View {
    let shows: Bool
    let direction: JumpDirection
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.readingPalette) private var reading
    @Environment(\.readingChrome) private var chrome

    private var visible: Bool {
        guard shows, let chrome, chrome.hidden else { return shows }
        return chrome.showsFloating
    }

    var body: some View {
        ZStack {
            if visible {
                Button(action: action) {
                    Label(Verbs.jumpToAudio, systemImage: direction == .up ? Icons.jumpToAudioUp : Icons.jumpToAudioDown)
                        .typeStyle(.row, weight: .semibold)
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(reading?.onAccent ?? Palette.onAccent)
                        .padding(.horizontal, Spacing.s)
                        .padding(.vertical, Spacing.xxs)
                        .background(reading?.accent ?? Palette.accent, in: Capsule(style: .continuous))
                        // Thin, but its tap area is the tap floor.
                        .contentShape(Capsule().inset(by: -Spacing.s))
                }
                .buttonStyle(PillPressStyle())
                .accessibilityLabel(Verbs.jumpToAudio)
                .accessibilityHint(direction == .up
                    ? String(localized: "Scrolls up to the sentence being read.")
                    : String(localized: "Scrolls down to the sentence being read."))
                .accessibilityIdentifier("nowPlayingJumpToAudio")
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        // The text's end scrolls clear of the pill while it shows (0 tall when it doesn't).
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            chrome?.jumpClearance = height > 0 ? height + Spacing.s : 0
        }
        // Reduce Motion: a cross-fade, no spring.
        .animation(visible ? (reduceMotion ? Motion.fadeIn : Motion.snappy) : Motion.fadeOut, value: visible)
    }
}

/// The transport: ⏮ (▶) ⏭, in one of two arrangements (`TransportSize`).
///
/// - `row`: the five-slot grid, `[leading] [⏮] (⏸) [⏭] [more]`. Regular width's Now Playing puts 🔖
///   first and ⋯ last; the Reader puts speed (`1×`) first and ⋯ last. The disc is as tall as the
///   grid's 44 pt row, so every slot (and ⋯) sits where it does on the other surfaces.
/// - `card`: the three alone, centred, larger (the `Control.prominent` disc, `Glyph.large` skips): compact
///   Listen's player card, which sets its tools on either side (`ReaderPlayerCard`); `leading` and
///   `more` are not drawn.
///
/// The play button reads "Play" / "Pause" like any player's.
struct NowPlayingTransport<Leading: View, More: View>: View {
    let state: PlayState
    var size = TransportSize.row
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

    var body: some View {
        Group {
            switch size {
            case .row:
                BottomToolbarLayout {
                    leading
                        .toolbarSlot(0)
                    skip(back: true)
                        .toolbarSlot(1)
                    playPause
                        .frame(height: Control.tap)
                        .toolbarSlot(2)
                    skip(back: false)
                        .toolbarSlot(3)
                    more
                        .toolbarSlot(BottomToolbarLayout.moreSlot)
                }
            case .card:
                HStack(spacing: Spacing.m) {
                    skip(back: true)
                    playPause
                    skip(back: false)
                }
            }
        }
        .tint(reading?.ink ?? Palette.ink)
    }

    private var playPause: some View {
        PlayStateButton(state: state, look: size == .card ? .disc(size: Control.prominent, glyph: Glyph.large) : .disc(), action: onPlayPause)
            .accessibilityLabel(state == .playing ? Verbs.pause : Verbs.play)
            .accessibilityIdentifier("listenPlayPause")
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.6).onEnded { _ in onPlayLongPress?() },
                                 including: onPlayLongPress == nil ? .subviews : .all)
    }

    @ViewBuilder
    private func skip(back: Bool) -> some View {
        Button(action: back ? onSkipBack : onSkipForward) {
            let image = Image(systemName: back ? Icons.previous : Icons.next)
            switch size {
            case .row:
                image.toolbarIconFrame()
            case .card:
                image
                    .font(.system(size: Glyph.large))
                    .frame(width: Control.tap, height: Control.tap)
                    .contentShape(Rectangle())
                    .accessibilityShowsLargeContentViewer()
            }
        }
        .disabled(back ? !canSkipBack : !canSkipForward)
        .accessibilityLabel(back ? "Previous paragraph" : "Next paragraph")
    }
}

/// `NowPlayingTransport`'s arrangement: the five-slot `row`, or the player `card`'s larger three.
enum TransportSize { case row, card }

extension NowPlayingTransport where Leading == EmptyView, More == EmptyView {
    /// The transport with no slots of its own: the player card's.
    init(state: PlayState, size: TransportSize, canSkipBack: Bool = true, canSkipForward: Bool = true,
         onSkipBack: @escaping () -> Void, onSkipForward: @escaping () -> Void, onPlayPause: @escaping () -> Void,
         onPlayLongPress: (() -> Void)? = nil) {
        self.init(state: state, size: size, canSkipBack: canSkipBack, canSkipForward: canSkipForward,
                  onSkipBack: onSkipBack, onSkipForward: onSkipForward, onPlayPause: onPlayPause,
                  onPlayLongPress: onPlayLongPress, leading: { EmptyView() }, more: { EmptyView() })
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
            IconButton(symbol: Icons.textAppearance, label: Verbs.textAppearance, identifier: "previewAa") {}
        } accessory: {
            IconButton(symbol: Icons.jump, label: Verbs.playFromParagraph, identifier: "previewJump") {}
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
                    IconButton(symbol: Icons.voice, label: Verbs.voice, identifier: "previewVoice") {}
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
