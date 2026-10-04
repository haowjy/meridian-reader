import SwiftUI

/// Reading one page, as a `Sheet` over the surface that opened it:
///
/// ```
/// ┌──────────────────────────────────────┐
/// │                 ───                  │ ← grabber
/// │ ( ‹ Browser )                        │ ← back pill names what is underneath
/// │ … `text`: ReadingHeading, then serif │
/// │   text on paper …                    │
/// │ ╭ `bar` (the Now Playing bar) ─────╮ │ ← what you hear (always another page)
/// │ [🔖]  [ ▶  Listen · 9 min ]  [ ⋯ ]   │ ← this page's own play button over slots 2–4
/// └──────────────────────────────────────┘
/// ```
///
/// The back pill, the grabber and a pull down all close it (`onClose`, after it has gone).
/// 🔖 saves (tap) or files (long-press, `onSaveToFolder`). `more` is the ⋯ button.
struct ReaderSheet<Reading: View, Bar: View, More: View>: View {
    /// What is underneath: "Browser", "Library".
    let backTitle: String
    let listenTitle: String
    let listenState: PlayState
    let isSaved: Bool
    let onClose: () -> Void
    let onListen: () -> Void
    let onToggleSave: () -> Void
    var onSaveToFolder: (() -> Void)?
    @ViewBuilder var text: Reading
    @ViewBuilder var bar: Bar
    @ViewBuilder var more: More

    var body: some View {
        Sheet(onDismiss: onClose) {
            HStack {
                SheetBackPill(title: backTitle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.pageMargin)
            .padding(.bottom, Spacing.xs)
        } content: {
            text
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: Spacing.xs) {
                        bar
                        BottomToolbarSpanLayout {
                            saveButton
                            PlayStateButton(state: listenState, look: .pill(title: listenTitle, expands: true),
                                            action: onListen)
                            more
                        }
                    }
                    .bottomChromeBand()
                }
        }
    }

    private var saveButton: some View {
        Button(action: onToggleSave) {
            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                .foregroundStyle(isSaved ? Palette.accent : Palette.ink)
                .toolbarIconFrame()
        }
        .buttonStyle(.plain)
        // Long-press picks a folder; a tap released early still saves.
        .highPriorityGesture(
            LongPressGesture().onEnded { _ in onSaveToFolder?() },
            including: onSaveToFolder == nil ? .subviews : .all
        )
        .accessibilityLabel(isSaved ? "Remove from Library" : "Save")
        .accessibilityActions {
            if let onSaveToFolder {
                Button("Save to Folder…", action: onSaveToFolder)
            }
        }
    }
}

/// "‹ Browser": closes the sheet it sits in.
struct SheetBackPill: View {
    let title: String
    @Environment(\.dismissSheet) private var dismissSheet

    var body: some View {
        PillButton(title, systemImage: "chevron.backward", style: .neutral, size: .compact) { dismissSheet() }
            .accessibilityLabel("Back to \(title)")
    }
}

/// The top of a page in the Reader and Now Playing: its title over its source and length.
struct ReadingHeading: View {
    let title: String
    /// "example.org · 9 min".
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .typeStyle(.title)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Text(detail)
                .typeStyle(.caption)
                .foregroundStyle(Palette.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
struct ReaderSheetGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("another page playing") { frame(.idle, "Listen · 9 min", bar: true) }
            PreviewState("nothing playing, part-way, saved") {
                frame(.idle, "Resume · 6 min left", bar: false, saved: true)
            }
        }
    }

    private func frame(_ state: PlayState, _ title: String, bar: Bool, saved: Bool = false) -> some View {
        ReaderSheet(backTitle: "Browser", listenTitle: title, listenState: state, isSaved: saved,
                    onClose: {}, onListen: {}, onToggleSave: {}) {
            SampleReading(title: "Notes on Tides", detail: "example.org · 9 min")
        } bar: {
            if bar {
                NowPlayingBar(title: "Chapter 12: Hunsford", detail: "Pride and Prejudice · 9 min left",
                              progress: 0.3, state: .playing, onOpen: {}, onPlayPause: {}, onStop: {})
            }
        } more: {
            Image(systemName: "ellipsis").toolbarIconFrame()
        }
        .frame(height: 640)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
    }
}

#Preview("ReaderSheet · light", traits: .sizeThatFitsLayout) { ReaderSheetGallery().previewVariant(.light) }
#Preview("ReaderSheet · dark", traits: .sizeThatFitsLayout) { ReaderSheetGallery().previewVariant(.dark) }
#Preview("ReaderSheet · AX5", traits: .sizeThatFitsLayout) { ReaderSheetGallery().previewVariant(.largestText) }
#endif
