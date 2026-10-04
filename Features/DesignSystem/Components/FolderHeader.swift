import SwiftUI

/// The top of a folder screen. A plain folder: its title and counts. A book or series: the
/// cover, title, details, how far through, and its play buttons (`actions`: Continue and Play
/// from Start).
///
/// ```
/// Finance                        ╭──────╮  Pride and Prejudice
/// 2 folders · 7 pages            │cover │  Jane Austen · Book · 61 chapters
///                                ╰──────╯  From EPUB · imported 2 Oct
///                                ━━━━━━━━░░░░░░░  38% · 6 h 10 min left
///                                ( ▶ Continue · Ch 24 )   Play from Start
/// ```
struct FolderHeader<Actions: View>: View {
    enum Style {
        case folder
        case book(cover: Image?)
    }

    var style: Style = .folder
    let title: String
    /// Counts ("2 folders · 7 pages") or the book's line ("Jane Austen · Book · 61 chapters").
    let detail: String
    /// Where it came from ("From EPUB · imported 2 Oct", a series' contents page).
    var source: String?
    /// 0…1 through a book or series; nil: no progress line.
    var progress: Double?
    /// Beside the progress line ("38% · 6 h 10 min left").
    var progressLabel: String?
    @ViewBuilder var actions: Actions

    @ScaledMetric(relativeTo: .title3) private var coverWidth: CGFloat = 96

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
            case .book(let cover):
                HStack(alignment: .bottom, spacing: Spacing.m) {
                    ArtworkTile(image: cover, letter: title, size: coverWidth, isCover: true)
                        .shadow(color: .black.opacity(0.15), radius: Spacing.s, y: Spacing.xxs)
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
                HStack(spacing: Spacing.xs) {
                    ThinProgressBar(value: progress)
                    if let progressLabel {
                        Text(progressLabel)
                            .typeStyle(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Palette.secondaryInk)
                            .fixedSize()
                    }
                }
            }
            actions
        }
        .padding(.horizontal, Spacing.pageMargin)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var lines: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(detail)
            if let source { Text(source) }
        }
        .typeStyle(.caption)
        .foregroundStyle(Palette.secondaryInk)
    }
}

extension FolderHeader where Actions == EmptyView {
    init(title: String, detail: String) {
        self.init(title: title, detail: detail) { EmptyView() }
    }
}

#if DEBUG
struct FolderHeaderGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("folder") {
                FolderHeader(title: "Finance", detail: "2 folders · 7 pages")
            }
            PreviewState("book, not playing") {
                FolderHeader(style: .book(cover: nil), title: "Pride and Prejudice",
                             detail: "Jane Austen · Book · 61 chapters", source: "From EPUB · imported 2 Oct",
                             progress: 0.38, progressLabel: "38% · 6 h 10 min left") {
                    HStack(spacing: Spacing.s) {
                        PlayStateButton(state: .idle, look: .pill(title: "Continue · Ch 24")) {}
                        PillButton("Play from Start", style: .neutral) {}
                    }
                }
            }
            PreviewState("series, a chapter playing") {
                FolderHeader(style: .book(cover: nil), title: "The Lantern Road",
                             detail: "serials.example.com · Series · 108 chapters · 13 saved",
                             progress: 0.2, progressLabel: "20%") {
                    PlayStateButton(state: .playing, look: .pill(title: "Playing · Ch 24")) {}
                }
            }
        }
    }
}

#Preview("FolderHeader · light", traits: .sizeThatFitsLayout) { FolderHeaderGallery().previewVariant(.light) }
#Preview("FolderHeader · dark", traits: .sizeThatFitsLayout) { FolderHeaderGallery().previewVariant(.dark) }
#Preview("FolderHeader · AX5", traits: .sizeThatFitsLayout) { FolderHeaderGallery().previewVariant(.largestText) }
#endif
