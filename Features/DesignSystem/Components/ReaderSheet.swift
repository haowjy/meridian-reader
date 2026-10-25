import SwiftUI

/// Reading one page, as a `Sheet` over the surface that opened it:
///
/// ```
/// ┌──────────────────────────────────────┐
/// │                 ───                  │ <- grabber
/// │ ( < Browser )             (Aa) (^)  │ <- `SheetTopBar`: the close pill names what is
/// │ `banner` (the ^ hint, while on)      │   underneath; `textAppearance` (Aa), `accessory` (^)
/// │ ... `text`: ReadingHeading, then the │ <- fills the sheet, running under the header and
/// │   text in the reading theme ...      │   the band
/// │ ─────────────────────────────────────│ <- hairline divider
/// │ [art] Title          (Voice)    [🔖]│ <- title; Voice then bookmark (trailing)
/// │       source                        │
/// │ [━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━] │ <- thin scrub
/// │ [⋯]  [⏮]    (▶)    [⏭]       [1×] │ <- transport row
/// └──────────────────────────────────────┘
/// ```
///
/// Now Playing (`NowPlayingSheet`) has the same top bar, the same colours (`palette`, the reading
/// theme) and the same flat integrated controls, so the controls stay put as Listen turns one into
/// the other. Both go full screen the same way (`ReadingChrome`): scrolling down hides the header
/// and the band, and the floating ▶ plays this page as Listen does. The close pill, the grabber and
/// a pull down all close it (`onClose`, after it has gone). `floating` floats just above the bottom
/// band's hairline (a toast).
struct ReaderSheet<Band: View, Reading: View, TextAppearance: View, Accessory: View,
                   Banner: View, Floating: View>: View {
    /// What is underneath: "Browser", "Library".
    let backTitle: String
    let listenState: PlayState
    let onClose: () -> Void
    let onListen: () -> Void
    /// The reading theme's colours.
    var palette: ReadingPalette = .app
    /// Aa (`TextAppearanceButton` and its panel), just before `accessory`.
    @ViewBuilder var textAppearance: TextAppearance
    /// The control at the trailing end of the top bar (☝︎, `JumpModeButton`).
    @ViewBuilder var accessory: Accessory
    /// Under the top bar, in the header (the ☝︎ hint, `JumpHint`): the text's top inset grows
    /// with it, so it never covers the first line.
    @ViewBuilder var banner: Banner
    @ViewBuilder var text: Reading
    /// The integrated bottom band: title, scrub, transport, all flat on the page background.
    @ViewBuilder var band: Band
    @ViewBuilder var floating: Floating

    @State private var chrome = ReadingChrome()

    var body: some View {
        Sheet(onDismiss: onClose, palette: palette, chrome: chrome) {
            VStack(spacing: 0) {
                SheetTopBar { SheetClosePill(kind: .back(backTitle)) } trailing: {
                    textAppearance
                    accessory
                }
                banner
            }
        } content: {
            text
        } band: {
            ReadingBottomBand {
                band
            } floating: {
                floating
            }
        } overText: {
            FloatingPlayButton(state: listenState, action: onListen)
        }
    }
}

extension ReaderSheet where TextAppearance == EmptyView, Accessory == EmptyView, Banner == EmptyView,
    Floating == EmptyView {
    init(backTitle: String, listenState: PlayState,
         onClose: @escaping () -> Void, onListen: @escaping () -> Void,
         @ViewBuilder text: () -> Reading, @ViewBuilder band: () -> Band) {
        self.init(backTitle: backTitle, listenState: listenState,
                  onClose: onClose, onListen: onListen,
                  textAppearance: { EmptyView() }, accessory: { EmptyView() }, banner: { EmptyView() }, text: text,
                  band: band, floating: { EmptyView() })
    }
}

/// The top of a page in the Reader and Now Playing: its title (none for a page without one) over
/// its source and length.
struct ReadingHeading: View {
    let title: String?
    /// ["example.org", "9 min"], spaced apart (`DetailLine`).
    let detail: [String]

    @Environment(\.readingPalette) private var reading

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if let title {
                Text(title)
                    .typeStyle(.title)
                    .foregroundStyle(reading?.ink ?? Palette.ink)
                    .accessibilityAddTraits(.isHeader)
            }
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
            PreviewState("not started") { frame(.idle) }
            PreviewState("part-way, saved") { frame(.idle, saved: true) }
        }
    }

    private func frame(_ state: PlayState, saved: Bool = false) -> some View {
        ReaderSheet(backTitle: "Browser", listenState: state,
                    onClose: {}, onListen: {}) {
            SampleReading(title: "Notes on Tides", detail: ["example.org", "9 min"])
        } band: {
            VStack(spacing: Spacing.xs) {
                HStack(spacing: Spacing.s) {
                    ArtworkTile(letter: "N", size: PlayerCard.artworkSize)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Notes on Tides").typeStyle(.row, weight: .semibold).lineLimit(1)
                        Text("example.org").typeStyle(.caption).foregroundStyle(Palette.secondaryInk).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    SaveToggleButton(isSaved: saved, identifier: "preview", onToggle: {})
                        .frame(width: BottomChrome.minTapTarget)
                        // Hug the trailing content edge (scrubber end) while keeping the 44 pt hit area.
                        .padding(.trailing, -(BottomChrome.minTapTarget - BottomChrome.iconSize) / 2)
                }
                ScrubTrack(value: 0).frame(height: 20)
                NowPlayingTransport(state: state, canSkipBack: false, canSkipForward: false,
                                    onSkipBack: {}, onSkipForward: {}, onPlayPause: {}) {
                    Text("1x").typeStyle(.caption).foregroundStyle(Palette.ink).fieldTextFrame()
                } more: {
                    Image(systemName: Icons.more).toolbarIconFrame()
                }
            }
        }
        .frame(height: 640)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
    }
}

#Preview("ReaderSheet · light", traits: .sizeThatFitsLayout) { ReaderSheetGallery().previewVariant(.light) }
#Preview("ReaderSheet · dark", traits: .sizeThatFitsLayout) { ReaderSheetGallery().previewVariant(.dark) }
#Preview("ReaderSheet · AX5", traits: .sizeThatFitsLayout) { ReaderSheetGallery().previewVariant(.largestText) }
#endif
