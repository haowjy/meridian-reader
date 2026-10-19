import SwiftUI

/// The top of a folder screen, centred (YouTube Music's album header). A book, a followed story,
/// or a folder given details (`detailed`): the cover, then the title and details. A plain folder:
/// its title and counts. Under them, once it has started, where it is ("3 of 7   38%   6 h 10 min
/// left", parts spaced apart, never joined by a separator); then the caller's `status` (a followed
/// story's line); then, for a folder whose pages play (`actions`), one row: its Download control,
/// the big ▶ and *More* (the caller's `more`, the folder's own menu).
///
/// ```
///                ╭──────╮
///                │cover │
///                ╰──────╯
///          Pride and Prejudice
///      Jane Austen   Book   61 chapters
///     24 of 61   38%   6 h 10 min left
///        ◯↓          ( ▶ )          ⋯
///     Download                     More
/// ```
///
/// The Download control is a `DownloadMark` (an outline ↓, the circle filling as it downloads, a
/// grey ✓ once downloaded) with what it shows written under it; *More* opens a menu; the ▶ is the
/// folder's Continue (⏸ while one of its pages is what you hear). The side controls share one
/// width, so the ▶ stays centred whatever their captions say. The row is an `ActionButtonRow`
/// (decision D21): with its captions while they fit whole, else the symbols alone (VoiceOver and
/// the large content viewer keep the names), so it never wraps or cuts a word. Takes plain
/// values and closures only; `anchor` lays a view of the caller's behind a side control, where a
/// question the control asks attaches, so on iOS 26 its popover points at that control.
struct FolderHeader<Status: View, More: View, Anchor: View>: View {
    var style: FolderHeaderStyle = .folder
    let title: String
    /// Counts (["2 folders", "7 pages"]) or the book's line (["Jane Austen", "Book", "61 chapters"]).
    let detail: [String]
    /// Where it came from (["Added 2 Oct"]); empty: no line.
    var source: [String] = []
    /// Where it is (["3 of 7", "38%", "6 h 10 min left"]); empty: no line.
    var progressLabel: [String] = []
    /// nil: no action row (none of its pages play).
    var actions: FolderHeaderActions?
    @ViewBuilder var status: Status
    @ViewBuilder var more: More
    /// Laid behind the Download control and *More*, at their size.
    @ViewBuilder var anchor: (FolderHeaderControl) -> Anchor

    @ScaledMetric(relativeTo: .title3) private var scaledCoverWidth: CGFloat = 80
    @ScaledMetric(relativeTo: .caption) private var scaledSideWidth: CGFloat = 76
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The cover grows with the text, up to `BottomChrome.maxTextGrowth`.
    private var coverWidth: CGFloat { BottomChrome.grown(scaledCoverWidth, from: 80) }
    /// Each side control's column, so the ▶ stays centred.
    private var sideWidth: CGFloat { BottomChrome.grown(scaledSideWidth, from: 76) }

    var body: some View {
        VStack(spacing: Spacing.s) {
            if case .detailed(let cover) = style {
                ArtworkTile(image: cover, letter: title, size: coverWidth, isCover: true)
                    .floatingShadow(opacity: 0.15)
                    .padding(.bottom, Spacing.xxs)
            }
            VStack(spacing: Spacing.xxs) {
                Text(title)
                    .typeStyle(style.isDetailed ? .heading : .title, design: .default)
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: Spacing.xxs) {
                    DetailLine(detail)
                    if !source.isEmpty { DetailLine(source) }
                    if !progressLabel.isEmpty {
                        DetailLine(progressLabel)
                            .monospacedDigit()
                            .accessibilityIdentifier("folderHeaderProgress")
                    }
                }
                .typeStyle(.caption)
            }
            status
            if let actions { actionRow(actions) }
        }
        .frame(maxWidth: .infinity)
    }

    private func actionRow(_ actions: FolderHeaderActions) -> some View {
        ActionButtonRow { fit in
            actionControls(actions, captions: fit != .icon)
        }
        .padding(.top, Spacing.xs)
    }

    private func actionControls(_ actions: FolderHeaderActions, captions: Bool) -> some View {
        CentredSidesLayout(spacing: Spacing.l, minSide: sideWidth) {
            Button(action: actions.onDownload) {
                sideLabel(actions.download.label, shown: captions) {
                    DownloadMark(state: actions.download)
                }
            }
            .buttonStyle(PillPressStyle())
            .accessibilityLabel(Verbs.download)
            .accessibilityValue(downloadValue(actions))
            .accessibilityIdentifier("folderDownload")
            .background { anchor(.download) }
            PlayStateButton(state: actions.play, look: .disc, action: actions.onPlay)
                .accessibilityIdentifier("folderContinue")
            Menu { more } label: {
                sideLabel(Verbs.more, shown: captions) {
                    Image(systemName: Icons.more)
                        .font(.system(size: Glyph.control * 0.8, weight: .semibold))
                        .foregroundStyle(Palette.secondaryInk)
                        .frame(width: Glyph.control, height: Glyph.control)
                }
            }
            .accessibilityLabel(Verbs.more)
            .accessibilityIdentifier("folderMore")
            .background { anchor(.more) }
        }
    }

    /// A side control: its glyph in a 44 pt square, its caption under it (`shown`), whole: a
    /// caption that doesn't fit makes the row drop them all.
    private func sideLabel(_ caption: String, shown: Bool, @ViewBuilder glyph: () -> some View) -> some View {
        VStack(spacing: 0) {
            glyph()
                .frame(width: BottomChrome.minTapTarget, height: BottomChrome.minTapTarget)
            if shown {
                Text(caption)
                    .typeStyle(.caption)
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .contentShape(Rectangle())
        .accessibilityShowsLargeContentViewer { Text(caption) }
    }

    /// "On, 40 percent", "On, downloaded", "Off".
    private func downloadValue(_ actions: FolderHeaderActions) -> String {
        var parts = [actions.downloadIsOn ? String(localized: "On") : String(localized: "Off")]
        switch actions.download {
        case .downloading, .paused: parts.append(actions.download.percentText)
        case .downloaded: parts.append(actions.download.label)
        case .notDownloaded: break
        }
        return parts.joined(separator: ", ")
    }
}

extension FolderHeader where Anchor == EmptyView {
    init(style: FolderHeaderStyle = .folder, title: String, detail: [String], source: [String] = [],
         progressLabel: [String] = [], actions: FolderHeaderActions? = nil,
         @ViewBuilder status: () -> Status, @ViewBuilder more: () -> More) {
        self.init(style: style, title: title, detail: detail, source: source, progressLabel: progressLabel,
                  actions: actions, status: status, more: more, anchor: { _ in EmptyView() })
    }
}

/// Three views in a row, the middle one centred: both sides take the wider side's width (at least
/// `minSide`), so the row's ideal width is honest about its captions and an `ActionButtonRow` can
/// tell when they don't fit.
private struct CentredSidesLayout: Layout {
    let spacing: CGFloat
    let minSide: CGFloat

    private func side(_ subviews: Subviews) -> CGFloat {
        [subviews.first, subviews.last].compactMap { $0?.sizeThatFits(.unspecified).width }.reduce(minSide, max)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 3 else { return .zero }
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return CGSize(width: 2 * side(subviews) + sizes[1].width + 2 * spacing,
                      height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let side = side(subviews)
        let centre = subviews[1].sizeThatFits(.unspecified)
        let xs = [bounds.midX - centre.width / 2 - spacing - side / 2, bounds.midX, bounds.midX + centre.width / 2 + spacing + side / 2]
        for (subview, x) in zip(subviews, xs) {
            subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .center, proposal: .unspecified)
        }
    }
}

/// A `FolderHeader` side control, for its `anchor`.
enum FolderHeaderControl {
    case download, more
}

/// A `FolderHeader`'s action row: its values and what its controls do.
struct FolderHeaderActions {
    var download: DownloadState
    /// The folder's Download toggle (VoiceOver reads it with the state).
    var downloadIsOn: Bool
    var onDownload: () -> Void
    var play: PlayState
    var onPlay: () -> Void
}

/// How a `FolderHeader` lays out its top.
enum FolderHeaderStyle {
    /// Title and counts.
    case folder
    /// The cover (a letter tile without one) above the title and details.
    case detailed(cover: Image?)

    var isDetailed: Bool {
        if case .detailed = self { return true }
        return false
    }
}

#if DEBUG
struct FolderHeaderGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("folder, none of its pages play") {
                header(title: "Finance", detail: ["2 folders"], actions: nil)
            }
            PreviewState("folder of pages, not started, not downloaded") {
                header(title: "Finance", detail: ["2 folders", "7 pages"], progress: ["52 min"],
                       actions: .init(download: .notDownloaded, downloadIsOn: false, onDownload: {}, play: .idle, onPlay: {}))
            }
            PreviewState("book, part-way, downloading 40%") {
                header(style: .detailed(cover: nil), title: "Pride and Prejudice",
                       detail: ["Jane Austen", "Book", "61 chapters"], progress: ["24 of 61", "38%", "6 h 10 min left"],
                       actions: .init(download: .downloading(fraction: 0.4), downloadIsOn: true, onDownload: {},
                                      play: .idle, onPlay: {}))
            }
            PreviewState("followed story, a chapter playing, downloaded") {
                FolderHeader(style: .detailed(cover: nil), title: "The Lantern Road", detail: ["A. Writer", "108 chapters"],
                             progressLabel: ["24 of 108", "20%", "41 h left"],
                             actions: .init(download: .downloaded, downloadIsOn: true, onDownload: {}, play: .playing,
                                            onPlay: {})) {
                    HeaderLink(symbol: Icons.follow, parts: ["Following", "41 of 108 fetched"]) {}
                } more: {
                    Button(Verbs.playFromStart, systemImage: Icons.previous) {}
                }
            }
        }
    }

    private func header(style: FolderHeaderStyle = .folder, title: String, detail: [String], progress: [String] = [],
                        actions: FolderHeaderActions?) -> some View {
        FolderHeader(style: style, title: title, detail: detail, progressLabel: progress, actions: actions) {
            EmptyView()
        } more: {
            Button(Verbs.playFromStart, systemImage: Icons.previous) {}
        }
    }
}

#Preview("FolderHeader · light", traits: .sizeThatFitsLayout) { FolderHeaderGallery().previewVariant(.light) }
#Preview("FolderHeader · dark", traits: .sizeThatFitsLayout) { FolderHeaderGallery().previewVariant(.dark) }
#Preview("FolderHeader · AX5", traits: .sizeThatFitsLayout) { FolderHeaderGallery().previewVariant(.largestText) }
#endif
