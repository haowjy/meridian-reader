import SwiftUI

/// What you hear, on every surface except Now Playing: a floating card above the bottom band's
/// field capsule, built on the same `PlayerCard` surface as `ReaderPlayerCard`.
///
/// ```
/// ╭──────────────────────────────────────────╮
/// │ [art]  Chapter 12: Hunsford            ⏸ │   ⏸ / ▶ centred over the ⋯ slot
/// │        Pride and Prejudice   9 min left  │
/// │ [━━━━━━━━━━━━━━━━───────────────────────]│   groove progress line
/// ╰─────────────────────────────────────────╯
/// ```
///
/// Tap or swipe up opens (`onOpen`); long-press shows `menu` (the page's own menu, then Stop
/// Listening); the placeholder has none.
/// While the next chapter loads the state is `.preparing` and `detail` says so.
/// `NowPlayingBar.placeholder` is the same card, greyed, with nothing to open or play: the band
/// shows it when it has nothing to resume (nothing played yet), so the band keeps its height.
/// In the Reader (another page playing) it takes the reading theme's card, inks and accent.
struct NowPlayingBar: View {
    let title: String
    /// Second line, as separate parts (`DetailLine`): the source, then the time left
    /// (["investopedia.com", "12 min left"]); or one part, "Getting next chapter…", `.finished`.
    let detail: [DetailPart]
    var artwork: Image?
    /// Letter for the artwork tile when there is no image.
    var artworkLetter: String = ""
    /// 0…1 through the page.
    let progress: Double
    let state: PlayState
    /// A sleep timer is set: 🌙 before the detail.
    var sleepTimerSet = false
    /// Accessibility identifier; its parts add "Open" and "PlayPause".
    var identifier = "nowPlayingBar"
    let onOpen: () -> Void
    let onPlayPause: () -> Void
    /// The long press's rows (nil: none, the placeholder).
    let menu: AnyView?
    /// The greyed stand-in (`placeholder`).
    private var isPlaceholder = false

    /// The bar's width: it spans a full toolbar row, so ⏸ sits over ⋯'s slot.
    @State private var width: CGFloat = 0
    @Environment(\.readingPalette) private var reading

    init(title: String, detail: [DetailPart], artwork: Image? = nil, artworkLetter: String = "", progress: Double,
         state: PlayState, sleepTimerSet: Bool = false, identifier: String = "nowPlayingBar", onOpen: @escaping () -> Void, onPlayPause: @escaping () -> Void,
         menu: AnyView?) {
        self.title = title
        self.detail = detail
        self.artwork = artwork
        self.artworkLetter = artworkLetter
        self.progress = progress
        self.state = state
        self.sleepTimerSet = sleepTimerSet
        self.identifier = identifier
        self.onOpen = onOpen
        self.onPlayPause = onPlayPause
        self.menu = menu
    }

    /// Nothing to resume: the bar's shape, greyed, with ▶ dimmed. Same height as the bar at
    /// every text size (same rows, same controls).
    static func placeholder() -> NowPlayingBar {
        var bar = NowPlayingBar(title: String(localized: "Nothing playing"),
                                detail: [DetailPart(String(localized: "Pick something to play"))],
                                artworkLetter: " ", progress: 0, state: .idle,
                                identifier: "nowPlayingBarPlaceholder", onOpen: {}, onPlayPause: {}, menu: nil)
        bar.isPlaceholder = true
        return bar
    }

    /// Trailing padding that centres a 44 pt control on slot 5 (⋯'s) of a toolbar row `rowWidth`
    /// wide: the bar's ⏸, list rows' trailing column.
    static func trailingPadding(rowWidth: CGFloat) -> CGFloat {
        guard rowWidth > 0 else { return 0 }
        return max(0, BottomToolbarLayout.slotWidth(rowWidth: rowWidth) / 2 - BottomChrome.minTapTarget / 2)
    }

    var body: some View {
        VStack(spacing: Spacing.xxs) {
            HStack(spacing: Spacing.s) {
                HStack(spacing: Spacing.s) {
                    artworkTile
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title)
                            .typeStyle(.row, weight: .semibold)
                            .foregroundStyle(isPlaceholder ? quietInk : reading?.ink ?? Palette.ink)
                            .lineLimit(1)
                        HStack(spacing: Spacing.xxs) {
                            if sleepTimerSet {
                                Image(systemName: Icons.sleepTimer)
                                    .accessibilityLabel("Sleep timer set")
                            }
                            DetailLine(parts: detail)
                        }
                        .typeStyle(.caption)
                        .foregroundStyle(isPlaceholder ? quietInk : reading?.secondaryInk ?? Palette.secondaryInk)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpen)
                .gesture(DragGesture(minimumDistance: SwipeGesturePolicy.verticalMinimumDistance).onEnded { v in
                    if v.translation.height < -SwipeGesturePolicy.verticalMinimumDistance { onOpen() }
                })
                .allowsHitTesting(!isPlaceholder)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(isPlaceholder ? [] : .isButton)
                .accessibilityHint(isPlaceholder ? "" : "Opens Now Playing")
                .accessibilityAction(.default, onOpen)
                .accessibilityIdentifier(identifier + "Open")

                PlayStateButton(state: state, action: onPlayPause)
                    .disabled(isPlaceholder)
                    .opacity(isPlaceholder ? Palette.disabledOpacity : 1)
                    .accessibilityHidden(isPlaceholder)
                    .accessibilityIdentifier(identifier + "PlayPause")
            }
            .padding(.trailing, Self.trailingPadding(rowWidth: width))

            ProgressLine(fraction: progress, height: PlayerCard.progressHeight, track: .groove)
                .padding(.trailing, Spacing.s)
                .opacity(isPlaceholder ? 0 : 1)
                .accessibilityHidden(true)
        }
        .padding(.leading, Spacing.s)
        .padding(.vertical, Spacing.xs)
        .playerCardSurface()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { if $0 != width { width = $0 } }
        .contextMenu { if let menu { menu } }
        .accessibilityElement(children: .contain)
        .accessibilityValue(isPlaceholder ? "" : "\(Int((progress * 100).rounded())) percent")
        .accessibilityIdentifier(identifier)
    }

    private var quietInk: Color { reading?.tertiaryInk ?? Palette.tertiaryInk }

    @ViewBuilder
    private var artworkTile: some View {
        if isPlaceholder {
            ArtworkTile(letter: " ", size: PlayerCard.artworkSize)
                .overlay {
                    Image(systemName: Icons.playing)
                        .font(.caption)
                        .foregroundStyle(quietInk)
                        .accessibilityHidden(true)
                }
        } else {
            ArtworkTile(image: artwork, letter: artworkLetter.isEmpty ? title : artworkLetter, size: PlayerCard.artworkSize)
        }
    }
}

#if DEBUG
struct NowPlayingBarGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("playing") {
                bar("Seven-Day Yield: Definition, Calculation", ["investopedia.com", "12 min left"], 0.58, .playing)
            }
            PreviewState("paused, sleep timer") {
                bar("Chapter 12: Hunsford", ["Pride and Prejudice", "9 min left"], 0.2, .paused,
                    sleep: true)
            }
            PreviewState("getting next chapter") {
                bar("Chapter 13", ["Getting next chapter…"], 0, .preparing)
            }
            PreviewState("finished") {
                bar("Notes on Tides", [.finished], 1, .idle)
            }
            PreviewState("nothing playing") {
                NowPlayingBar.placeholder()
            }
        }
    }

    private func bar(_ title: String, _ detail: [DetailPart], _ progress: Double, _ state: PlayState,
                     sleep: Bool = false) -> some View {
        NowPlayingBar(title: title, detail: detail, progress: progress, state: state, sleepTimerSet: sleep,
                      onOpen: {}, onPlayPause: {}, menu: nil)
    }
}

#Preview("NowPlayingBar · light", traits: .sizeThatFitsLayout) { NowPlayingBarGallery().previewVariant(.light) }
#Preview("NowPlayingBar · dark", traits: .sizeThatFitsLayout) { NowPlayingBarGallery().previewVariant(.dark) }
#Preview("NowPlayingBar · AX5", traits: .sizeThatFitsLayout) { NowPlayingBarGallery().previewVariant(.largestText) }
#endif
