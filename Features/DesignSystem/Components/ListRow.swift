import SwiftUI

/// Every row in the Library, a folder, a book's contents and the Move tree.
///
/// ```
/// 📁 Bonds                                   4        folder: count
/// [i] Coupon Basics         ✓ Finished       ▶        page
/// [i] Seven-Day Yield   ▂▅▇ 9 min left       ⏸        page, playing: tinted
///  ◐  Chapter 24            6 min left       ▶        chapter, part-way
/// 🔗  serials.example.com   not fetched yet           link: lighter
/// ```
///
/// The row draws; tapping it is the caller's (a `NavigationLink`, a button). The trailing ▶ / ⏸
/// is a `PlayStateButton` that calls `onPlay`; rows without `onPlay` (folders, plain links)
/// have none.
struct ListRow: View {
    enum Kind {
        /// A folder (or Favorites, a book, a series): its symbol, or a book's cover when it has
        /// one, and how many things are in it.
        case folder(symbol: String = "folder", count: Int, cover: Image? = nil)
        /// A saved page: its site icon (or a letter tile).
        case page(artwork: Image? = nil, letter: String)
        /// A chapter of a book or series.
        case chapter
        /// A page that is only an address so far (a link in Favorites, a chapter not fetched).
        case link
    }

    enum Progress {
        /// Not started: its length, when known ("18 min").
        case unplayed(minutes: Int?)
        /// Part-way: a small ring and the time left.
        case partWay(fraction: Double, minutesLeft: Int)
        case finished
        /// Front matter left out of playback.
        case skipped
    }

    let kind: Kind
    let title: String
    /// Under the title: the site, "not fetched yet".
    var subtitle: String?
    var progress: Progress = .unplayed(minutes: nil)
    var playState: PlayState = .idle
    var onPlay: (() -> Void)?

    /// 56 pt at the default text size; larger text grows the row through its content, and the
    /// minimum only up to `BottomChrome.maxTextGrowth`.
    @ScaledMetric(relativeTo: .callout) private var scaledMinHeight: CGFloat = 56

    var body: some View {
        HStack(spacing: Spacing.s) {
            // The label reads as one VoiceOver element (the title, then its status as the
            // value); ▶ stays its own so play and open are separate actions.
            HStack(spacing: Spacing.s) {
                leading
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .typeStyle(.row, weight: playState.isCurrent ? .semibold : .regular)
                        .foregroundStyle(titleColor)
                        .lineLimit(2)
                    if let subtitle {
                        Text(subtitle)
                            .typeStyle(.caption)
                            .foregroundStyle(Palette.secondaryInk)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                trailing
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(accessibilityStatus)
            .accessibilityAddTraits(.isStaticText)
            if let onPlay {
                PlayStateButton(state: playState, action: onPlay)
            }
        }
        .padding(.leading, Spacing.m)
        .padding(.trailing, onPlay == nil ? Spacing.m : Spacing.xxs)
        .padding(.vertical, Spacing.xs)
        .frame(minHeight: BottomChrome.grown(scaledMinHeight, from: 56))
        .background(playState.isCurrent ? Palette.playingTint : Color.clear)
        .opacity(isDimmed ? 0.6 : 1)
        .accessibilityElement(children: .contain)
    }

    /// What VoiceOver reads after the title: the subtitle and the status line.
    private var accessibilityStatus: String {
        var parts: [String] = []
        if let subtitle { parts.append(subtitle) }
        if playState.isCurrent { parts.append(playState == .playing ? "Playing" : "Paused") }
        switch (kind, progress) {
        case (.folder(_, let count, _), _): parts.append("\(count) items")
        case (_, .unplayed(let minutes?)): parts.append("\(minutes) min")
        case (_, .unplayed(nil)): break
        case (_, .partWay(_, let left)): parts.append("\(left) min left")
        case (_, .finished): parts.append("Finished")
        case (_, .skipped): parts.append("Skipped in playback")
        }
        return parts.joined(separator: ", ")
    }

    private var isDimmed: Bool {
        if case .skipped = progress { return true }
        if case .link = kind { return true }
        return false
    }

    private var titleColor: Color {
        if playState.isCurrent { return Palette.accent }
        if case .finished = progress { return Palette.secondaryInk }
        return Palette.ink
    }

    @ViewBuilder
    private var leading: some View {
        switch kind {
        case .folder(_, _, let cover?):
            ArtworkTile(image: cover, letter: title, size: ListRow.coverWidth, isCover: true, fill: Palette.paper)
                .frame(width: ListRow.leadingWidth)
        case .folder(let symbol, _, nil):
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Palette.accent)
                .frame(width: ListRow.leadingWidth)
        case .page(let artwork, let letter):
            ArtworkTile(image: artwork, letter: letter, size: ListRow.leadingWidth, fill: Palette.paper)
        case .chapter:
            Group {
                if playState.isCurrent {
                    PlayingBars(animating: playState == .playing)
                        .foregroundStyle(Palette.accent)
                        .padding(Spacing.xxs)
                } else {
                    switch progress {
                    case .finished:
                        Image(systemName: "checkmark").foregroundStyle(Palette.secondaryInk)
                    case .partWay(let fraction, _):
                        ProgressRing(fraction: fraction)
                    case .unplayed, .skipped:
                        Color.clear
                    }
                }
            }
            .frame(width: Glyph.mark, height: Glyph.mark)
        case .link:
            Image(systemName: "link")
                .foregroundStyle(Palette.secondaryInk)
                .frame(width: ListRow.leadingWidth)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        HStack(spacing: Spacing.xs) {
            if case .page = kind, playState.isCurrent {
                PlayingBars(animating: playState == .playing)
                    .foregroundStyle(Palette.accent)
                    .frame(width: Glyph.indicator, height: Glyph.indicator)
            }
            status
        }
    }

    @ViewBuilder
    private var status: some View {
        Group {
            switch (kind, progress) {
            case (.folder(_, let count, _), _):
                Text("\(count)")
            case (_, .unplayed(let minutes?)):
                Text("\(minutes) min")
            case (_, .unplayed(nil)):
                EmptyView()
            case (.page, .partWay(let fraction, let left)):
                HStack(spacing: Spacing.xxs) {
                    if !playState.isCurrent { ProgressRing(fraction: fraction) }
                    Text("\(left) min left")
                }
            case (_, .partWay(_, let left)):
                Text("\(left) min left")
            case (.chapter, .finished):
                Text("Finished")
            case (_, .finished):
                Text("✓ Finished")
            case (_, .skipped):
                Text("skipped")
            }
        }
        .typeStyle(.caption)
        .monospacedDigit()
        .foregroundStyle(playState.isCurrent ? Palette.accent : Palette.secondaryInk)
        .lineLimit(1)
        .fixedSize()
    }

    /// Width of the leading symbol or artwork.
    static let leadingWidth: CGFloat = 32
    /// A book cover in a folder row: narrower than the slot, so its height (1.45×) stays inside
    /// the row's 56 pt.
    static let coverWidth: CGFloat = 26
}

/// A small progress ring: how far through a part-way page or chapter.
struct ProgressRing: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle().stroke(Palette.secondaryInk.opacity(0.25), lineWidth: 2)
            Circle()
                .trim(from: 0, to: min(max(0, fraction), 1))
                .stroke(Palette.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: Glyph.ring, height: Glyph.ring)
        .accessibilityHidden(true)
    }
}

#if DEBUG
struct ListRowGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("folder") {
                ListRow(kind: .folder(count: 4), title: "Bonds")
                ListRow(kind: .folder(symbol: "star.fill", count: 12), title: "Favorites")
                ListRow(kind: .folder(symbol: "book.closed", count: 61, cover: nil), title: "Pride and Prejudice",
                        subtitle: "Jane Austen")
                ListRow(kind: .folder(count: 3, cover: Image(systemName: "photo")), title: "A book with a cover")
            }
            PreviewState("page, unplayed") {
                ListRow(kind: .page(letter: "M"), title: "Money Market Funds", subtitle: "investing.example.com",
                        progress: .unplayed(minutes: 12), onPlay: {})
            }
            PreviewState("page, part-way") {
                ListRow(kind: .page(letter: "B"), title: "Bond Ladders", subtitle: "investing.example.com",
                        progress: .partWay(fraction: 0.4, minutesLeft: 6), onPlay: {})
            }
            PreviewState("page, playing") {
                ListRow(kind: .page(letter: "S"), title: "Seven-Day Yield", subtitle: "investing.example.com",
                        progress: .partWay(fraction: 0.58, minutesLeft: 9), playState: .playing, onPlay: {})
            }
            PreviewState("page, finished") {
                ListRow(kind: .page(letter: "C"), title: "Coupon Basics", progress: .finished, onPlay: {})
            }
            PreviewState("chapter: finished, playing, part-way, unplayed, skipped") {
                VStack(spacing: 0) {
                    ListRow(kind: .chapter, title: "Chapter 11", progress: .finished, onPlay: {})
                    ListRow(kind: .chapter, title: "Chapter 12", progress: .partWay(fraction: 0.3, minutesLeft: 18),
                            playState: .playing, onPlay: {})
                    ListRow(kind: .chapter, title: "Chapter 24", progress: .partWay(fraction: 0.5, minutesLeft: 6),
                            onPlay: {})
                    ListRow(kind: .chapter, title: "Chapter 25", progress: .unplayed(minutes: 11), onPlay: {})
                    ListRow(kind: .chapter, title: "Title page", progress: .skipped)
                }
            }
            PreviewState("link, and a link chapter that fetches then plays") {
                ListRow(kind: .link, title: "investing.example.com")
                ListRow(kind: .link, title: "Chapter 26", subtitle: "not fetched yet", onPlay: {})
            }
        }
    }
}

#Preview("ListRow · light", traits: .sizeThatFitsLayout) { ListRowGallery().previewVariant(.light) }
#Preview("ListRow · dark", traits: .sizeThatFitsLayout) { ListRowGallery().previewVariant(.dark) }
#Preview("ListRow · AX5", traits: .sizeThatFitsLayout) { ListRowGallery().previewVariant(.largestText) }
#endif
