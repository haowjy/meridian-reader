import SwiftUI

/// Something to resume, in the Library's Continue row: a book, a series or a part-way page.
///
/// ```
/// ╭──────────────────╮
/// │ [cover]       ▶  │   the card's own play button
/// │ Chapter 12       │
/// │ ━━━━━░░░░░░░░░░  │
/// │ 18 min left      │
/// ╰──────────────────╯
/// ```
///
/// Tapping the card opens the thing (the caller wraps it); the ▶ resumes it (`onPlay`).
struct ContinueCard: View {
    let title: String
    /// "18 min left", "Pride and Prejudice · Ch 12".
    let detail: String
    var artwork: Image?
    var artworkLetter = ""
    /// 0…1 through it.
    let progress: Double
    var playState: PlayState = .idle
    /// A short mark under the detail ("Not saved").
    var badge: String?
    let onPlay: () -> Void

    @ScaledMetric(relativeTo: .callout) private var width: CGFloat = 160

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .top) {
                ArtworkTile(image: artwork, letter: artworkLetter.isEmpty ? title : artworkLetter, size: 48,
                            fill: playState.isCurrent ? Palette.chrome : Palette.paper)
                Spacer(minLength: 0)
                PlayStateButton(state: playState, action: onPlay)
                    .padding(.top, -Spacing.xxs)
                    .padding(.trailing, -Spacing.s)
            }
            Text(title)
                .typeStyle(.row, weight: .semibold)
                .foregroundStyle(playState.isCurrent ? Palette.accent : Palette.ink)
                .lineLimit(2, reservesSpace: true)
            ThinProgressBar(value: progress)
            Text(detail)
                .typeStyle(.caption)
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
            if let badge {
                Text(badge)
                    .typeStyle(.caption, weight: .semibold)
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
        .padding(Spacing.s)
        .frame(width: width, alignment: .leading)
        .background(playState.isCurrent ? Palette.playingTint : Palette.chrome,
                    in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
struct ContinueCardGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("page part-way · book playing · not saved") {
                HStack(alignment: .top, spacing: Spacing.s) {
                    ContinueCard(title: "Seven-Day Yield: Definition", detail: "12 min left", progress: 0.58) {}
                    ContinueCard(title: "Chapter 12", detail: "Pride and Prejudice", artworkLetter: "P",
                                 progress: 0.2, playState: .playing) {}
                }
            }
            PreviewState("not saved, preparing") {
                ContinueCard(title: "Notes on Tides", detail: "9 min left", progress: 0.1, playState: .preparing,
                             badge: "Not saved") {}
            }
        }
    }
}

#Preview("ContinueCard · light", traits: .sizeThatFitsLayout) { ContinueCardGallery().previewVariant(.light) }
#Preview("ContinueCard · dark", traits: .sizeThatFitsLayout) { ContinueCardGallery().previewVariant(.dark) }
#Preview("ContinueCard · AX5", traits: .sizeThatFitsLayout) { ContinueCardGallery().previewVariant(.largestText) }
#endif
