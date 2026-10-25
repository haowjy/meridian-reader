import SwiftUI

/// The regular-width bottom band (docs/NAVIGATION.md), over the clustered dock: a field capsule over
/// a toolbar of five slots made of the helpers in `BottomChrome`:
///
/// ```
/// [ field capsule: address / Library search ]    ← `bottomChromeField()`
///  [‹]   [›]   [＋/🔖]  [🕘]   [⋯]                ← `BottomToolbarLayout`, explicit slots,
///                                                   ⋯ always slot 5
/// ```
///
/// The Reader and Now Playing share one band (`ReadingBottomBand`): integrated controls
/// (title, scrub, transport) flat on the page background, separated by a hairline divider.
enum RegularBand {
    /// Horizontal margin of the band's content.
    static let horizontalMargin = Spacing.bandMargin
    /// Space above the first row inside the band.
    static let topPadding = Spacing.xs
}

extension View {
    /// The bottom band: content inset by the standard margins on the system bar material (on the
    /// reading page, tinted with its background), which runs down through the home indicator.
    func bottomChromeBand(bottomPadding: CGFloat = 0) -> some View {
        self.padding(.horizontal, RegularBand.horizontalMargin)
            .padding(.top, RegularBand.topPadding)
            .padding(.bottom, bottomPadding)
            .modifier(BottomChromeBandBackground())
    }
}

private struct BottomChromeBandBackground: ViewModifier {
    @Environment(\.readingPalette) private var reading

    func body(content: Content) -> some View {
        if let reading, reading.theme != .matchApp {
            // The bar material, tinted with the reading theme's page so the band reads as part of it.
            content.background {
                ZStack {
                    Rectangle().fill(.bar)
                    reading.background.opacity(0.85)
                }
                .ignoresSafeArea(edges: .bottom)
            }
        } else {
            content.background(.bar)
        }
    }
}

/// Toolbar row layout: five equal slots, evenly spaced, one grid for every bottom toolbar,
/// so each icon sits at the same x on every screen:
///
/// ```
/// Browse   [‹]  [›]  [🔖]  [🕘]  [⋯]
/// Library  [‹]  [›]  [＋]  [🕘]  [⋯]
/// Now Playing [🔖] [⏮] (⏸) [⏭] [⋯]
/// ```
///
/// Each item sits in the slot it names with `.toolbarSlot(_:)`; an item without one sits at its
/// position in the row. A slot nothing names stays empty, so a row with fewer items never slides
/// them along, and ⋯ (`.toolbarSlot(BottomToolbarLayout.moreSlot)`) grows the morph menu from the
/// same spot everywhere.
struct BottomToolbarLayout: Layout {
    static let slotCount = 5
    /// ⋯'s slot, the last.
    static let moreSlot = slotCount - 1

    /// Width of one slot in a row `rowWidth` wide.
    static func slotWidth(rowWidth: CGFloat) -> CGFloat { rowWidth / CGFloat(slotCount) }

    /// Center x of slot `index` (0-based) from the row's leading edge.
    static func slotCenterX(_ index: Int, rowWidth: CGFloat) -> CGFloat {
        slotWidth(rowWidth: rowWidth) * (CGFloat(index) + 0.5)
    }

    /// The slot of subview `index`: the one it names, else its position; within the row.
    static func slot(named: Int?, forSubview index: Int) -> Int {
        min(max(named ?? index, 0), slotCount - 1)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: proposal.width ?? 320, height: max(BottomChrome.rowHeight, height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let slot = Self.slotWidth(rowWidth: bounds.width)
        for (i, view) in subviews.enumerated() {
            let s = Self.slot(named: view[ToolbarSlotKey.self], forSubview: i)
            view.place(at: CGPoint(x: bounds.minX + Self.slotCenterX(s, rowWidth: bounds.width), y: bounds.midY),
                       anchor: .center, proposal: ProposedViewSize(width: slot, height: bounds.height))
        }
    }
}

private struct ToolbarSlotKey: LayoutValueKey {
    static let defaultValue: Int? = nil
}

extension View {
    /// The slot (0-based) this item takes in a `BottomToolbarLayout` row.
    func toolbarSlot(_ index: Int) -> some View {
        layoutValue(key: ToolbarSlotKey.self, value: index)
    }
}

/// The bottom band shared by the Reader and Now Playing: integrated controls on the page
/// background, separated from the text by a hairline divider. No card, no shadow: the controls
/// sit directly on the reading surface.
struct ReadingBottomBand<Content: View, Floating: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var floating: Floating

    @Environment(\.readingPalette) private var reading

    var body: some View {
        content
            .readerScrubBubble()
            .bottomChromeBand(bottomPadding: Spacing.xs)
            .overlay(alignment: .top) {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(reading?.hairline ?? Palette.hairline)
                        .frame(height: 1 / UIScreen.main.scale)
                    floating
                }
            }
    }
}

#if DEBUG
/// The regular-width bottom band on each surface: the browser's and the Library's three rows, slot for slot.
struct BottomToolbarGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("browser") {
                band {
                    barRow(playing)
                    AddressField(reader: .available, listen: .idle) { Text("news.example.org") }
                    BottomToolbarLayout {
                        icon(Icons.back).toolbarSlot(0)
                        icon(Icons.forward).disabled(true).toolbarSlot(1)
                        SaveToggleButton(isSaved: false, identifier: "preview", onToggle: {}).toolbarSlot(2)
                        icon(Icons.history).toolbarSlot(3)
                        icon(Icons.more).toolbarSlot(BottomToolbarLayout.moreSlot)
                    }
                }
            }
            PreviewState("library, nothing played") {
                band {
                    barRow(NowPlayingBar.placeholder())
                    SearchField(text: .constant(""))
                    BottomToolbarLayout {
                        icon(Icons.back).disabled(true).toolbarSlot(0)
                        icon(Icons.forward).disabled(true).toolbarSlot(1)
                        icon(Icons.add).toolbarSlot(2)
                        icon(Icons.history).toolbarSlot(3)
                        icon(Icons.more).toolbarSlot(BottomToolbarLayout.moreSlot)
                    }
                }
            }
            PreviewState("named slots, gaps kept") {
                band {
                    BottomToolbarLayout {
                        icon(Icons.back).disabled(true).toolbarSlot(0)
                        icon(Icons.more).toolbarSlot(BottomToolbarLayout.moreSlot)
                    }
                }
            }
        }
    }

    private var playing: NowPlayingBar {
        NowPlayingBar(title: "Notes on Tides", detail: ["example.com", "6 min left"], progress: 0.4, state: .paused,
                      onOpen: {}, onPlayPause: {}, menu: nil)
    }

    private func barRow(_ bar: NowPlayingBar) -> some View {
        bar.padding(.bottom, Spacing.xxs)
    }

    private func band<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: Spacing.xxs) { content() }
            .bottomChromeBand(bottomPadding: Spacing.xs)
            .tint(Palette.ink)
    }

    private func icon(_ name: String) -> some View {
        Button {} label: { Image(systemName: name).toolbarIconFrame() }
    }
}

#Preview("BottomToolbar · light", traits: .sizeThatFitsLayout) { BottomToolbarGallery().previewVariant(.light) }
#Preview("BottomToolbar · dark", traits: .sizeThatFitsLayout) { BottomToolbarGallery().previewVariant(.dark) }
#Preview("BottomToolbar · AX5", traits: .sizeThatFitsLayout) { BottomToolbarGallery().previewVariant(.largestText) }
#endif
