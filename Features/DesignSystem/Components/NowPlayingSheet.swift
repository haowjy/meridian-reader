import SwiftUI

/// What you hear, opened up: a `Sheet` over everything that shrinks back into the Now Playing
/// bar, in the Reader's colours and type (the reading theme, `palette`): the spoken paragraph
/// highlighted in full ink, the others dimmed.
///
/// ```
/// ┌──────────────────────────────────────┐
/// │                 ───                  │ <- grabber
/// │ ( v Pride and Prejudice ) (Aa) (^)  │ <- `SheetTopBar`, as in the Reader: the pill names
/// │ `banner` (the ^ hint, while on)      │   where it plays from and shrinks it; Aa, `accessory`
/// │ `text`: dimmed, SPOKEN in full ink   │ <- fills the sheet, under the header and the band;
/// │         dimmed                       │   follows the audio
/// │            ( Jump to Audio )         │ <- after you scroll away, bars up only (C128)
/// │ ─────────────────────────────────────│ <- hairline divider
/// │ Title                     time left  │
/// │ source                               │
/// │ [━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━] │ <- scrub row
/// │ [🔖]  [⏮]    (⏸)    [⏭]   [⋯]      │ <- transport
/// └──────────────────────────────────────┘
/// ```
///
/// It goes full screen as the Reader does (`ReadingChrome`): the floating play / pause is
/// `playState` / `onPlayPause`, the only control over the text then; Jump to Audio shows only with
/// the bars up (C128). The pill, the grabber and a pull down shrink it (`onCollapse`, after it has
/// gone). `floating` floats just above the bottom band's hairline (a toast), as in the Reader.
struct NowPlayingSheet<Band: View, Reading: View, TextAppearance: View, Accessory: View, Banner: View,
                       Floating: View>: View {
    /// The book, series or folder the page lives in, else the Library or its site.
    let playingFrom: String
    /// What you hear, for the play / pause floating in full screen.
    let playState: PlayState
    /// The text scrolled away from the audio: offer to jump back to the spoken sentence.
    var showsJumpToAudio = false
    let onCollapse: () -> Void
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
        Sheet(onDismiss: onCollapse, palette: palette, chrome: chrome) {
            VStack(spacing: 0) {
                SheetTopBar { SheetClosePill(kind: .collapse(playingFrom)) } trailing: {
                    textAppearance
                    accessory
                }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("nowPlayingHeader")
                banner
            }
        } content: {
            text
        } band: {
            ReadingBottomBand {
                band
            } floating: {
                floating
            }
        } overText: {
            ZStack(alignment: .bottom) {
                jumpToAudio
                FloatingPlayButton(state: playState, action: onPlayPause)
            }
        }
    }

    /// Floats over the text, so the text keeps running under it. No arrow: the spoken sentence
    /// may be above or below. Inverted: an ink pill with the page's colour for its text.
    private var jumpToAudio: some View {
        let shows = chrome.showsJumpToAudio(awayFromAudio: showsJumpToAudio)
        return ZStack {
            if shows {
                PillButton("Jump to Audio", style: .inverted, size: .compact, action: onJumpToAudio)
                    .overTextShadow()
                    .accessibilityIdentifier("nowPlayingJumpToAudio")
                    .transition(.opacity)
            }
        }
        .animation(Motion.snappy, value: shows)
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
        return NowPlayingSheet(playingFrom: "Pride and Prejudice", playState: state, showsJumpToAudio: back,
                               onCollapse: {}, onPlayPause: {}, palette: palette) {
            TextAppearanceButton(isOpen: false) {}
        } accessory: {
            JumpModeButton(isOn: false) {}
        } banner: {
            EmptyView()
        } text: {
            SampleReading(title: "Chapter 12", detail: ["Pride and Prejudice", "9 min left"], spoken: true, card: true)
        } band: {
            VStack(spacing: Spacing.xs) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Chapter 12: Hunsford").typeStyle(.row, weight: .semibold).lineLimit(1)
                        .foregroundStyle(palette.ink)
                    Text("9 min left").typeStyle(.caption).foregroundStyle(palette.secondaryInk).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
