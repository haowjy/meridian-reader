import SwiftUI

/// Reading one page, as a `Sheet` over the surface that opened it:
///
/// ```
/// ┌──────────────────────────────────────┐
/// │                 ───                  │ ← grabber
/// │ ( ‹ Browser )             (Aa) (☝︎)  │ ← `SheetTopBar`: the close pill names what is
/// │ … `text`: ReadingHeading, then the   │   underneath; `textAppearance` (Aa), `accessory` (☝︎)
/// │   text in the reading theme …        │
/// │ ╭ `bar` (the Now Playing bar) ─────╮ │ ← what you hear (always another page)
/// │ [🔖]  [ ▶  Listen  9 min ]  [ ⋯ ]    │ ← this page's own play button over slots 2–4
/// └──────────────────────────────────────┘
/// ```
///
/// Now Playing (`NowPlayingSheet`) has the same top bar, the same 🔖 and ⋯ slots and the same
/// colours (`palette`, the reading theme), so the controls stay put as Listen turns one into the
/// other. The close pill, the grabber and a pull
/// down all close it (`onClose`, after it has gone). 🔖 saves (tap) or files (long-press,
/// `onSaveToFolder`). `more` is the ⋯ button. `floating` floats just above the bottom band (a
/// toast).
struct ReaderSheet<Reading: View, Bar: View, More: View, TextAppearance: View, Accessory: View, Floating: View>: View {
    /// What is underneath: "Browser", "Library".
    let backTitle: String
    let listenTitle: String
    /// After Listen's title, lighter: "9 min", "6 min left".
    var listenDetail: String?
    let listenState: PlayState
    let isSaved: Bool
    let onClose: () -> Void
    let onListen: () -> Void
    let onToggleSave: () -> Void
    var onSaveToFolder: (() -> Void)?
    /// The reading theme's colours.
    var palette: ReadingPalette = .app
    /// Aa (`TextAppearanceButton` and its panel), just before `accessory`.
    @ViewBuilder var textAppearance: TextAppearance
    /// The control at the trailing end of the top bar (☝︎, `JumpModeButton`).
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var text: Reading
    @ViewBuilder var bar: Bar
    @ViewBuilder var more: More
    @ViewBuilder var floating: Floating

    var body: some View {
        Sheet(onDismiss: onClose, palette: palette) {
            SheetTopBar { SheetClosePill(kind: .back(backTitle)) } trailing: {
                textAppearance
                accessory
            }
        } content: {
            text
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: Spacing.xs) {
                        bar
                        BottomToolbarSpanLayout {
                            saveButton
                            PlayStateButton(state: listenState,
                                            look: .pill(title: listenTitle, detail: listenDetail, expands: true),
                                            action: onListen)
                                .accessibilityIdentifier("listenPlayPause")
                            more
                                .foregroundStyle(palette.ink)
                        }
                    }
                    .bottomChromeBand()
                    .overlay(alignment: .top) { floating }
                }
        }
    }

    private var saveButton: some View {
        SaveToggleButton(isSaved: isSaved, identifier: "readerBookmark", onToggle: onToggleSave,
                         onSaveToFolder: onSaveToFolder)
    }
}

extension ReaderSheet where TextAppearance == EmptyView, Accessory == EmptyView, Floating == EmptyView {
    init(backTitle: String, listenTitle: String, listenDetail: String? = nil, listenState: PlayState, isSaved: Bool,
         onClose: @escaping () -> Void, onListen: @escaping () -> Void, onToggleSave: @escaping () -> Void,
         onSaveToFolder: (() -> Void)? = nil, @ViewBuilder text: () -> Reading, @ViewBuilder bar: () -> Bar,
         @ViewBuilder more: () -> More) {
        self.init(backTitle: backTitle, listenTitle: listenTitle, listenDetail: listenDetail, listenState: listenState,
                  isSaved: isSaved,
                  onClose: onClose, onListen: onListen, onToggleSave: onToggleSave, onSaveToFolder: onSaveToFolder,
                  textAppearance: { EmptyView() }, accessory: { EmptyView() }, text: text, bar: bar, more: more, floating: { EmptyView() })
    }
}

/// The top of a page in the Reader and Now Playing: its title over its source and length.
struct ReadingHeading: View {
    let title: String
    /// ["example.org", "9 min"], spaced apart (`DetailLine`).
    let detail: [String]

    @Environment(\.readingPalette) private var reading

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .typeStyle(.title)
                .foregroundStyle(reading?.ink ?? Palette.ink)
                .accessibilityAddTraits(.isHeader)
            DetailLine(detail)
                .typeStyle(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
struct ReaderSheetGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("another page playing") { frame(.idle, "Listen", "9 min", bar: true) }
            PreviewState("nothing playing, part-way, saved") {
                frame(.idle, "Resume", "6 min left", bar: false, saved: true)
            }
        }
    }

    private func frame(_ state: PlayState, _ title: String, _ detail: String, bar: Bool, saved: Bool = false)
        -> some View {
        ReaderSheet(backTitle: "Browser", listenTitle: title, listenDetail: detail, listenState: state, isSaved: saved,
                    onClose: {}, onListen: {}, onToggleSave: {}) {
            SampleReading(title: "Notes on Tides", detail: ["example.org", "9 min"])
        } bar: {
            if bar {
                NowPlayingBar(title: "Chapter 12: Hunsford", detail: ["Pride and Prejudice", "9 min left"],
                              progress: 0.3, state: .playing, onOpen: {}, onPlayPause: {}, onStop: {})
            }
        } more: {
            Image(systemName: Icons.more).toolbarIconFrame()
        }
        .frame(height: 640)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
    }
}

#Preview("ReaderSheet · light", traits: .sizeThatFitsLayout) { ReaderSheetGallery().previewVariant(.light) }
#Preview("ReaderSheet · dark", traits: .sizeThatFitsLayout) { ReaderSheetGallery().previewVariant(.dark) }
#Preview("ReaderSheet · AX5", traits: .sizeThatFitsLayout) { ReaderSheetGallery().previewVariant(.largestText) }
#endif
