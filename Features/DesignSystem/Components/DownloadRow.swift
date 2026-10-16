import SwiftUI

/// A row in the Downloads list (decision D16): what was downloaded, the voice it renders or was
/// rendered in, and where it is. The second line's parts are spaced apart (`DetailLine`), never
/// joined with a separator.
///
/// ```
/// ▣  Pride and Prejudice                  (◔⏸)   queued: a ring with pause, centred on the ⋯ slot
///    Kokoro Heart   4 of 12 chapters   38%
/// [i] Notes on Tides                      (◔↓)   paused: the ring with resume
///    Kokoro Heart   Paused
/// [i] Coupon Basics                               done
///    Kokoro Heart   12 MB
/// [i] Seven-Day Yield                             another voice: its two choices under it
///    Kokoro Bella   9 MB
///    ( ↻ Re-download )  ( ✓ Keep )   one line: symbols alone when short of room
/// ```
///
/// Tapping the row is the caller's (it opens what was downloaded). The title is the row's
/// VoiceOver element, the detail its value; the ring and the buttons are their own.
struct DownloadRow: View {
    enum Leading {
        /// A page: its site icon, or a letter tile.
        case page(artwork: Image?, letter: String)
        /// A folder, book or series: its symbol, or a book's cover.
        case folder(symbol: String, cover: Image?)
    }

    /// The trailing control of a download still running or waiting.
    struct Transfer {
        var fraction: Double
        /// Paused: the ring offers to resume (↓); otherwise to pause.
        var isPaused: Bool
        var toggle: () -> Void
    }

    /// A choice under the detail line (*Re-download*, *Keep*).
    struct Choice: Identifiable {
        var title: String
        /// Its symbol: before the title, and alone when the row is short of room.
        var systemImage: String
        /// The filled pill; the others are neutral.
        var isPrimary = false
        var identifier: String
        var perform: () -> Void

        var id: String { identifier }
    }

    let leading: Leading
    let title: String
    var detail: [String] = []
    var transfer: Transfer?
    var choices: [Choice] = []

    @ScaledMetric(relativeTo: .callout) private var scaledMinHeight: CGFloat = 56
    @State private var width: CGFloat = 0

    var body: some View {
        HStack(spacing: Spacing.s) {
            HStack(alignment: .top, spacing: Spacing.s) {
                leadingView
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title)
                            .typeStyle(.row)
                            .foregroundStyle(Palette.ink)
                            .lineLimit(2)
                            .accessibilityValue(DetailLine.accessibilityLabel(detail))
                        if !detail.isEmpty {
                            DetailLine(detail)
                                .typeStyle(.caption)
                                .monospacedDigit()
                                .accessibilityHidden(true)
                        }
                    }
                    if !choices.isEmpty {
                        ActionButtonRow(spacing: Spacing.xs) { fit in
                            ForEach(choices) { choice in
                                PillButton(choice.title, systemImage: choice.systemImage,
                                           style: choice.isPrimary ? .filled : .neutral, size: .compact, fit: fit,
                                           action: choice.perform)
                                    .accessibilityIdentifier(choice.identifier)
                            }
                        }
                        .padding(.top, Spacing.xxs)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let transfer {
                TransferControl(transfer: transfer)
            }
        }
        .padding(.leading, Spacing.m)
        .padding(.trailing, transfer != nil ? ListRow.trailingColumnPadding(rowWidth: width) : Spacing.m)
        .padding(.vertical, Spacing.xs)
        .frame(minHeight: BottomChrome.grown(scaledMinHeight, from: 56))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { if $0 != width { width = $0 } }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var leadingView: some View {
        switch leading {
        case .page(let artwork, let letter):
            ArtworkTile(image: artwork, letter: letter, size: ListRow.leadingWidth, fill: Palette.paper)
        case .folder(_, let cover?):
            ArtworkTile(image: cover, letter: title, size: ListRow.coverWidth, isCover: true, fill: Palette.paper)
                .frame(width: ListRow.leadingWidth)
        case .folder(let symbol, nil):
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Palette.accent)
                .frame(width: ListRow.leadingWidth)
        }
    }
}

/// The ring a running download fills, with ⏸ inside to pause it, or ↓ to resume a paused one.
/// 44 pt to tap, centred like the rows' ▶.
private struct TransferControl: View {
    let transfer: DownloadRow.Transfer

    var body: some View {
        Button(action: transfer.toggle) {
            ZStack {
                ProgressRing(fraction: transfer.fraction, size: Glyph.control)
                    .animation(Motion.standard, value: transfer.fraction)
                Image(systemName: transfer.isPaused ? Icons.downloadInRing : Icons.pause)
                    .font(.system(size: Glyph.control * 0.4, weight: .bold))
                    .foregroundStyle(Palette.accent)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: Glyph.control, height: Glyph.control)
            .frame(width: BottomChrome.minTapTarget, height: BottomChrome.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(transfer.isPaused ? "Resume Download" : "Pause Download")
        .accessibilityValue("\(Int((transfer.fraction * 100).rounded())) percent")
        .accessibilityIdentifier(transfer.isPaused ? "downloadResume" : "downloadPause")
    }
}

#if DEBUG
struct DownloadRowGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("downloading a book") {
                DownloadRow(leading: .folder(symbol: Icons.book, cover: nil), title: "Pride and Prejudice",
                            detail: ["Kokoro Heart", "4 of 12 chapters", "38%"],
                            transfer: .init(fraction: 0.38, isPaused: false) {})
                    .background(Palette.chrome)
            }
            PreviewState("queued, paused") {
                DownloadRow(leading: .page(artwork: nil, letter: "N"), title: "Notes on Tides",
                            detail: ["Kokoro Heart", "Queued"], transfer: .init(fraction: 0, isPaused: false) {})
                    .background(Palette.chrome)
                DownloadRow(leading: .page(artwork: nil, letter: "B"), title: "Bond Ladders",
                            detail: ["Kokoro Heart", "Paused", "60%"], transfer: .init(fraction: 0.6, isPaused: true) {})
                    .background(Palette.chrome)
            }
            PreviewState("done") {
                DownloadRow(leading: .page(artwork: nil, letter: "C"), title: "Coupon Basics",
                            detail: ["Kokoro Heart", "12 MB"])
                    .background(Palette.chrome)
            }
            PreviewState("another voice") {
                DownloadRow(leading: .page(artwork: nil, letter: "S"),
                            title: "Seven-Day Yield: Definition, Calculation, and Example",
                            detail: ["Kokoro Bella", "9 MB"],
                            choices: [.init(title: "Re-download", systemImage: Icons.redownload, isPrimary: true, identifier: "redownload") {},
                                      .init(title: "Keep", systemImage: Icons.checkmark, identifier: "keep") {}])
                    .background(Palette.chrome)
            }
        }
    }
}

#Preview("DownloadRow · light", traits: .sizeThatFitsLayout) { DownloadRowGallery().previewVariant(.light) }
#Preview("DownloadRow · dark", traits: .sizeThatFitsLayout) { DownloadRowGallery().previewVariant(.dark) }
#Preview("DownloadRow · AX5", traits: .sizeThatFitsLayout) { DownloadRowGallery().previewVariant(.largestText) }
#endif
