import SwiftUI

/// What you hear, opened up: a `Sheet` over everything that shrinks back into the Now Playing
/// bar. A player, not a page: deep jade in light and dark (`SheetLook.player`), the text in the
/// Reader's serif but lyrics style (`ReadingStyle.Look.player`), under a title card.
///
/// ```
/// ┌──────────────────────────────────────┐
/// │  ⌄          PLAYING FROM          ⊕  │ ← ⌄ or a pull down shrinks it; ⊕ saves (✓ saved)
/// │          Pride and Prejudice         │ ← tap: go there
/// │ `text`: [▣ title, site  N min left]  │ ← the title card scrolls with the text
/// │  dimmed, SPOKEN in full ink, dimmed  │ ← follows the audio
/// │            ( Jump to Audio )         │ ← after you scroll away, floating over the text
/// │ `controls`: status notes, the        │
/// │ scrubber, [1×] [⏮] (⏸) [⏭] [⋯]       │ ← in the bottom band, the big round ⏸ in the middle
/// └──────────────────────────────────────┘
/// ```
struct NowPlayingSheet<Reading: View, Controls: View>: View {
    /// The book, series or folder the page lives in, else its site.
    let playingFrom: String
    let isSaved: Bool
    /// The text scrolled away from the audio: offer to jump back to the spoken sentence.
    var showsJumpToAudio = false
    let onCollapse: () -> Void
    var onPlayingFrom: () -> Void = {}
    var onToggleSave: () -> Void = {}
    var onJumpToAudio: () -> Void = {}
    @ViewBuilder var text: Reading
    /// Status notes, the scrubber and the transport row, stacked in the bottom band.
    @ViewBuilder var controls: Controls

    var body: some View {
        Sheet(onDismiss: onCollapse, look: .player) {
            NowPlayingHeader(playingFrom: playingFrom, isSaved: isSaved, onPlayingFrom: onPlayingFrom,
                             onToggleSave: onToggleSave)
        } content: {
            text
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .overlay(alignment: .bottom) { jumpToAudio }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: BottomChrome.rowSpacing) { controls }
                        .bottomChromeBand()
                }
        }
    }

    /// Floats over the text, so the text keeps running under it. No arrow: the spoken sentence
    /// may be above or below. Inverted on the player's dark scheme: a light pill, dark text.
    private var jumpToAudio: some View {
        ZStack {
            if showsJumpToAudio {
                PillButton("Jump to Audio", style: .inverted, size: .compact, action: onJumpToAudio)
                    .floatingShadow(opacity: 0.2)
                    .accessibilityIdentifier("nowPlayingJumpToAudio")
                    .transition(.opacity)
            }
        }
        .padding(.bottom, Spacing.s)
        .animation(Motion.snappy, value: showsJumpToAudio)
    }
}

/// Now Playing's transport row in the five-slot grid: `[1×] [⏮] (⏸) [⏭] [more]`. The play
/// button is the big round disc and reads "Play" / "Pause" like any player's. The row keeps the
/// grid's 44 pt height, so every slot (and ⋯) sits where it does on the other surfaces; the
/// disc reaches past it by half the difference. The row keeps that room above it, and below it
/// too where the home indicator's inset doesn't already give it (a phone with a Home button).
struct NowPlayingTransport<More: View>: View {
    let state: PlayState
    let rateLabel: String
    var canSkipBack = true
    var canSkipForward = true
    let onRate: () -> Void
    let onSkipBack: () -> Void
    let onSkipForward: () -> Void
    let onPlayPause: () -> Void
    /// Long-press on play / pause (developer options: the listen debug panel); nil = none.
    var onPlayLongPress: (() -> Void)?
    @ViewBuilder var more: More

    @Environment(\.onPlayerPalette) private var onPlayer
    @State private var bottomInset: CGFloat = 0

    private static var discOverhang: CGFloat {
        (BottomChrome.transportDiscSize - BottomChrome.rowHeight) / 2
    }

    var body: some View {
        BottomToolbarLayout {
            Button(action: onRate) { Text(rateLabel).toolbarTextFrame() }
                .accessibilityLabel("Speed \(rateLabel)")
                .accessibilityIdentifier("listenSpeed")
                .toolbarSlot(0)
            Button(action: onSkipBack) { Image(systemName: "backward.end.fill").toolbarIconFrame() }
                .disabled(!canSkipBack)
                .accessibilityLabel("Previous paragraph")
                .toolbarSlot(1)
            PlayStateButton(state: state, look: .disc, action: onPlayPause)
                .accessibilityLabel(state == .playing ? "Pause" : "Play")
                .accessibilityIdentifier("listenPlayPause")
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.6).onEnded { _ in onPlayLongPress?() },
                                     including: onPlayLongPress == nil ? .subviews : .all)
                .frame(height: BottomChrome.rowHeight)
                .toolbarSlot(2)
            Button(action: onSkipForward) { Image(systemName: "forward.end.fill").toolbarIconFrame() }
                .disabled(!canSkipForward)
                .accessibilityLabel("Next paragraph")
                .toolbarSlot(3)
            more
                .toolbarSlot(BottomToolbarLayout.moreSlot)
        }
        .padding(.top, Self.discOverhang)
        .padding(.bottom, max(0, Self.discOverhang - bottomInset))
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomInset = $0 }
        .tint(onPlayer ? Palette.playerInk : Palette.ink)
    }
}

/// ⌄, "Playing from <name>", ⊕, on the player palette.
private struct NowPlayingHeader: View {
    let playingFrom: String
    let isSaved: Bool
    let onPlayingFrom: () -> Void
    let onToggleSave: () -> Void

    @Environment(\.dismissSheet) private var dismissSheet

    var body: some View {
        HStack(spacing: 0) {
            Button { dismissSheet() } label: {
                Image(systemName: "chevron.down").toolbarIconFrame()
            }
            .frame(width: BottomChrome.minTapTarget)
            .accessibilityLabel("Close Now Playing")
            .accessibilityIdentifier("readerClose")

            Button(action: onPlayingFrom) {
                VStack(spacing: 0) {
                    Text("PLAYING FROM")
                        .typeStyle(.caption)
                        .tracking(1)
                        .foregroundStyle(Palette.playerSecondaryInk)
                    Text(playingFrom)
                        .typeStyle(.row, weight: .semibold)
                        .foregroundStyle(Palette.playerInk)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Playing from \(playingFrom)")
            .accessibilityIdentifier("nowPlayingFrom")

            Button(action: onToggleSave) {
                Image(systemName: isSaved ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(isSaved ? Palette.playerAccent : Palette.playerInk)
                    .toolbarIconFrame()
            }
            .frame(width: BottomChrome.minTapTarget)
            .accessibilityLabel(isSaved ? "Remove from Library" : "Save to Library")
            .accessibilityValue(isSaved ? "Saved" : "Not saved")
            .accessibilityIdentifier("readerBookmark")
        }
        .tint(Palette.playerInk)
        .padding(.horizontal, Spacing.xs)
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
        NowPlayingSheet(playingFrom: "Pride and Prejudice", isSaved: saved, showsJumpToAudio: back,
                        onCollapse: {}) {
            SampleReading(title: "Chapter 12", detail: ["Pride and Prejudice", "9 min left"], spoken: true,
                          look: .player)
        } controls: {
            if let note {
                Text(note)
                    .typeStyle(.caption)
                    .foregroundStyle(Palette.playerSecondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.xs)
            }
            ScrubBar(value: 0.42, buffered: [0.42...0.6], elapsed: "6:10", remaining: "9 min left") { _ in }
            NowPlayingTransport(state: state, rateLabel: "1×", onRate: {}, onSkipBack: {}, onSkipForward: {},
                                onPlayPause: {}) {
                Image(systemName: "ellipsis").toolbarIconFrame()
            }
        }
        .frame(height: 700)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
    }
}

#Preview("NowPlayingSheet · light", traits: .sizeThatFitsLayout) { NowPlayingSheetGallery().previewVariant(.light) }
#Preview("NowPlayingSheet · dark", traits: .sizeThatFitsLayout) { NowPlayingSheetGallery().previewVariant(.dark) }
#Preview("NowPlayingSheet · AX5", traits: .sizeThatFitsLayout) { NowPlayingSheetGallery().previewVariant(.largestText) }
#endif
