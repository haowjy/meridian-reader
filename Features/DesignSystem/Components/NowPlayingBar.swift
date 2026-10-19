import SwiftUI

/// What you hear, on every surface except Now Playing: a floating card above the bottom band's
/// field capsule.
///
/// ```
/// ╭──────────────────────────────────────────╮
/// │ [art]  Chapter 12: Hunsford            ⏸ │   ⏸ / ▶ centred over the ⋯ slot
/// │        Pride and Prejudice   9 min left  │
/// ╰━━━━━━━━━━━━━━━━━━━━━━━━──────────────────╯   progress along the bottom edge
/// ```
///
/// Tap or swipe up opens (`onOpen`); long-press shows `menu` (the page's own menu, then Stop
/// Listening); the placeholder has none.
/// While the next chapter loads the state is `.preparing` and `detail` says so.
/// `NowPlayingBar.placeholder` is the same card, greyed, with nothing to open or play: the band
/// shows it when it has nothing to resume (nothing played yet), so the band keeps its height.
struct NowPlayingBar: View {
    let title: String
    /// Second line, as separate parts (`DetailLine`): the source, then the time left
    /// (["investopedia.com", "12 min left"]); or one part, "Getting next chapter…", "Finished"
    /// (after `detailSymbol`, ✓).
    let detail: [String]
    var detailSymbol: String?
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

    static let artworkSize: CGFloat = 36

    init(title: String, detail: [String], detailSymbol: String? = nil, artwork: Image? = nil, artworkLetter: String = "", progress: Double,
         state: PlayState, sleepTimerSet: Bool = false, identifier: String = "nowPlayingBar", onOpen: @escaping () -> Void, onPlayPause: @escaping () -> Void,
         menu: AnyView?) {
        self.title = title
        self.detail = detail
        self.detailSymbol = detailSymbol
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
                                detail: [String(localized: "Pick something to play")],
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
        HStack(spacing: Spacing.s) {
            HStack(spacing: Spacing.s) {
                artworkTile
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .typeStyle(.row, weight: .semibold)
                        .foregroundStyle(isPlaceholder ? Palette.tertiaryInk : Palette.ink)
                        .lineLimit(1)
                    HStack(spacing: Spacing.xxs) {
                        if sleepTimerSet {
                            Image(systemName: Icons.sleepTimer)
                                .accessibilityLabel("Sleep timer set")
                        }
                        DetailLine(detail, symbol: detailSymbol)
                    }
                    .typeStyle(.caption)
                    .foregroundStyle(isPlaceholder ? Palette.tertiaryInk : Palette.secondaryInk)
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
        .padding(.leading, Spacing.xs)
        .padding(.trailing, Self.trailingPadding(rowWidth: width))
        .padding(.vertical, Spacing.xs)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(alignment: .bottom) {
            if !isPlaceholder {
                GeometryReader { g in
                    Palette.accent
                        .frame(width: g.size.width * min(max(0, progress), 1), height: 3)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .floatingShadow(opacity: isPlaceholder ? Self.placeholderShadowOpacity : 0.14)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { if $0 != width { width = $0 } }
        .contextMenu { if let menu { menu } }
        .accessibilityElement(children: .contain)
        .accessibilityValue(isPlaceholder ? "" : "\(Int((progress * 100).rounded())) percent")
        .accessibilityIdentifier(identifier)
    }

    /// The placeholder sits flatter than a live card.
    private static let placeholderShadowOpacity = 0.05

    @ViewBuilder
    private var artworkTile: some View {
        if isPlaceholder {
            ArtworkTile(letter: " ", size: Self.artworkSize)
                .overlay {
                    Image(systemName: Icons.playing)
                        .font(.caption)
                        .foregroundStyle(Palette.tertiaryInk)
                        .accessibilityHidden(true)
                }
        } else {
            ArtworkTile(image: artwork, letter: artworkLetter.isEmpty ? title : artworkLetter, size: Self.artworkSize)
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
                NowPlayingBar(title: "Notes on Tides", detail: [ListeningTime.finishedLabel], detailSymbol: Icons.checkmark,
                              progress: 1, state: .idle, onOpen: {}, onPlayPause: {}, menu: nil)
            }
            PreviewState("nothing playing") {
                NowPlayingBar.placeholder()
            }
        }
    }

    private func bar(_ title: String, _ detail: [String], _ progress: Double, _ state: PlayState,
                     sleep: Bool = false) -> some View {
        NowPlayingBar(title: title, detail: detail, progress: progress, state: state, sleepTimerSet: sleep,
                      onOpen: {}, onPlayPause: {}, menu: nil)
    }
}

#Preview("NowPlayingBar · light", traits: .sizeThatFitsLayout) { NowPlayingBarGallery().previewVariant(.light) }
#Preview("NowPlayingBar · dark", traits: .sizeThatFitsLayout) { NowPlayingBarGallery().previewVariant(.dark) }
#Preview("NowPlayingBar · AX5", traits: .sizeThatFitsLayout) { NowPlayingBarGallery().previewVariant(.largestText) }
#endif
