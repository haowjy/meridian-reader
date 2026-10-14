import SwiftUI

/// The top of a folder screen. A plain folder: its title and counts. A book, a series, or a
/// folder given details (`detailed`): the cover, title, details, how far through, and its play
/// buttons (`actions`: Continue, From Start and Download, in an `ActionButtonRow`, so one line
/// at every width and text size). A plain folder whose pages play has the progress and buttons
/// too, under its title.
///
/// ```
/// Finance                        ╭──────╮  Pride and Prejudice
/// 2 folders   7 pages            │cover │  Jane Austen   Book   61 chapters
///                                ╰──────╯  Added 2 Oct
///                                ━━━━━━━━━━━━━━━━░░░░░░░░░░░░░░░░░░░░░░░░░░
///                                38%   6 h 10 min left
///                                ( ▶ Continue  Ch 24   ) ( ⏮ From Start ) (⬇)
/// ```
///
/// Every block spans the content width and nothing pads it: in a Library list the section
/// header already sits on the page margin, so the bar, the buttons and the cards below share
/// both edges. Each line is separate parts set apart by space (`DetailLine`): the first in
/// secondary ink, the rest in tertiary. At accessibility text sizes the cover sits above the
/// title rather than beside it, so the title keeps the line.
struct FolderHeader<Actions: View>: View {
    var style: FolderHeaderStyle = .folder
    let title: String
    /// Counts (["2 folders", "7 pages"]) or the book's line (["Jane Austen", "Book", "61 chapters"]).
    let detail: [String]
    /// Where it came from (["Added 2 Oct"], a series' contents page); empty: no line.
    var source: [String] = []
    /// 0…1 through a book or series; nil: no progress line.
    var progress: Double?
    /// Under the progress line, on one line (["38%", "6 h 10 min left"]).
    var progressLabel: [String] = []
    @ViewBuilder var actions: Actions

    @ScaledMetric(relativeTo: .title3) private var scaledCoverWidth: CGFloat = 96
    @ScaledMetric(relativeTo: TypeStyle.caption.relativeTo) private var partSpacing = Spacing.s
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The cover grows with the text, up to `BottomChrome.maxTextGrowth`.
    private var coverWidth: CGFloat { BottomChrome.grown(scaledCoverWidth, from: 96) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            switch style {
            case .folder:
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title)
                        .typeStyle(.title, design: .default)
                        .foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    lines
                }
            case .detailed(let cover):
                let stack = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.m))
                    : AnyLayout(HStackLayout(alignment: .bottom, spacing: Spacing.m))
                stack {
                    ArtworkTile(image: cover, letter: title, size: coverWidth, isCover: true)
                        .floatingShadow(opacity: 0.15)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(title)
                            .typeStyle(.heading)
                            .foregroundStyle(Palette.ink)
                            .accessibilityAddTraits(.isHeader)
                        lines
                    }
                }
            }
            if let progress {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ThinProgressBar(value: progress)
                    if !progressLabel.isEmpty { progressLine }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(DetailLine.accessibilityLabel(progressLabel))
                .accessibilityIdentifier("folderHeaderProgress")
            }
            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var lines: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            DetailLine(detail)
            if !source.isEmpty { DetailLine(source) }
        }
        .typeStyle(.caption)
    }

    /// "38%   6 h 10 min left": one line, never wrapped (it shrinks a little at the largest
    /// sizes instead), the percent in secondary ink and the time in tertiary.
    private var progressLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: partSpacing) {
            ForEach(Array(progressLabel.enumerated()), id: \.offset) { index, part in
                Text(part)
                    .foregroundStyle(index == 0 ? DetailLine.leadInk(false) : DetailLine.restInk(false))
            }
        }
        .typeStyle(.caption)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

/// How a `FolderHeader` lays out its top.
enum FolderHeaderStyle {
    /// Title and counts.
    case folder
    /// The cover (a letter tile without one) beside the title and details.
    case detailed(cover: Image?)
}

extension FolderHeader where Actions == EmptyView {
    init(title: String, detail: [String]) {
        self.init(title: title, detail: detail) { EmptyView() }
    }
}

#if DEBUG
struct FolderHeaderGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("folder") {
                FolderHeader(title: "Finance", detail: ["2 folders", "7 pages"])
            }
            PreviewState("book, not playing") {
                FolderHeader(style: .detailed(cover: nil), title: "Pride and Prejudice",
                             detail: ["Jane Austen", "Book", "61 chapters"], source: ["Added 2 Oct"],
                             progress: 0.02, progressLabel: ["2%", "8 h 48 min left"]) {
                    PreviewActions(title: "Continue", detail: "Ch 24")
                }
            }
            PreviewState("folder with details") {
                FolderHeader(style: .detailed(cover: nil), title: "Tide Tables",
                             detail: ["A. Writer", "1 folder", "4 pages"],
                             progress: 0.5, progressLabel: ["50%", "22 min left"]) {
                    PreviewActions(title: "Continue", detail: "3 of 4")
                }
            }
            PreviewState("series, a chapter playing") {
                FolderHeader(style: .detailed(cover: nil), title: "The Lantern Road",
                             detail: ["serials.example.com", "Series", "108 chapters", "13 saved"],
                             progress: 0.2, progressLabel: ["20%"]) {
                    PreviewActions(title: "Playing", detail: "Ch 24", state: .playing, download: .downloading(fraction: 0.3))
                }
            }
        }
    }
}

/// The header's action row as `FolderPlayButtons` draws it.
private struct PreviewActions: View {
    let title: String
    let detail: String
    var state: PlayState = .idle
    var download: DownloadState = .available

    var body: some View {
        ActionButtonRow { fit in
            PlayStateButton(state: state, look: .pill(title: title, detail: detail, expands: true, fit: fit)) {}
            PillButton("From Start", shortTitle: "Start", systemImage: "backward.end.fill", style: .neutral, fit: fit) {}
            DownloadStateButton(state: download, look: .round) {}
        }
    }
}

#Preview("FolderHeader · light", traits: .sizeThatFitsLayout) { FolderHeaderGallery().previewVariant(.light) }
#Preview("FolderHeader · dark", traits: .sizeThatFitsLayout) { FolderHeaderGallery().previewVariant(.dark) }
#Preview("FolderHeader · AX5", traits: .sizeThatFitsLayout) { FolderHeaderGallery().previewVariant(.largestText) }
#endif
