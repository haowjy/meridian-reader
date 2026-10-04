import SwiftUI

/// What you hear, on every surface except Now Playing: a floating card above the bottom band's
/// field capsule.
///
/// ```
/// ╭──────────────────────────────────────────╮
/// │ [art]  Chapter 12: Hunsford            ⏸ │   ⏸ / ▶ centred over the ⋯ slot
/// │        Pride and Prejudice · Ch 12 · 9m  │
/// ╰━━━━━━━━━━━━━━━━━━━━━━━━──────────────────╯   progress along the bottom edge
/// ```
///
/// Tap or swipe up opens Now Playing (`onOpen`); long-press offers Stop Listening (`onStop`).
/// While the next chapter loads the state is `.preparing` and `detail` says so.
struct NowPlayingBar: View {
    let title: String
    /// Second line: "<source> · N min left", "Getting next chapter…", "✓ Finished".
    let detail: String
    var artwork: Image?
    /// Letter for the artwork tile when there is no image.
    var artworkLetter: String = ""
    /// 0…1 through the page.
    let progress: Double
    let state: PlayState
    /// A sleep timer is set: 🌙 before the detail.
    var sleepTimerSet = false
    let onOpen: () -> Void
    let onPlayPause: () -> Void
    let onStop: () -> Void

    /// The bar's width (= the toolbar row's): ⏸ sits over slot 5.
    @State private var width: CGFloat = 0

    static let artworkSize: CGFloat = 36

    /// Trailing padding that centres a 44 pt play button on slot 5 of `BottomToolbarLayout`.
    static func trailingPadding(rowWidth: CGFloat) -> CGFloat {
        guard rowWidth > 0 else { return 0 }
        return max(0, BottomToolbarLayout.slotWidth(rowWidth: rowWidth) / 2 - BottomChrome.minTapTarget / 2)
    }

    var body: some View {
        HStack(spacing: Spacing.s) {
            HStack(spacing: Spacing.s) {
                ArtworkTile(image: artwork, letter: artworkLetter.isEmpty ? title : artworkLetter,
                            size: Self.artworkSize)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .typeStyle(.row, weight: .semibold)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    HStack(spacing: Spacing.xxs) {
                        if sleepTimerSet {
                            Image(systemName: "moon.fill")
                                .accessibilityLabel("Sleep timer set")
                        }
                        Text(detail).lineLimit(1)
                    }
                    .typeStyle(.caption)
                    .foregroundStyle(Palette.secondaryInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
            .gesture(DragGesture(minimumDistance: SwipeGesturePolicy.verticalMinimumDistance).onEnded { v in
                if v.translation.height < -SwipeGesturePolicy.verticalMinimumDistance { onOpen() }
            })
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens Now Playing")
            .accessibilityAction(.default, onOpen)

            PlayStateButton(state: state, action: onPlayPause)
        }
        .padding(.leading, Spacing.xs)
        .padding(.trailing, Self.trailingPadding(rowWidth: width))
        .padding(.vertical, Spacing.xs)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(alignment: .bottom) {
            GeometryReader { g in
                Palette.accent
                    .frame(width: g.size.width * min(max(0, progress), 1), height: 3)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .floatingShadow()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { if $0 != width { width = $0 } }
        .contextMenu {
            Button("Stop Listening", systemImage: "stop.fill", action: onStop)
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue("\(Int((progress * 100).rounded())) percent")
    }
}

#if DEBUG
struct NowPlayingBarGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("playing") {
                bar("Seven-Day Yield: Definition, Calculation", "investopedia.com · 12 min left", 0.58, .playing)
            }
            PreviewState("paused, sleep timer") {
                bar("Chapter 12: Hunsford", "Pride and Prejudice · Ch 12 · 9 min left", 0.2, .paused,
                    sleep: true)
            }
            PreviewState("getting next chapter") {
                bar("Chapter 13", "Getting next chapter…", 0, .preparing)
            }
            PreviewState("finished") {
                bar("Notes on Tides", "✓ Finished", 1, .idle)
            }
        }
    }

    private func bar(_ title: String, _ detail: String, _ progress: Double, _ state: PlayState,
                     sleep: Bool = false) -> some View {
        NowPlayingBar(title: title, detail: detail, progress: progress, state: state, sleepTimerSet: sleep,
                      onOpen: {}, onPlayPause: {}, onStop: {})
    }
}

#Preview("NowPlayingBar · light", traits: .sizeThatFitsLayout) { NowPlayingBarGallery().previewVariant(.light) }
#Preview("NowPlayingBar · dark", traits: .sizeThatFitsLayout) { NowPlayingBarGallery().previewVariant(.dark) }
#Preview("NowPlayingBar · AX5", traits: .sizeThatFitsLayout) { NowPlayingBarGallery().previewVariant(.largestText) }
#endif
