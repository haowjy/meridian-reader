import SwiftUI

/// The scrubber's look: track, buffered spans, fill and thumb, at `value` (0…1). Grows a little
/// while dragged. Draws only; the owner handles the drag (`ScrubBar`, the Reader's scrub row).
/// On the player the fill and thumb are `playerInk` on a `playerTrack` track.
struct ScrubTrack: View {
    let value: Double
    /// Spans that already have audio, as fractions of the track.
    var buffered: [ClosedRange<Double>] = []
    var isDragging = false

    @Environment(\.onPlayerPalette) private var onPlayer

    var body: some View {
        let fill = onPlayer ? Palette.playerInk : Palette.accent
        let empty = onPlayer ? Palette.playerTrack : Palette.secondaryInk.opacity(0.22)
        GeometryReader { g in
            let w = max(1, g.size.width)
            let shown = min(max(0, value), 1)
            let thumb: CGFloat = isDragging ? 20 : 12
            let track: CGFloat = isDragging ? 6 : 4
            ZStack(alignment: .leading) {
                Capsule().fill(empty).frame(height: track)
                ForEach(Array(buffered.enumerated()), id: \.offset) { _, span in
                    Capsule()
                        .fill(fill.opacity(0.28))
                        .frame(width: max(track, w * (span.upperBound - span.lowerBound)), height: track)
                        .offset(x: w * span.lowerBound)
                }
                .accessibilityHidden(true)
                Capsule().fill(fill).frame(width: w * shown, height: track)
                Circle()
                    .fill(fill)
                    .frame(width: thumb, height: thumb)
                    .shadow(color: .black.opacity(isDragging ? 0.18 : 0), radius: 3, y: 1)
                    .offset(x: w * shown - thumb / 2)
            }
            .frame(width: w, height: g.size.height)
        }
    }
}

/// Now Playing's scrubber in a field capsule, with the time played and left after it:
///
/// ```
/// ( ━━━━━●━━░░───────  6:10   9 min left )
/// ```
///
/// The time played and the time left are separate parts (`DetailLine`): the time played in
/// secondary ink, the time left after it in tertiary.
///
/// Dragging reports the fraction under the finger (`onScrub`) and, on release, the fraction to
/// play from (`onCommit`). VoiceOver adjusts it in `accessibilityStep`s.
struct ScrubBar: View {
    let value: Double
    var buffered: [ClosedRange<Double>] = []
    /// Time played, e.g. "6:10".
    let elapsed: String
    /// Time left, e.g. "9 min left".
    let remaining: String
    /// While dragging: the fraction under the finger; nil when the drag ends.
    var onScrub: (Double?) -> Void = { _ in }
    let onCommit: (Double) -> Void
    var accessibilityStep = 0.05

    @State private var dragValue: Double?

    var body: some View {
        HStack(spacing: Spacing.s) {
            GeometryReader { g in
                ScrubTrack(value: dragValue ?? value, buffered: buffered, isDragging: dragValue != nil)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                let f = fraction(v.location.x, width: g.size.width)
                                dragValue = f
                                onScrub(f)
                            }
                            .onEnded { v in
                                let f = fraction(v.location.x, width: g.size.width)
                                dragValue = nil
                                onScrub(nil)
                                onCommit(f)
                            }
                    )
            }
            .frame(height: BottomChrome.fieldControlSize)
            .animation(Motion.snappy, value: dragValue != nil)
            .accessibilityElement()
            .accessibilityLabel("Position")
            .accessibilityValue("\(elapsed), \(remaining)")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: onCommit(min(1, value + accessibilityStep))
                case .decrement: onCommit(max(0, value - accessibilityStep))
                @unknown default: break
                }
            }

            DetailLine([elapsed, remaining])
                .typeStyle(.caption)
                .monospacedDigit()
                .fixedSize()
                .accessibilityHidden(true)
        }
        .bottomChromeField(leading: Spacing.m, trailing: Spacing.m)
    }

    private func fraction(_ x: CGFloat, width: CGFloat) -> Double {
        min(max(0, Double(x / max(1, width))), 1)
    }
}

#if DEBUG
struct ScrubBarGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("start") {
                ScrubBar(value: 0, elapsed: "0:00", remaining: "12 min left") { _ in }
            }
            PreviewState("part-way, buffered ahead") {
                ScrubBar(value: 0.42, buffered: [0.42...0.7], elapsed: "6:10", remaining: "9 min left") { _ in }
            }
            PreviewState("track while dragging") {
                ScrubTrack(value: 0.6, buffered: [0.6...0.8], isDragging: true)
                    .frame(height: BottomChrome.fieldControlSize)
            }
            PreviewState("finished") {
                ScrubBar(value: 1, elapsed: "15:02", remaining: "0 min left") { _ in }
            }
            PreviewState("on the player, buffered ahead") {
                ScrubBar(value: 0.42, buffered: [0.42...0.7], elapsed: "6:10", remaining: "9 min left") { _ in }
                    .onPlayerPreview()
            }
        }
    }
}

#Preview("ScrubBar · light", traits: .sizeThatFitsLayout) { ScrubBarGallery().previewVariant(.light) }
#Preview("ScrubBar · dark", traits: .sizeThatFitsLayout) { ScrubBarGallery().previewVariant(.dark) }
#Preview("ScrubBar · AX5", traits: .sizeThatFitsLayout) { ScrubBarGallery().previewVariant(.largestText) }
#endif
