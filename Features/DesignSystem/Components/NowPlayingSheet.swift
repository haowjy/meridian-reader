import SwiftUI

/// What you hear, opened up: a `Sheet` over everything that shrinks back into the Now Playing
/// bar. It looks like the Reader (paper, serif, margins); its chrome is the player's.
///
/// ```
/// ┌──────────────────────────────────────┐
/// │  ⌄          PLAYING FROM          ⊕  │ ← ⌄ or a pull down shrinks it; ⊕ saves (✓ saved)
/// │          Pride and Prejudice         │ ← tap: go there
/// │ … `text`: follows the audio …        │
/// │            ( ↓ Back to audio )       │ ← after you scroll away
/// │ `controls`: status notes, the        │
/// │ scrubber, [1×] [⏮] [⏸] [⏭] [⋯]       │ ← in the bottom band
/// └──────────────────────────────────────┘
/// ```
struct NowPlayingSheet<Reading: View, Controls: View>: View {
    /// The book, series or folder the page lives in, else its site.
    let playingFrom: String
    let isSaved: Bool
    /// The text scrolled away from the spoken paragraph: offer to go back.
    var showsBackToAudio = false
    let onCollapse: () -> Void
    var onPlayingFrom: () -> Void = {}
    var onToggleSave: () -> Void = {}
    var onBackToAudio: () -> Void = {}
    @ViewBuilder var text: Reading
    /// Status notes, the scrubber and the transport row, stacked in the bottom band.
    @ViewBuilder var controls: Controls

    var body: some View {
        Sheet(onDismiss: onCollapse) {
            NowPlayingHeader(playingFrom: playingFrom, isSaved: isSaved, onPlayingFrom: onPlayingFrom,
                             onToggleSave: onToggleSave)
        } content: {
            text
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .safeAreaInset(edge: .bottom, spacing: 0) { bottom }
        }
    }

    private var bottom: some View {
        VStack(spacing: Spacing.xs) {
            if showsBackToAudio {
                PillButton("Back to audio", systemImage: "arrow.down", style: .inverted, size: .compact,
                           action: onBackToAudio)
                    .floatingShadow(opacity: 0.2)
                    .accessibilityIdentifier("nowPlayingBackToAudio")
                    .transition(.opacity)
            }
            VStack(spacing: BottomChrome.rowSpacing) { controls }
                .bottomChromeBand()
        }
        .animation(Motion.snappy, value: showsBackToAudio)
    }
}

/// Now Playing's transport row in the five-slot grid: `[1×] [⏮] [▶ / ⏸] [⏭] [more]`. The play
/// button reads "Play" / "Pause" like any player's.
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

    var body: some View {
        BottomToolbarLayout {
            Button(action: onRate) { Text(rateLabel).toolbarTextFrame() }
                .accessibilityLabel("Speed \(rateLabel)")
                .accessibilityIdentifier("listenSpeed")
            Button(action: onSkipBack) { Image(systemName: "backward.end.fill").toolbarIconFrame() }
                .disabled(!canSkipBack)
                .accessibilityLabel("Previous paragraph")
            PlayStateButton(state: state, action: onPlayPause)
                .accessibilityLabel(state == .playing ? "Pause" : "Play")
                .accessibilityIdentifier("listenPlayPause")
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.6).onEnded { _ in onPlayLongPress?() },
                                     including: onPlayLongPress == nil ? .subviews : .all)
            Button(action: onSkipForward) { Image(systemName: "forward.end.fill").toolbarIconFrame() }
                .disabled(!canSkipForward)
                .accessibilityLabel("Next paragraph")
            more
        }
        .tint(Palette.ink)
    }
}

/// ⌄, "Playing from <name>", ⊕.
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
                        .foregroundStyle(Palette.secondaryInk)
                    Text(playingFrom)
                        .typeStyle(.row, weight: .semibold)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Playing from \(playingFrom)")
            .accessibilityIdentifier("nowPlayingFrom")

            Button(action: onToggleSave) {
                Image(systemName: isSaved ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(isSaved ? Palette.accent : Palette.ink)
                    .toolbarIconFrame()
            }
            .frame(width: BottomChrome.minTapTarget)
            .accessibilityLabel(isSaved ? "Remove from Library" : "Save to Library")
            .accessibilityValue(isSaved ? "Saved" : "Not saved")
            .accessibilityIdentifier("readerBookmark")
        }
        .tint(Palette.ink)
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
        NowPlayingSheet(playingFrom: "Pride and Prejudice", isSaved: saved, showsBackToAudio: back,
                        onCollapse: {}) {
            SampleReading(title: "Chapter 12", detail: "Jane Austen · 15 min", spoken: true)
        } controls: {
            if let note {
                Text(note)
                    .typeStyle(.caption)
                    .foregroundStyle(Palette.secondaryInk)
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
