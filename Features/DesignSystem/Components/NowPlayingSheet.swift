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
/// │ 🌙 Sleep in 23 min                   │ ← `note`
/// │ ( ━━━━●━━░░──  6:10 · 9 min left )   │
/// │ [1×]  [⏮]  [⏸]  [⏭]  [ ⋯ ]          │
/// └──────────────────────────────────────┘
/// ```
struct NowPlayingSheet<Reading: View, More: View>: View {
    /// The scrubber's values.
    struct Position {
        var value: Double
        var buffered: [ClosedRange<Double>] = []
        var elapsed: String
        var remaining: String
    }

    /// The book, series or folder the page lives in, else its site.
    let playingFrom: String
    let isSaved: Bool
    let state: PlayState
    let position: Position
    /// "1×", "1.25×".
    let rateLabel: String
    /// A status note above the scrubber ("🌙 Sleep in 23 min", "✓ Finished").
    var note: String?
    /// The reader scrolled away from the spoken paragraph: offer to go back.
    var showsBackToAudio = false
    var canSkipBack = true
    var canSkipForward = true
    let onCollapse: () -> Void
    var onPlayingFrom: () -> Void = {}
    var onToggleSave: () -> Void = {}
    var onBackToAudio: () -> Void = {}
    var onScrub: (Double?) -> Void = { _ in }
    let onSeek: (Double) -> Void
    let onRate: () -> Void
    let onSkipBack: () -> Void
    let onSkipForward: () -> Void
    let onPlayPause: () -> Void
    @ViewBuilder var text: Reading
    @ViewBuilder var more: More

    var body: some View {
        Sheet(onDismiss: onCollapse) {
            NowPlayingHeader(playingFrom: playingFrom, isSaved: isSaved, onPlayingFrom: onPlayingFrom,
                             onToggleSave: onToggleSave)
        } content: {
            text
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .safeAreaInset(edge: .bottom, spacing: 0) { controls }
        }
    }

    private var controls: some View {
        VStack(spacing: Spacing.xs) {
            if showsBackToAudio {
                PillButton("Back to audio", systemImage: "arrow.down", style: .inverted, size: .compact,
                           action: onBackToAudio)
                    .floatingShadow(opacity: 0.2)
                    .transition(.opacity)
            }
            VStack(spacing: BottomChrome.rowSpacing) {
                if let note {
                    Text(note)
                        .typeStyle(.caption)
                        .foregroundStyle(Palette.secondaryInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Spacing.xs)
                }
                ScrubBar(value: position.value, buffered: position.buffered, elapsed: position.elapsed,
                         remaining: position.remaining, onScrub: onScrub, onCommit: onSeek)
                BottomToolbarLayout {
                    Button(action: onRate) { Text(rateLabel).toolbarTextFrame() }
                        .accessibilityLabel("Speed \(rateLabel)")
                    Button(action: onSkipBack) { Image(systemName: "backward.end.fill").toolbarIconFrame() }
                        .disabled(!canSkipBack)
                        .accessibilityLabel("Previous paragraph")
                    PlayStateButton(state: state, action: onPlayPause)
                    Button(action: onSkipForward) { Image(systemName: "forward.end.fill").toolbarIconFrame() }
                        .disabled(!canSkipForward)
                        .accessibilityLabel("Next paragraph")
                    more
                }
                .tint(Palette.ink)
            }
            .bottomChromeBand()
        }
        .animation(Motion.snappy, value: showsBackToAudio)
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

            Button(action: onToggleSave) {
                Image(systemName: isSaved ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(isSaved ? Palette.accent : Palette.ink)
                    .toolbarIconFrame()
            }
            .frame(width: BottomChrome.minTapTarget)
            .accessibilityLabel(isSaved ? "Saved" : "Save to Library")
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
        NowPlayingSheet(
            playingFrom: "Pride and Prejudice", isSaved: saved, state: state,
            position: .init(value: 0.42, buffered: [0.42...0.6], elapsed: "6:10", remaining: "9 min left"),
            rateLabel: "1×", note: note, showsBackToAudio: back,
            onCollapse: {}, onSeek: { _ in }, onRate: {}, onSkipBack: {}, onSkipForward: {}, onPlayPause: {}
        ) {
            SampleReading(title: "Chapter 12", detail: "Jane Austen · 15 min", spoken: true)
        } more: {
            Image(systemName: "ellipsis").toolbarIconFrame()
        }
        .frame(height: 700)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
    }
}

#Preview("NowPlayingSheet · light", traits: .sizeThatFitsLayout) { NowPlayingSheetGallery().previewVariant(.light) }
#Preview("NowPlayingSheet · dark", traits: .sizeThatFitsLayout) { NowPlayingSheetGallery().previewVariant(.dark) }
#Preview("NowPlayingSheet · AX5", traits: .sizeThatFitsLayout) { NowPlayingSheetGallery().previewVariant(.largestText) }
#endif
