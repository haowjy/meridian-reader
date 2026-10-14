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
/// Tap or swipe up opens (`onOpen`); long-press offers Stop Listening when there is `onStop`.
/// While the next chapter loads the state is `.preparing` and `detail` says so.
/// `NowPlayingBar.placeholder` is the same card, greyed, with nothing to open or play: the band
/// shows it before anything has played, so the band keeps its height.
struct NowPlayingBar: View {
    let title: String
    /// Second line, as separate parts (`DetailLine`): the source, then the time left
    /// (["investopedia.com", "12 min left"]); or one part, "Getting next chapter…", "✓ Finished".
    let detail: [String]
    var artwork: Image?
    /// Letter for the artwork tile when there is no image.
    var artworkLetter: String = ""
    /// 0…1 through the page.
    let progress: Double
    let state: PlayState
    /// A sleep timer is set: 🌙 before the detail.
    var sleepTimerSet = false
    /// How many toolbar slots the bar spans, ending at ⋯'s: 5 across the band (the Reader), 4
    /// beside the band's swap (`BottomBandTopRow`). ⏸ sits over the last.
    var spansSlots = BottomToolbarLayout.slotCount
    /// Accessibility identifier; its parts add "Open" and "PlayPause".
    var identifier = "nowPlayingBar"
    let onOpen: () -> Void
    let onPlayPause: () -> Void
    /// Long-press → Stop Listening (nil: no menu).
    let onStop: (() -> Void)?
    /// The greyed stand-in (`placeholder`).
    private var isPlaceholder = false

    /// The bar's width: ⏸ sits over its last slot.
    @State private var width: CGFloat = 0

    static let artworkSize: CGFloat = 36

    init(title: String, detail: [String], artwork: Image? = nil, artworkLetter: String = "", progress: Double,
         state: PlayState, sleepTimerSet: Bool = false, spansSlots: Int = BottomToolbarLayout.slotCount,
         identifier: String = "nowPlayingBar", onOpen: @escaping () -> Void, onPlayPause: @escaping () -> Void,
         onStop: (() -> Void)?) {
        self.title = title
        self.detail = detail
        self.artwork = artwork
        self.artworkLetter = artworkLetter
        self.progress = progress
        self.state = state
        self.sleepTimerSet = sleepTimerSet
        self.spansSlots = spansSlots
        self.identifier = identifier
        self.onOpen = onOpen
        self.onPlayPause = onPlayPause
        self.onStop = onStop
    }

    /// Nothing has played: the bar's shape, greyed, with ▶ dimmed. Same height as the bar at
    /// every text size (same rows, same controls).
    static func placeholder(spansSlots: Int = BottomToolbarLayout.slotCount) -> NowPlayingBar {
        var bar = NowPlayingBar(title: String(localized: "Nothing playing"),
                                detail: [String(localized: "Pick something to play")],
                                artworkLetter: " ", progress: 0, state: .idle, spansSlots: spansSlots,
                                identifier: "nowPlayingBarPlaceholder", onOpen: {}, onPlayPause: {}, onStop: nil)
        bar.isPlaceholder = true
        return bar
    }

    /// Trailing padding that centres a 44 pt control on slot 5 of a full toolbar row `rowWidth`
    /// wide (the Reader's bar; list rows' trailing column).
    static func trailingPadding(rowWidth: CGFloat) -> CGFloat {
        trailingPadding(barWidth: rowWidth, spansSlots: BottomToolbarLayout.slotCount)
    }

    /// Trailing padding that centres a 44 pt play button on the last slot of a bar `barWidth`
    /// wide spanning `spansSlots` toolbar slots.
    static func trailingPadding(barWidth: CGFloat, spansSlots: Int) -> CGFloat {
        guard barWidth > 0, spansSlots > 0 else { return 0 }
        return max(0, barWidth / CGFloat(spansSlots) / 2 - BottomChrome.minTapTarget / 2)
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
                            Image(systemName: "moon.fill")
                                .accessibilityLabel("Sleep timer set")
                        }
                        DetailLine(detail)
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
        .padding(.trailing, Self.trailingPadding(barWidth: width, spansSlots: spansSlots))
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
        .contextMenu {
            if let onStop {
                Button("Stop Listening", systemImage: "stop.fill", action: onStop)
            }
        }
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
                    Image(systemName: "waveform")
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
                bar("Notes on Tides", ["✓ Finished"], 1, .idle)
            }
            PreviewState("nothing playing") {
                NowPlayingBar.placeholder()
            }
        }
    }

    private func bar(_ title: String, _ detail: [String], _ progress: Double, _ state: PlayState,
                     sleep: Bool = false) -> some View {
        NowPlayingBar(title: title, detail: detail, progress: progress, state: state, sleepTimerSet: sleep,
                      onOpen: {}, onPlayPause: {}, onStop: {})
    }
}

#Preview("NowPlayingBar · light", traits: .sizeThatFitsLayout) { NowPlayingBarGallery().previewVariant(.light) }
#Preview("NowPlayingBar · dark", traits: .sizeThatFitsLayout) { NowPlayingBarGallery().previewVariant(.dark) }
#Preview("NowPlayingBar · AX5", traits: .sizeThatFitsLayout) { NowPlayingBarGallery().previewVariant(.largestText) }
#endif
