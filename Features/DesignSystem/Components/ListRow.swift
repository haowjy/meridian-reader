import SwiftUI

/// Every row in the Library, a folder, a book's contents, the browser's history and Downloads.
///
/// ```
/// 📁 Bonds                                       ⋯   folder: its count on the second line
///    2 folders   3 pages
/// ▣  Pride and Prejudice                         ⋯   book: its place and time left
///    Ch 24   6 h 10 min left                ◐  ⋯   (the listening column: ◐ part-way)
/// ▣ Coupon Basics                             ●  ⋯   page, downloaded: the grey filled ↓ badge;
/// ▣ ↓ example.com   Finished                          ● the same ring, full
/// ▣̲ Seven-Day Yield                          ▂▅▇ ⋯   page, playing and downloading: tinted,
/// ▣ Playing                                           bars; the tile dimmed under a jade ↓
/// 🔗 serials.example.com                              link: lighter
/// ```
///
/// The row draws; tapping it is the caller's (a `NavigationLink` behind it, `opensOnTap`). A
/// page's row is exactly two lines: its title on one line (truncated), then one line of what it
/// is and where it stands; its thumbnail is as tall as the two lines. The second line's parts are
/// spaced apart, never joined by a separator: the first in secondary ink, the rest in tertiary,
/// the status in the accent while it is what you hear ("Playing", "Paused"). The leading parts
/// give way first, and at accessibility sizes the status shows alone.
///
/// Its listening mark stands in a fixed-width column at the trailing edge, just before the
/// accessory and the ⋯ (`Glyph.listeningColumn`), so every row's ring lines up: a ring part-way,
/// the same ring full once finished, the bars while it is what you hear, and nothing (the column
/// kept, so nothing shifts) before it starts. Line two keeps the words ("18 min", "6 min left",
/// "Finished", "Playing"). Rows with no listening (a folder with its count, a book preview's
/// chapter, `showsListening` false: browser visits, downloads) have no column.
///
/// Its download (`download`) shows on the row itself, never as a button: downloading dims the
/// thumbnail under a small jade ↓ (grey while paused), downloaded puts a grey filled ↓ before the second
/// line. The trailing ⋯ (`menu`, the same menu as the row's long press) is centred on the
/// toolbar's ⋯ slot like the Now Playing bar's ⏸; a row with a control of its own (a download's
/// pause, `accessory`) has it just before the ⋯. Every row's separator starts at its title,
/// whatever leads it.
///
/// A folder row under a dragged row that it takes (`isDropTarget`) is washed and outlined in the
/// accent, with a selection tick as it lights up.
struct ListRow: View {
    enum Kind {
        /// A folder (a book or a series too): its symbol, or a book's cover when it has one, and
        /// what is in it ("2 folders", "3 pages"; "Empty") for its second line; none (`[]`) for a
        /// folder whose pages play, whose second line is its place and time left.
        case folder(symbol: String = Icons.folder, count: [String], cover: Image? = nil)
        /// A saved page: its site icon (or a letter tile).
        case page(artwork: Image? = nil, letter: String)
        /// A chapter in a book's preview: its title alone, after an empty mark's width.
        case chapter
        /// A page that is only an address so far (a link ☆ made, a chapter not fetched).
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
    /// A short note between the subtitle and the status ("Fetching text…", "2 h ago").
    var note: String?
    /// More parts after the note, in the same tertiary ink (a download's count and size).
    var details: [String] = []
    var progress: Progress = .unplayed(minutes: nil)
    var playState: PlayState = .idle
    /// A dragged row is over this one, and it takes the drop (a folder it would be filed in).
    var isDropTarget = false
    /// A dragged row would be placed beside this one, on this side: a line marks the place.
    var insertionEdge: VerticalEdge?
    /// Where its download stands: the dimmed thumbnail while downloading, the ↓ badge once done.
    var download: DownloadState = .notDownloaded
    var isFavorite = false
    var folderHasDetails = false
    /// The rows of its ⋯ menu, the same as its long press (nil: no ⋯, as in Edit).
    var menu: AnyView?
    /// A view laid behind the ⋯ at its size (behind the row when it has none): a question its menu
    /// asks attaches there, so on iOS 26 its popover points at the ⋯.
    var menuAnchor: AnyView?
    /// A control of the row's own, 44 pt, just before the ⋯ (a download's pause / resume).
    var accessory: AnyView?
    /// Whether the row has the trailing listening column (false where listening never shows:
    /// browser visits, the Downloads list).
    var showsListening = true

    /// `RowHeight.content` at the default text size; larger text grows the row through its
    /// content, and the minimum only up to `BottomChrome.maxTextGrowth`.
    @ScaledMetric(relativeTo: .callout) private var scaledMinHeight = RowHeight.content
    /// Space between the second line's parts: `Spacing.s`, growing with the caption.
    @ScaledMetric(relativeTo: TypeStyle.caption.relativeTo) private var partSpacing = Spacing.s
    /// The two text lines' heights, scaled like their text: a page's thumbnail matches them.
    @ScaledMetric(relativeTo: TypeStyle.row.relativeTo) private var titleLineHeight = TypeStyle.row.lineHeight
    @ScaledMetric(relativeTo: TypeStyle.caption.relativeTo) private var captionLineHeight = TypeStyle.caption.lineHeight
    /// The ⋯, scaled like a toolbar glyph (`moreGlyphSize`).
    @ScaledMetric(relativeTo: .title3) private var scaledGlyph: CGFloat = ListRow.moreGlyphSize
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The row's width, for the trailing column's place (`trailingColumnPadding`).
    @State private var width: CGFloat = 0

    var body: some View {
        HStack(spacing: Spacing.s) {
            // The title is the row's one VoiceOver element, its status the value (the rest is
            // hidden); the ⋯ stays its own.
            HStack(spacing: Spacing.s) {
                downloadLeading
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: Spacing.xs) {
                        Text(title)
                            .typeStyle(.row, weight: playState.isCurrent ? .semibold : .regular)
                            .foregroundStyle(titleColor)
                            .lineLimit(1)
                            .accessibilityValue(accessibilityStatus)
                        if isFavorite {
                            Image(systemName: Icons.favorited)
                                .font(.caption)
                                .foregroundStyle(Palette.accent)
                                .accessibilityHidden(true)
                        }
                    }
                    secondLine
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // The separator under the row starts at the title, for every kind of row.
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            }
            if hasListeningColumn {
                listeningMark
                    .frame(width: Glyph.listeningColumn)
                    .accessibilityHidden(true)
            }
            if let accessory {
                accessory
                    .frame(width: BottomChrome.minTapTarget, height: BottomChrome.minTapTarget)
            }
            if let menu {
                Menu { menu } label: {
                    Image(systemName: Icons.more)
                        .font(.system(size: BottomChrome.grown(scaledGlyph, from: Self.moreGlyphSize), weight: .semibold))
                        .foregroundStyle(Palette.secondaryInk)
                        .frame(width: BottomChrome.minTapTarget, height: BottomChrome.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Verbs.more)
                .accessibilityIdentifier("rowMore")
                .background { menuAnchor }
            }
        }
        .background { if menu == nil { menuAnchor } }
        .padding(.leading, Spacing.m)
        .padding(.trailing, menu != nil ? Self.trailingColumnPadding(rowWidth: width) : Spacing.m)
        .padding(.vertical, Spacing.xs)
        .frame(minHeight: BottomChrome.grown(scaledMinHeight, from: RowHeight.content))
        .background(playState.isCurrent ? Palette.playingTint : Color.clear)
        .overlay { dropHighlight }
        .overlay(alignment: insertionEdge == .bottom ? .bottom : .top) { insertionLine }
        .opacity(isDimmed ? Palette.lighterRowOpacity : 1)
        .animation(Motion.snappy, value: isDropTarget)
        .animation(Motion.snappy, value: insertionEdge)
        .animation(Motion.standard, value: download)
        .sensoryFeedback(.selection, trigger: isDropTarget) { _, isTarget in isTarget }
        .sensoryFeedback(.selection, trigger: insertionEdge) { _, edge in edge != nil }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { if $0 != width { width = $0 } }
        .accessibilityElement(children: .contain)
    }

    /// The ⋯'s size at the default text size; it grows like a toolbar glyph.
    static let moreGlyphSize: CGFloat = 20

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
            .strokeBorder(Palette.accent, lineWidth: Glyph.stroke)
            .padding(Spacing.xxs)
            .opacity(isDropTarget ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Where a dragged row would go: an accent line along the row's edge, from the title's
    /// leading edge, with a ring at its start (as iOS marks a drop between rows).
    @ViewBuilder
    private var insertionLine: some View {
        if insertionEdge != nil {
            HStack(spacing: 0) {
                Circle()
                    .strokeBorder(Palette.accent, lineWidth: Glyph.stroke)
                    .frame(width: Spacing.xs, height: Spacing.xs)
                Capsule()
                    .fill(Palette.accent)
                    .frame(height: Glyph.stroke)
            }
            // The ring just before the title, the line from the title's leading edge on.
            .padding(.leading, Spacing.m + thumbnailSide + Spacing.s - Spacing.xs)
            .padding(.trailing, Spacing.m)
            // Centred on the edge, half in this row and half in its neighbour's gap.
            .offset(y: (insertionEdge == .bottom ? 1 : -1) * Spacing.xs / 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .transition(.opacity)
        }
    }

    /// What is in a folder, on its second line in place of a status (a folder whose pages play
    /// gives none: its place and time left stand there, in Edit too).
    private var folderCount: [String]? {
        guard case .folder(_, let count, _) = kind, !count.isEmpty else { return nil }
        return count
    }

    // MARK: - Second line

    /// The ✓ badge once downloaded, the subtitle, the note, then the status, spaced apart on one
    /// line: "↓ example.org   4 min left" (the ring is the trailing column's). The subtitle and note give way first; at
    /// accessibility sizes they are left out and the status truncates if it must, so the line
    /// never wraps or widens the row.
    @ViewBuilder
    private var secondLine: some View {
        let status = statusText
        // At accessibility sizes there is no room for both: the status alone (VoiceOver reads all).
        let leads = typeSize.isAccessibilitySize && status != nil ? []
            : [subtitle, note].compactMap { $0 } + details + (folderCount ?? [])
        // A skipped chapter never plays, so it shows no downloaded mark (C89).
        let badged = download == .downloaded && !isSkipped
        let queued = download.isQueued
        if !leads.isEmpty || status != nil || badged || queued {
            HStack(spacing: partSpacing) {
                if queued {
                    // Waiting its turn: a small spinner in the badge slot (C93).
                    QueuedIndicator()
                        .padding(.trailing, -partSpacing / 2)
                        .transition(.opacity)
                } else if badged {
                    // Downloaded: a grey filled ↓ before the line, as tall as its text.
                    Image(systemName: Icons.downloaded)
                        .foregroundStyle(Palette.secondaryInk)
                        .padding(.trailing, -partSpacing / 2)
                        .transition(.opacity)
                }
                ForEach(Array(leads.enumerated()), id: \.offset) { index, text in
                    Text(text)
                        .foregroundStyle(index == 0 ? Palette.secondaryInk : Palette.tertiaryInk)
                        .layoutPriority(index == 0 ? 0 : 1)
                }
                if let status {
                    statusView(status, isLead: leads.isEmpty)
                        .layoutPriority(2)
                }
            }
            .lineLimit(1)
            .typeStyle(.caption)
        }
    }

    private func statusView(_ status: String, isLead: Bool) -> some View {
        Text(status)
            .foregroundStyle(playState.isCurrent ? Palette.accent
                             : isLead ? Palette.secondaryInk : Palette.tertiaryInk)
            .monospacedDigit()
    }

    /// The trailing listening column: a page's, a chapter's, a book's whose pages play. Not a
    /// folder with its count, nor a book preview's chapter, nor where listening never shows.
    private var hasListeningColumn: Bool {
        guard showsListening, folderCount == nil else { return false }
        if case .chapter = kind { return false }
        return true
    }

    /// The column's mark, centred: bars, a ring, or nothing (the column keeps its width).
    @ViewBuilder
    private var listeningMark: some View {
        switch statusMark {
        case .bars:
            PlayingBars(animating: playState == .playing)
                .frame(width: Glyph.ring, height: Glyph.ring)
                .foregroundStyle(Palette.accent)
        case .ring(let fraction):
            ProgressRing(fraction: fraction)
        case nil:
            Color.clear.frame(width: Glyph.ring, height: Glyph.ring)
        }
    }

    private enum StatusMark {
        case bars
        case ring(Double)
    }

    /// Bars while it is what you hear, a ring part-way and the same ring full once finished (rings
    /// mean listening, nothing else; ✓ is selection's only).
    private var statusMark: StatusMark? {
        if playState.isCurrent { return .bars }
        if case .partWay(let fraction, _) = progress { return .ring(fraction) }
        if case .finished = progress { return .ring(1) }
        return nil
    }

    /// "Playing", "18 min", "6 min left", "Finished", "Skipped"; nil for a folder row with its
    /// count.
    private var statusText: String? {
        if folderCount != nil { return nil }
        if playState.isCurrent {
            return playState == .playing ? String(localized: "Playing") : String(localized: "Paused")
        }
        switch (kind, progress) {
        case (_, .unplayed(let minutes?)): return ListeningTime.label(minutes: minutes)
        case (_, .unplayed(nil)): return nil
        case (_, .partWay(_, let left)): return ListeningTime.leftLabel(minutes: left)
        case (_, .finished): return ListeningTime.finishedLabel
        case (_, .skipped): return String(localized: "Skipped")
        }
    }

    /// What VoiceOver reads after the title: the subtitle and the status line.
    private var accessibilityStatus: String {
        var parts: [String] = []
        if let subtitle { parts.append(subtitle) }
        if let note { parts.append(note) }
        parts.append(contentsOf: details)
        if playState.isCurrent { parts.append(playState == .playing ? "Playing" : "Paused") }
        if isDropTarget { parts.append("Drop to move here") }
        if insertionEdge != nil { parts.append("Drop to place here") }
        if let count = folderCount {
            parts.append(contentsOf: count)
        } else {
            switch progress {
            case .unplayed(let minutes?): parts.append(ListeningTime.label(minutes: minutes))
            case .unplayed(nil): break
            case .partWay(_, let left): parts.append(ListeningTime.leftLabel(minutes: left))
            case .finished: parts.append(ListeningTime.finishedLabel)
            case .skipped: parts.append("Skipped in playback")
            }
        }
        if download != .notDownloaded { parts.append(download.label) }
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

    /// The thumbnail, dimmed under the download's `DownloadMark` while it downloads (C90): the ↓
    /// filling with its real progress while it renders now, grey while paused. Waiting its turn
    /// leaves the tile alone: the spinner is in the badge slot (C93).
    private var downloadLeading: some View {
        // A queued row's spinner is in its badge slot instead (C93).
        let downloading = download.isDownloading && !download.isQueued
        return leading
            .opacity(downloading ? Palette.downloadingOpacity : 1)
            .overlay {
                if downloading {
                    DownloadMark(state: download, size: thumbnailSide * 0.6)
                        .background(Circle().fill(Palette.paper).opacity(0.85))
                        .transition(.opacity)
                }
            }
    }

    private var isSkipped: Bool {
        if case .skipped = progress { return true }
        return false
    }

    @ViewBuilder
    private var leading: some View {
        switch kind {
        // Every row is the same compact row: folders, books and pages all lead with the page
        // thumbnail's column (as tall as the two lines), a cover inside it at its 1 : 1.45.
        case .folder(_, _, let cover?):
            ArtworkTile(image: cover, letter: title, size: thumbnailSide / 1.45,
                        isCover: true, fill: Palette.paper)
                .frame(width: thumbnailSide, height: thumbnailSide)
        case .folder(let symbol, _, nil):
            if folderHasDetails {
                ArtworkTile(image: nil, letter: title, size: thumbnailSide / 1.45,
                            isCover: true, fill: Palette.chrome)
                    .frame(width: thumbnailSide, height: thumbnailSide)
            } else {
                Image(systemName: symbol).tileSymbol().foregroundStyle(Palette.accent)
                    .frame(width: thumbnailSide, height: thumbnailSide)
            }
        case .page(let artwork, let letter):
            ArtworkTile(image: artwork, letter: letter, size: thumbnailSide, fill: Palette.paper)
        case .chapter:
            Color.clear
                .frame(width: Glyph.mark, height: Glyph.mark)
        case .link:
            Image(systemName: Icons.link)
                .foregroundStyle(Palette.secondaryInk)
                .frame(width: thumbnailSide)
        }
    }

    /// A page's thumbnail: as tall as its two lines of text, growing with them only up to
    /// `BottomChrome.maxTextGrowth` so the title keeps room at the largest sizes.
    private var thumbnailSide: CGFloat {
        let base = TypeStyle.row.lineHeight + TypeStyle.caption.lineHeight
        return BottomChrome.grown(titleLineHeight + captionLineHeight, from: base)
    }
}

/// A small progress ring: how far through a part-way page or chapter.
struct ProgressRing: View {
    let fraction: Double
    var size: CGFloat = Glyph.ring

    @Environment(\.readingPalette) private var reading

    var body: some View {
        ZStack {
            Circle().stroke(reading?.track ?? Palette.track, lineWidth: Glyph.stroke)
            Circle()
                .trim(from: 0, to: min(max(0, fraction), 1))
                .stroke(reading?.accent ?? Palette.accent, style: StrokeStyle(lineWidth: Glyph.stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

#if DEBUG
struct ListRowGallery: View {
    private let menu = AnyView(Button("Play", systemImage: Icons.play) {})

    var body: some View {
        PreviewGallery {
            PreviewState("folder") {
                ListRow(kind: .folder(count: ["4 pages"]), title: "Bonds", menu: menu)
                ListRow(kind: .folder(symbol: Icons.favorited, count: ["12 pages"]), title: "Favorites", menu: menu)
                ListRow(kind: .folder(count: ["Empty"], cover: Image(systemName: Icons.photo)), title: "A book with a cover",
                        menu: menu)
            }
            PreviewState("folder, a dragged row over it") {
                ListRow(kind: .folder(count: ["4 pages"]), title: "Bonds", isDropTarget: true, menu: menu)
            }
            PreviewState("a page with a dragged row about to be placed above it") {
                ListRow(kind: .page(letter: "M"), title: "Money Market Funds", subtitle: "investing.example.com",
                        progress: .unplayed(minutes: 12), insertionEdge: .top, menu: menu)
            }
            PreviewState("book: unplayed, part-way and downloading, playing and downloaded") {
                ListRow(kind: .folder(symbol: Icons.book, count: []), title: "Pride and Prejudice",
                        subtitle: "Jane Austen", progress: .unplayed(minutes: 645), menu: menu)
                ListRow(kind: .folder(symbol: Icons.book, count: []), title: "Pride and Prejudice",
                        subtitle: "Ch 24", progress: .partWay(fraction: 0.38, minutesLeft: 370),
                        download: .downloading(fraction: 0.2), folderHasDetails: true, menu: menu)
                ListRow(kind: .folder(symbol: Icons.library, count: []), title: "The Lighthouse Keeper",
                        subtitle: "Ch 14", progress: .partWay(fraction: 0.12, minutesLeft: 1210), playState: .playing,
                        download: .downloaded, menu: menu)
            }
            PreviewState("page: not downloaded, downloading, downloaded") {
                ListRow(kind: .page(letter: "N"), title: "Notes on Tides", subtitle: "example.org",
                        progress: .unplayed(minutes: 18), menu: menu)
                ListRow(kind: .page(letter: "N"), title: "Notes on Tides", subtitle: "example.org",
                        progress: .unplayed(minutes: 18), download: .downloading(fraction: 0.4), menu: menu)
                ListRow(kind: .page(letter: "N"), title: "Notes on Tides", subtitle: "example.org",
                        progress: .unplayed(minutes: 18), download: .downloaded, menu: menu)
            }
            PreviewState("page: part-way, playing, paused while downloading, finished") {
                ListRow(kind: .page(letter: "S"), title: "Seven-Day Yield: Definition, Calculation, and Example",
                        subtitle: "investing.example.com", progress: .partWay(fraction: 0.4, minutesLeft: 6),
                        download: .downloaded, menu: menu)
                ListRow(kind: .page(letter: "C"), title: "Coupon Basics", subtitle: "example.com",
                        progress: .partWay(fraction: 0.58, minutesLeft: 9), playState: .playing, download: .downloaded,
                        menu: menu)
                ListRow(kind: .page(letter: "C"), title: "Coupon Basics", subtitle: "example.com",
                        progress: .partWay(fraction: 0.58, minutesLeft: 9), playState: .paused,
                        download: .downloading(fraction: 0.1), menu: menu)
                ListRow(kind: .page(letter: "B"), title: "Bond Ladders", subtitle: "example.com", progress: .finished,
                        menu: menu)
            }
            PreviewState("in a folder: skipped; in Edit (no ⋯)") {
                ListRow(kind: .page(letter: "T"), title: "Title Page", progress: .skipped, menu: menu)
                ListRow(kind: .page(letter: "I"), title: "Index Funds", progress: .unplayed(minutes: 12))
            }
            PreviewState("a book's chapters before import") {
                VStack(spacing: 0) {
                    ListRow(kind: .chapter, title: "Chapter 1")
                    ListRow(kind: .chapter, title: "Chapter 2")
                }
            }
            PreviewState("link, and a link chapter waiting for its text") {
                ListRow(kind: .link, title: "investing.example.com", menu: menu)
                ListRow(kind: .link, title: "Chapter 26", subtitle: "not fetched yet", note: "Waiting", menu: menu)
            }
        }
    }
}

#Preview("ListRow · light", traits: .sizeThatFitsLayout) { ListRowGallery().previewVariant(.light) }
#Preview("ListRow · dark", traits: .sizeThatFitsLayout) { ListRowGallery().previewVariant(.dark) }
#Preview("ListRow · AX5", traits: .sizeThatFitsLayout) { ListRowGallery().previewVariant(.largestText) }
#endif
