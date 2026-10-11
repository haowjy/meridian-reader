import SwiftUI

/// Every row in the Library, a folder, a book's contents and the Move tree.
///
/// ```
/// 📁 Bonds                                    4  ›   folder: count, then ›
/// ▣  Pride and Prejudice                         ▶   book: its place and its own ▶
///    Ch 24   ◐ 6 h 10 min left
/// [i] Coupon Basics                              ▶   page: status under the title
///     investing.example.com   ✓ Finished
/// [i] Seven-Day Yield                            ⏸   page, playing: tinted, bars
///     investing.example.com   ▂▅▇ 9 min left
/// [i] Notes on Tides                             ▶   played, not saved: the note
///     example.org   Not saved   ◐ 4 min left
///  ◐  Chapter 24                                 ▶   chapter, part-way
///     6 min left
/// 🔗  serials.example.com                            link: lighter
/// [i] Index Funds                                ▶   downloaded: a quiet mark ends the line
///     investing.example.com   12 min   ⊕
/// ```
///
/// The row draws; tapping it is the caller's (a `NavigationLink`, a button). The status sits
/// under the title so the title keeps the row's width. The second line's parts are spaced apart
/// (`DetailLineLayout`), not joined by a separator: the first in secondary ink, the rest in
/// tertiary, the status in the accent while it is what you hear. ▶ / ⏸ (`onPlay`) and ›
/// (`opensScreen`) share one trailing column, centred on the toolbar's ⋯ slot like the Now
/// Playing bar's ⏸.
///
/// A folder row under a dragged row that it takes (`isDropTarget`) is washed and outlined in the
/// accent, with a selection tick as it lights up.
struct ListRow: View {
    enum Kind {
        /// A folder (or Favorites, a book, a series): its symbol, or a book's cover when it has
        /// one, and how many things are in it (shown before › on a row without ▶).
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
    /// Under the title, before the status: the site, "Ch 24", "not fetched yet".
    var subtitle: String?
    /// A short note between the subtitle and the status ("Not saved").
    var note: String?
    var progress: Progress = .unplayed(minutes: nil)
    var playState: PlayState = .idle
    /// Tapping the row opens a screen: › in the trailing column (unless the row has ▶).
    var opensScreen = false
    var onPlay: (() -> Void)?
    /// A dragged row is over this one, and it takes the drop (a folder it would be filed in).
    var isDropTarget = false
    /// A dragged row would be placed beside this one, on this side: a line marks the place.
    var insertionEdge: VerticalEdge?
    /// Its audio is downloaded (a folder's: every page its download covers): a small mark ends
    /// the second line.
    var isDownloaded = false

    /// 56 pt at the default text size; larger text grows the row through its content, and the
    /// minimum only up to `BottomChrome.maxTextGrowth`.
    @ScaledMetric(relativeTo: .callout) private var scaledMinHeight: CGFloat = 56
    /// Space between the second line's parts: `Spacing.s`, growing with the caption.
    @ScaledMetric(relativeTo: TypeStyle.caption.relativeTo) private var partSpacing = Spacing.s
    /// The row's width, for the trailing column's place (`trailingColumnPadding`).
    @State private var width: CGFloat = 0

    var body: some View {
        HStack(spacing: Spacing.s) {
            // The title is the row's one VoiceOver element, its status the value (the rest is
            // hidden); ▶ stays its own so play and open are separate actions.
            HStack(spacing: Spacing.s) {
                leading
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .typeStyle(.row, weight: playState.isCurrent ? .semibold : .regular)
                        .foregroundStyle(titleColor)
                        .lineLimit(2)
                        .accessibilityValue(accessibilityStatus)
                    secondLine
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let count = folderCount {
                    Text("\(count)")
                        .typeStyle(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize()
                        .accessibilityHidden(true)
                }
            }
            trailingColumn
        }
        .padding(.leading, Spacing.m)
        .padding(.trailing, hasTrailingColumn ? Self.trailingColumnPadding(rowWidth: width) : Spacing.m)
        .padding(.vertical, Spacing.xs)
        .frame(minHeight: BottomChrome.grown(scaledMinHeight, from: 56))
        .background(playState.isCurrent ? Palette.playingTint : Color.clear)
        .overlay { dropHighlight }
        .overlay(alignment: insertionEdge == .bottom ? .bottom : .top) { insertionLine }
        .opacity(isDimmed ? 0.6 : 1)
        .animation(Motion.snappy, value: isDropTarget)
        .animation(Motion.snappy, value: insertionEdge)
        .sensoryFeedback(.selection, trigger: isDropTarget) { _, isTarget in isTarget }
        .sensoryFeedback(.selection, trigger: insertionEdge) { _, edge in edge != nil }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { if $0 != width { width = $0 } }
        .accessibilityElement(children: .contain)
    }

    /// Trailing padding that centres the 44 pt trailing column on the toolbar's ⋯ slot, for a
    /// row `rowWidth` wide in a list at the page margin: the toolbar row is wider by the
    /// difference between the page and band margins on each side.
    static func trailingColumnPadding(rowWidth: CGFloat) -> CGFloat {
        guard rowWidth > 0 else { return Spacing.xxs }
        let inset = Spacing.pageMargin - Spacing.bandMargin
        return max(0, NowPlayingBar.trailingPadding(rowWidth: rowWidth + 2 * inset) - inset)
    }

    /// The accent wash and outline of a drop target, inset so the outline clears the card's
    /// rounded corners.
    private var dropHighlight: some View {
        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .fill(Palette.accent.opacity(Palette.washOpacity))
            .strokeBorder(Palette.accent, lineWidth: Self.dropOutlineWidth)
            .padding(Spacing.xxs)
            .opacity(isDropTarget ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    static let dropOutlineWidth: CGFloat = 2

    /// Where a dragged row would go: an accent line along the row's edge, from the title's
    /// leading edge, with a ring at its start (as iOS marks a drop between rows).
    @ViewBuilder
    private var insertionLine: some View {
        if insertionEdge != nil {
            HStack(spacing: 0) {
                Circle()
                    .strokeBorder(Palette.accent, lineWidth: Self.dropOutlineWidth)
                    .frame(width: Spacing.xs, height: Spacing.xs)
                Capsule()
                    .fill(Palette.accent)
                    .frame(height: Self.dropOutlineWidth)
            }
            .padding(.leading, Spacing.m + ListRow.leadingWidth)
            .padding(.trailing, Spacing.m)
            // Centred on the edge, half in this row and half in its neighbour's gap.
            .offset(y: (insertionEdge == .bottom ? 1 : -1) * Spacing.xs / 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .transition(.opacity)
        }
    }

    // MARK: - Trailing column

    private var hasTrailingColumn: Bool { onPlay != nil || opensScreen }

    @ViewBuilder
    private var trailingColumn: some View {
        if let onPlay {
            PlayStateButton(state: playState, action: onPlay)
        } else if opensScreen {
            Image(systemName: "chevron.right")
                .typeStyle(.caption, weight: .semibold)
                .foregroundStyle(Palette.secondaryInk)
                .frame(width: BottomChrome.minTapTarget)
                .accessibilityHidden(true)
        }
    }

    /// A folder row without ▶ shows its count just before ›.
    private var folderCount: Int? {
        guard onPlay == nil, case .folder(_, let count, _) = kind else { return nil }
        return count
    }

    // MARK: - Second line

    /// The subtitle, the note, then the status, spaced apart: "investing.example.com   ◐ 6 min
    /// left". The subtitle truncates, the status doesn't; when they can't share a line (large
    /// text), the status wraps under the subtitle.
    @ViewBuilder
    private var secondLine: some View {
        let status = statusText
        let leads = [subtitle, note].compactMap { $0 }
        if !leads.isEmpty || status != nil || isDownloaded {
            DetailLineLayout(spacing: partSpacing) {
                ForEach(Array(leads.enumerated()), id: \.offset) { index, text in
                    Text(text)
                        .foregroundStyle(index == 0 ? Palette.secondaryInk : Palette.tertiaryInk)
                        .lineLimit(index == 0 ? 1 : nil)
                }
                if let status { statusView(status, isLead: leads.isEmpty) }
                if isDownloaded { downloadedMark }
            }
            .typeStyle(.caption)
        }
    }

    /// Downloaded: a small filled arrow in secondary ink, the caption's size. VoiceOver reads
    /// "Downloaded" in the row's value.
    private var downloadedMark: some View {
        Image(systemName: "arrow.down.circle.fill")
            .foregroundStyle(Palette.secondaryInk)
            .accessibilityLabel(String(localized: "Downloaded"))
    }

    private func statusView(_ status: String, isLead: Bool) -> some View {
        HStack(spacing: Spacing.xxs) {
            switch statusMark {
            case .bars:
                PlayingBars(animating: playState == .playing)
                    .frame(width: Glyph.ring, height: Glyph.ring)
            case .ring(let fraction):
                ProgressRing(fraction: fraction)
            case nil:
                EmptyView()
            }
            Text(status)
        }
        .foregroundStyle(playState.isCurrent ? Palette.accent
                         : isLead ? Palette.secondaryInk : Palette.tertiaryInk)
        .monospacedDigit()
    }

    private enum StatusMark {
        case bars
        case ring(Double)
    }

    /// Bars while it is what you hear, a ring part-way; a chapter shows these in its leading
    /// column instead.
    private var statusMark: StatusMark? {
        if case .chapter = kind { return nil }
        if playState.isCurrent { return .bars }
        if case .partWay(let fraction, _) = progress { return .ring(fraction) }
        return nil
    }

    /// "18 min", "6 min left", "✓ Finished", "skipped"; nil for a folder row with its count.
    private var statusText: String? {
        if folderCount != nil { return nil }
        switch (kind, progress) {
        case (_, .unplayed(let minutes?)): return ListeningTime.label(minutes: minutes)
        case (_, .unplayed(nil)): return nil
        case (_, .partWay(_, let left)): return "\(ListeningTime.label(minutes: left)) left"
        case (.chapter, .finished): return String(localized: "Finished")
        case (_, .finished): return String(localized: "✓ Finished")
        case (_, .skipped): return String(localized: "skipped")
        }
    }

    /// What VoiceOver reads after the title: the subtitle and the status line.
    private var accessibilityStatus: String {
        var parts: [String] = []
        if let subtitle { parts.append(subtitle) }
        if let note { parts.append(note) }
        if playState.isCurrent { parts.append(playState == .playing ? "Playing" : "Paused") }
        if isDropTarget { parts.append("Drop to move here") }
        if insertionEdge != nil { parts.append("Drop to place here") }
        if let count = folderCount {
            parts.append("\(count) items")
        } else {
            switch progress {
            case .unplayed(let minutes?): parts.append(ListeningTime.label(minutes: minutes))
            case .unplayed(nil): break
            case .partWay(_, let left): parts.append("\(ListeningTime.label(minutes: left)) left")
            case .finished: parts.append("Finished")
            case .skipped: parts.append("Skipped in playback")
            }
        }
        if isDownloaded { parts.append(String(localized: "Downloaded")) }
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
                ListRow(kind: .folder(count: 4), title: "Bonds", opensScreen: true)
                ListRow(kind: .folder(symbol: "star.fill", count: 12), title: "Favorites", opensScreen: true)
                ListRow(kind: .folder(count: 3, cover: Image(systemName: "photo")), title: "A book with a cover",
                        opensScreen: true)
            }
            PreviewState("folder, a dragged row over it") {
                ListRow(kind: .folder(count: 4), title: "Bonds", opensScreen: true, isDropTarget: true)
            }
            PreviewState("a page with a dragged row about to be placed above it") {
                ListRow(kind: .page(letter: "M"), title: "Money Market Funds", subtitle: "investing.example.com",
                        progress: .unplayed(minutes: 12), onPlay: {}, insertionEdge: .top)
            }
            PreviewState("folder of pages: its place and its ▶") {
                ListRow(kind: .folder(count: 7), title: "Finance", subtitle: "Seven-Day Yield",
                        progress: .partWay(fraction: 0.3, minutesLeft: 52), opensScreen: true, onPlay: {})
            }
            PreviewState("book: unplayed, part-way, playing") {
                ListRow(kind: .folder(symbol: "book.closed", count: 61), title: "Pride and Prejudice",
                        subtitle: "Jane Austen", progress: .unplayed(minutes: 645), opensScreen: true, onPlay: {})
                ListRow(kind: .folder(symbol: "book.closed", count: 61), title: "Pride and Prejudice",
                        subtitle: "Ch 24", progress: .partWay(fraction: 0.38, minutesLeft: 370), opensScreen: true,
                        onPlay: {})
                ListRow(kind: .folder(symbol: "books.vertical", count: 108), title: "The Lighthouse Keeper",
                        subtitle: "Ch 14", progress: .partWay(fraction: 0.12, minutesLeft: 1210), playState: .playing,
                        opensScreen: true, onPlay: {})
            }
            PreviewState("page, unplayed") {
                ListRow(kind: .page(letter: "M"), title: "Money Market Funds", subtitle: "investing.example.com",
                        progress: .unplayed(minutes: 12), onPlay: {})
            }
            PreviewState("page, part-way; played, not saved") {
                ListRow(kind: .page(letter: "B"), title: "Bond Ladders", subtitle: "investing.example.com",
                        progress: .partWay(fraction: 0.4, minutesLeft: 6), onPlay: {})
                ListRow(kind: .page(letter: "N"), title: "Notes on Tides", subtitle: "example.org", note: "Not saved",
                        progress: .partWay(fraction: 0.6, minutesLeft: 4), onPlay: {})
            }
            PreviewState("page, playing") {
                ListRow(kind: .page(letter: "S"), title: "Seven-Day Yield: Definition, Calculation, and Example",
                        subtitle: "investing.example.com", progress: .partWay(fraction: 0.58, minutesLeft: 9),
                        playState: .playing, onPlay: {})
            }
            PreviewState("downloaded: a page, a book, a chapter") {
                ListRow(kind: .page(letter: "I"), title: "Index Funds", subtitle: "investing.example.com",
                        progress: .unplayed(minutes: 12), onPlay: {}, isDownloaded: true)
                ListRow(kind: .folder(symbol: "book.closed", count: 61), title: "Pride and Prejudice",
                        subtitle: "Ch 24", progress: .partWay(fraction: 0.38, minutesLeft: 370), opensScreen: true,
                        onPlay: {}, isDownloaded: true)
                ListRow(kind: .chapter, title: "Chapter 25", progress: .unplayed(minutes: 11), onPlay: {},
                        isDownloaded: true)
            }
            PreviewState("page, finished") {
                ListRow(kind: .page(letter: "C"), title: "Coupon Basics", subtitle: "investing.example.com",
                        progress: .finished, onPlay: {})
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
