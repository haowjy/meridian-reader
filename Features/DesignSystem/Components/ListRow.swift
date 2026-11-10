import SwiftUI

/// Every row in the Library, a folder, a book's contents, the browser's history and Prepared audio.
///
/// ```
/// 📁 Bonds                                       ⋯   folder: its count on the second line
///    2 folders   3 articles
/// ▣  Pride and Prejudice                         ⋯   book: its place and time left
///    Ch 24   6 h 10 min left                ◐  ⋯   (the listening column: ◐ part-way)
/// ▣ Coupon Basics                             ●  ⋯   page, prepared: ●↓ before line two;
/// ▣ ●↓ example.com   Finished                          ● the same ring, full
/// ▣̲ Seven-Day Yield                          ▂▅▇ ⋯   page, playing and preparing: tinted,
/// ▣ ◔ Playing                                         bars; the prepare's ring before line two
/// 🔗 Chapter 26                                    ⋯   a chapter waiting for its text: the arc
///    ◜ Waiting
/// 🔗 serials.example.com                              link: lighter
/// ```
///
/// The row draws; tapping it is the caller's (a `NavigationLink` behind it, `opensOnTap`). A
/// page's row is exactly two lines: its title on one line (truncated), then one line of what it
/// is and where it stands; its thumbnail is as tall as the two lines. At the accessibility sizes
/// the title runs the row's width on up to three lines, over the thumbnail, line two and the ⋯. The second line's parts are
/// spaced apart, never joined by a separator: the first in secondary ink, the rest in tertiary,
/// the status in the accent while it is what you hear ("Playing", "Paused"). The leading parts
/// give way first, and at accessibility sizes the status shows alone.
///
/// Its listening mark stands in a fixed-width column at the trailing edge, just before the
/// accessory and the ⋯ (`Glyph.regular`), so every row's ring lines up: a ring part-way,
/// the same ring full once finished, the bars while it is what you hear, and nothing (the column
/// kept, so nothing shifts) before it starts. Line two keeps the words ("18 min", "6 min left",
/// "Finished", "Playing"). Rows with no listening (a folder with its count, a book preview's
/// chapter, `showsListening` false: browser visits, prepared audio) have no column.
///
/// Its prepare (`prepare`) or a link page's fetch (`download`) shows on the row itself, never as a
/// button: a `DownloadMark` as tall as the text before line two, the app's one download look (the
/// spinning arc while it waits, the ring filling while it renders, grey while paused, ●↓ once
/// prepared). The trailing ⋯ (`menu`, the same menu as the row's long press) is in the row's accessory slot
/// (`RowMetrics`: its glyph ends where every card's text does); a row with a control of its own (a
/// prepare's pause, `accessory`) has it just before the ⋯. Every row's separator starts at its title,
/// whatever leads it. Its height is a two-line row's (`RowMetrics`), in Edit and out.
///
/// A folder row under a dragged row that it takes (`isDropTarget`) is washed and outlined in the
/// accent, with a selection tick as it lights up.
struct ListRow: View {
    enum Kind {
        /// A folder (a book or a series too): its symbol, or a book's cover when it has one, and
        /// what is in it ("2 folders", "3 articles"; "Empty") for its second line; none (`[]`) for a
        /// folder whose pages play, whose second line is its place and time left.
        case folder(symbol: String = Icons.folder, count: [String], cover: Image? = nil)
        /// A saved page: its site icon (or a letter tile).
        case article(artwork: Image? = nil, letter: String)
        /// A chapter in a book's preview: its title alone, after an empty mark's width.
        case chapter
        /// A page that is only an address so far (a saved address, a chapter not fetched).
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
    /// More parts after the note, in the same tertiary ink (a prepare's count and size).
    var details: [String] = []
    var progress: Progress = .unplayed(minutes: nil)
    var playState: PlayState = .idle
    /// A dragged row is over this one, and it takes the drop (a folder it would be filed in).
    var isDropTarget = false
    /// A dragged row would be placed beside this one, on this side: a line marks the place.
    var insertionEdge: VerticalEdge?
    /// Where its prepare stands: its `DownloadMark` before line two.
    var prepare: PrepareState = .notPrepared
    /// Where a link page's text stands while it is fetched or waits to be (a followed story's
    /// chapter): its `DownloadMark` before line two, in the prepare's place.
    var download: DownloadMark.State?
    var folderHasDetails = false
    /// The rows of its ⋯ menu, the same as its long press (nil: no ⋯, as in Edit).
    var menu: AnyView?
    /// A view laid behind the ⋯ at its size (behind the row when it has none): a question its menu
    /// asks attaches there, so on iOS 26 its popover points at the ⋯.
    var menuAnchor: AnyView?
    /// A control of the row's own, 44 pt, just before the ⋯ (a prepare's pause / resume).
    var accessory: AnyView?
    /// A drag handle shown where the ⋯ sits, in Edit: only the handle initiates reorder.
    var editHandle: AnyView?
    /// Whether the row has the trailing listening column (false where listening never shows:
    /// browser visits, the Prepared Audio list).
    var showsListening = true

    /// Space between the second line's parts: `Spacing.s`, growing with the caption.
    @ScaledMetric(relativeTo: TypeStyle.caption.relativeTo) private var partSpacing = Spacing.s
    /// The two text lines' heights, scaled like their text: a page's thumbnail matches them.
    @ScaledMetric(relativeTo: TypeStyle.row.relativeTo) private var titleLineHeight = TypeStyle.row.lineHeight
    @ScaledMetric(relativeTo: TypeStyle.caption.relativeTo) private var captionLineHeight = TypeStyle.caption.lineHeight
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                accessibilityLayout
            } else {
                HStack(spacing: Spacing.s) {
                    HStack(spacing: RowMetrics.columnGap) {
                        leading
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 0) {
                            titleText
                                .lineLimit(1)
                            secondLine
                                .accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // The separator under the row starts at the title, for every kind of row.
                        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                    }
                    trailingControls
                }
            }
        }
        .background { if menu == nil { menuAnchor } }
        .padding(.leading, RowMetrics.edgeInset)
        .padding(.trailing, (menu != nil || editHandle != nil) ? RowMetrics.accessoryTrailing : RowMetrics.edgeInset)
        // A page's row is two lines in Edit and out.
        .rowHeight(lines: 2)
        .background(playState.isCurrent ? Palette.playingTint : Color.clear)
        .overlay { dropHighlight }
        .overlay(alignment: insertionEdge == .bottom ? .bottom : .top) { insertionLine }
        .opacity(isDimmed ? Palette.lighterRowOpacity : 1)
        .animation(Motion.snappy, value: isDropTarget)
        .animation(Motion.snappy, value: insertionEdge)
        .animation(Motion.standard, value: prepare)
        .sensoryFeedback(.selection, trigger: isDropTarget) { _, isTarget in isTarget }
        .sensoryFeedback(.selection, trigger: insertionEdge) { _, edge in edge != nil }
        .accessibilityElement(children: .contain)
    }

    /// At the accessibility sizes the title takes the row's whole width, up to three lines, and
    /// the thumbnail, the second line and the trailing controls go on a line under it: beside them
    /// a title would have room for a word or two.
    private var accessibilityLayout: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            titleText
                .lineLimit(RowMetrics.stackedTitleLines)
                .frame(maxWidth: .infinity, alignment: .leading)
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            HStack(spacing: Spacing.s) {
                leading
                    .accessibilityHidden(true)
                secondLine
                    .accessibilityHidden(true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                trailingControls
            }
        }
    }

    /// The title is the row's one VoiceOver element, its status the value (the rest is hidden); the
    /// ⋯ stays its own.
    private var titleText: some View {
        Text(title)
            .typeStyle(.row, weight: playState.isCurrent ? .semibold : .regular)
            .foregroundStyle(titleColor)
            .accessibilityValue(accessibilityStatus)
    }

    /// The listening column, the row's own control and the ⋯ (or Edit's handle).
    @ViewBuilder
    private var trailingControls: some View {
        if hasListeningColumn {
            listeningMark
                .frame(width: Glyph.regular)
                .accessibilityHidden(true)
        }
        if let accessory {
            accessory
                .rowAccessorySlot()
        }
        if let menu {
            Menu { menu } label: {
                Image(systemName: Icons.more)
                    .glyphSize(Glyph.regular, weight: .semibold)
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(width: RowMetrics.accessorySlot, height: RowMetrics.accessorySlot)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .padding(.vertical, -RowMetrics.verticalInset)
            .accessibilityLabel(Verbs.more)
            .accessibilityIdentifier("rowMore")
            .background { menuAnchor }
        } else if let editHandle {
            editHandle
                .padding(.vertical, -RowMetrics.verticalInset)
        }
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
            .padding(.leading, RowMetrics.edgeInset - Spacing.xs + (typeSize.isAccessibilitySize ? 0 : thumbnailSide + RowMetrics.columnGap))
            .padding(.trailing, RowMetrics.edgeInset)
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

    /// The download mark, the subtitle, the note, then the status, spaced apart on one
    /// line: "●↓ example.org   4 min left" (the listening ring is the trailing column's). The subtitle and note give way first; at
    /// accessibility sizes they are left out and the status truncates if it must, so the line
    /// never wraps or widens the row.
    @ViewBuilder
    private var secondLine: some View {
        let status = statusText
        // At accessibility sizes there is no room for both: the status alone (VoiceOver reads all).
        let leads = typeSize.isAccessibilitySize && status != nil ? []
            : [subtitle, note].compactMap { $0 } + details + (folderCount ?? [])
        let mark = slotMark
        if !leads.isEmpty || status != nil || mark != nil {
            HStack(spacing: partSpacing / 2) {
                if let mark {
                    DownloadMark(state: mark.state, act: mark.act, size: statusMarkSize)
                        .transition(.opacity)
                }
                DetailLine(parts: leads.map { DetailPart($0) }
                           + [status.map { DetailPart($0, isLit: playState.isCurrent) }].compactMap { $0 },
                           wraps: false)
                    .monospacedDigit()
            }
            .typeStyle(.caption)
        }
    }

    /// The `DownloadMark` before line two, as tall as its text: a link page's fetch (`download`),
    /// else its prepare while it waits, renders or is paused, and ●↓ once prepared (a skipped
    /// chapter never plays, so it shows none). Nil before either starts.
    private var slotMark: (state: DownloadMark.State, act: DownloadMark.Act)? {
        if let download { return (download, .download) }
        switch prepare {
        case .notPrepared: return nil
        case .prepared: return isSkipped ? nil : (prepare.mark, .prepare)
        default: return (prepare.mark, .prepare)
        }
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

    /// Bars while it is what you hear, a ring part-way and the same ring full once finished (a ring
    /// in this column is listening; a download's is before line two; ✓ is selection's only).
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
        if prepare != .notPrepared { parts.append(prepare.label) }
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

    /// The line-two prepare mark's side: as tall as the caption text.
    @ScaledMetric(relativeTo: TypeStyle.caption.relativeTo) private var statusMarkSize = Glyph.inline

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
                Image(systemName: symbol).glyphSize(Glyph.regular).foregroundStyle(Palette.accent)
                    .frame(width: thumbnailSide, height: thumbnailSide)
            }
        case .article(let artwork, let letter):
            ArtworkTile(image: artwork, letter: letter, size: thumbnailSide, fill: Palette.paper)
        case .chapter:
            Color.clear
                .frame(width: Glyph.regular, height: Glyph.regular)
        case .link:
            Image(systemName: Icons.link)
                .foregroundStyle(Palette.secondaryInk)
                .frame(width: thumbnailSide)
        }
    }

    /// A page's thumbnail: as tall as its two lines of text, growing with them only up to
    /// `Control.maxTextGrowth` so the title keeps room at the largest sizes.
    private var thumbnailSide: CGFloat {
        let base = TypeStyle.row.lineHeight + TypeStyle.caption.lineHeight
        return Control.grown(titleLineHeight + captionLineHeight, from: base)
    }
}

#if DEBUG
struct ListRowGallery: View {
    private let menu = AnyView(Button("Play", systemImage: Icons.play) {})

    var body: some View {
        PreviewGallery {
            PreviewState("folder") {
                ListRow(kind: .folder(count: ["4 pages"]), title: "Bonds", menu: menu)
                ListRow(kind: .folder(symbol: Icons.folder, count: ["12 pages"]), title: "Reading list", menu: menu)
                ListRow(kind: .folder(count: ["Empty"], cover: Image(systemName: Icons.photo)), title: "A book with a cover",
                        menu: menu)
            }
            PreviewState("folder, a dragged row over it") {
                ListRow(kind: .folder(count: ["4 pages"]), title: "Bonds", isDropTarget: true, menu: menu)
            }
            PreviewState("a page with a dragged row about to be placed above it") {
                ListRow(kind: .article(letter: "M"), title: "Money Market Funds", subtitle: "investing.example.com",
                        progress: .unplayed(minutes: 12), insertionEdge: .top, menu: menu)
            }
            PreviewState("book: unplayed, part-way and downloading, playing and downloaded") {
                ListRow(kind: .folder(symbol: Icons.folder, count: []), title: "Pride and Prejudice",
                        subtitle: "Jane Austen", progress: .unplayed(minutes: 645), menu: menu)
                ListRow(kind: .folder(symbol: Icons.folder, count: []), title: "Pride and Prejudice",
                        subtitle: "Ch 24", progress: .partWay(fraction: 0.38, minutesLeft: 370),
                        prepare: .preparing(fraction: 0.2), folderHasDetails: true, menu: menu)
                ListRow(kind: .folder(symbol: Icons.library, count: []), title: "The Lighthouse Keeper",
                        subtitle: "Ch 14", progress: .partWay(fraction: 0.12, minutesLeft: 1210), playState: .playing,
                        prepare: .prepared, menu: menu)
            }
            PreviewState("page: not downloaded, downloading, downloaded") {
                ListRow(kind: .article(letter: "N"), title: "Notes on Tides", subtitle: "example.org",
                        progress: .unplayed(minutes: 18), menu: menu)
                ListRow(kind: .article(letter: "N"), title: "Notes on Tides", subtitle: "example.org",
                        progress: .unplayed(minutes: 18), prepare: .preparing(fraction: 0.4), menu: menu)
                ListRow(kind: .article(letter: "N"), title: "Notes on Tides", subtitle: "example.org",
                        progress: .unplayed(minutes: 18), prepare: .prepared, menu: menu)
            }
            PreviewState("page: part-way, playing, paused while downloading, finished") {
                ListRow(kind: .article(letter: "S"), title: "Seven-Day Yield: Definition, Calculation, and Example",
                        subtitle: "investing.example.com", progress: .partWay(fraction: 0.4, minutesLeft: 6),
                        prepare: .prepared, menu: menu)
                ListRow(kind: .article(letter: "C"), title: "Coupon Basics", subtitle: "example.com",
                        progress: .partWay(fraction: 0.58, minutesLeft: 9), playState: .playing, prepare: .prepared,
                        menu: menu)
                ListRow(kind: .article(letter: "C"), title: "Coupon Basics", subtitle: "example.com",
                        progress: .partWay(fraction: 0.58, minutesLeft: 9), playState: .paused,
                        prepare: .preparing(fraction: 0.1), menu: menu)
                ListRow(kind: .article(letter: "B"), title: "Bond Ladders", subtitle: "example.com", progress: .finished,
                        menu: menu)
            }
            PreviewState("in a folder: skipped; in Edit (no ⋯)") {
                ListRow(kind: .article(letter: "T"), title: "Title Page", progress: .skipped, menu: menu)
                ListRow(kind: .article(letter: "I"), title: "Index Funds", progress: .unplayed(minutes: 12))
            }
            PreviewState("a book's chapters before import") {
                VStack(spacing: 0) {
                    ListRow(kind: .chapter, title: "Chapter 1")
                    ListRow(kind: .chapter, title: "Chapter 2")
                }
            }
            PreviewState("link, and a link chapter waiting for its text") {
                ListRow(kind: .link, title: "investing.example.com", menu: menu)
                ListRow(kind: .link, title: "Chapter 26", note: "Waiting", download: .waiting, menu: menu)
                ListRow(kind: .link, title: "Chapter 27", note: "Trying again in 1:52", download: .waiting, menu: menu)
            }
        }
    }
}

#Preview("ListRow · light", traits: .sizeThatFitsLayout) { ListRowGallery().previewVariant(.light) }
#Preview("ListRow · dark", traits: .sizeThatFitsLayout) { ListRowGallery().previewVariant(.dark) }
#Preview("ListRow · AX5", traits: .sizeThatFitsLayout) { ListRowGallery().previewVariant(.largestText) }
#endif
