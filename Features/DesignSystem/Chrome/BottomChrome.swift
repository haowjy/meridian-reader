import SwiftUI

/// The one bottom-chrome design, shared by the browser, the library and the reader
/// (docs/NAVIGATION.md). The browser and the Library draw the same three-row band, so swapping
/// between them changes no pixel of its frame:
///
/// ```
/// ┌ .bar band ────────────────────────────────────┐
/// │ ╭ Now Playing bar (or placeholder) ─────────╮ │  ← the full row; ⏸ over ⋯'s slot
/// │ ╰───────────────────────────────────────────╯ │
/// │ [⇄] ( field capsule: address / Library search ) │  ← the swap, then `bottomChromeField()`
/// │  [‹]   [›]   [＋/🔖]  [🕘]   [⋯]              │  ← `BottomToolbarLayout`, explicit slots,
/// └───────────────────────────────── home indicator ┘    ⋯ always slot 5
/// ```
///
/// The Reader and Now Playing share one band (`ReadingBottomBand`): integrated controls
/// (title, scrub, transport) flat on the page background, separated by a hairline divider.
enum BottomChrome {
    /// Horizontal margin of the band's content.
    static let horizontalMargin = Spacing.bandMargin
    /// Space above the first row inside the band.
    static let topPadding = Spacing.xs
    /// Space between the field capsule and the toolbar row.
    static let rowSpacing = Spacing.xxs
    /// Vertical padding inside the field capsule.
    static let fieldVerticalPadding = Spacing.xxs
    /// Field capsule / toolbar row height.
    static let rowHeight: CGFloat = 44
    /// The field capsule's fill: `chrome`, or the reading page's card.
    static func fieldFill(_ reading: ReadingPalette?) -> Color { reading?.card ?? Palette.chrome }
    /// Toolbar glyph size.
    static let iconSize: CGFloat = 19
    /// Text standing in for a field control (the speed). Like the glyphs it keeps its size at
    /// large text sizes, so the controls never crowd.
    static let toolbarTextSize: CGFloat = 17
    /// Small controls inside the field capsule (mic, the speed) and in a sheet's top bar (☝︎).
    static let fieldControlSize: CGFloat = 36
    /// The smallest tap area of a control (`tapTarget`), whatever it looks like.
    static let minTapTarget: CGFloat = 44
    /// Now Playing's round play / pause in the transport's centre slot. Fixed like the toolbar
    /// glyphs (the large content viewer shows it at large text sizes). The row stays
    /// `rowHeight`; the disc reaches past it above and below by half the difference.
    static let transportDiscSize: CGFloat = 52
    /// The glyph inside the transport disc.
    static let transportDiscGlyph: CGFloat = 21
    /// A folder header's play / pause between Prepare and More (C124): smaller than the
    /// transport's, its glyph in the same proportion.
    static let headerDiscSize: CGFloat = 56
    /// The glyph inside the header disc.
    static let headerDiscGlyph: CGFloat = (transportDiscGlyph * headerDiscSize / transportDiscSize).rounded()
    /// The play / pause disc floating over a reading sheet in full screen: one tap target wide.
    static let floatingDiscSize: CGFloat = minTapTarget
    /// The glyph inside the floating disc.
    static let floatingDiscGlyph: CGFloat = 18
    /// How far the field capsule and its controls grow with Dynamic Type, as a multiple of their
    /// default size: enough that text and glyphs never clip, while the chrome stays a band.
    static let maxTextGrowth: CGFloat = 1.5

    /// A Dynamic Type–scaled size (`@ScaledMetric` of `base`), kept between `base` and
    /// `maxTextGrowth` times it.
    static func grown(_ scaled: CGFloat, from base: CGFloat) -> CGFloat {
        min(max(scaled, base), base * maxTextGrowth)
    }
}

extension View {
    /// The bottom band: content inset by the standard margins on the system bar material (on the
    /// reading page, tinted with its background), which runs down through the home indicator. `bottomInset` = extra
    /// bottom padding when the caller is laid out edge to edge (the reader); 0 when it already
    /// sits in the safe area (Browse).
    func bottomChromeBand(bottomInset: CGFloat = 0, bottomPadding: CGFloat = 0) -> some View {
        self.padding(.horizontal, BottomChrome.horizontalMargin)
            .padding(.top, BottomChrome.topPadding)
            .padding(.bottom, bottomPadding + bottomInset)
            .modifier(BottomChromeBandBackground())
    }

    /// The field capsule: the browser's address field, the reader's scrub row and title row.
    /// 44 pt, growing with Dynamic Type (up to `maxTextGrowth`) so its text never clips.
    func bottomChromeField(leading: CGFloat = Spacing.s, trailing: CGFloat = Spacing.xxs) -> some View {
        modifier(BottomChromeField(leading: leading, trailing: trailing))
    }

    /// Toolbar icon: its cell of the toolbar row, 44 pt tall, full-cell tap target. The glyph
    /// keeps its size at large text sizes (like the system's toolbars); a long press shows it in
    /// the large content viewer instead.
    func toolbarIconFrame() -> some View {
        self.font(.system(size: BottomChrome.iconSize))
            .frame(maxWidth: .infinity, minHeight: BottomChrome.rowHeight)
            .contentShape(Rectangle())
            .accessibilityShowsLargeContentViewer()
    }

    /// A small control inside the field capsule (mic, Jump, bookmark): 36 pt with a body-size
    /// glyph, growing with Dynamic Type like the capsule; taps land anywhere in 44 pt.
    func fieldControlFrame() -> some View {
        modifier(FieldControlFrame())
    }

    /// A field control on a round fill of its own, standing apart from a field: ☝︎ in a sheet's
    /// top bar, ✕ beside the search field.
    func roundFieldControl(fill: Color) -> some View {
        fieldControlFrame().background(Circle().fill(fill))
    }

    /// Text standing in for a field control (the speed in Now Playing's scrub capsule): as tall
    /// as one and at least as wide, wider for a longer label ("1.75×"), at the toolbar text's
    /// fixed size with even-width digits.
    func fieldTextFrame() -> some View {
        modifier(FieldTextFrame())
    }

    /// Grows the tap area of a control drawn `size` points wide to `BottomChrome.minTapTarget`
    /// without moving it or changing its look.
    func tapTarget(_ size: CGFloat) -> some View {
        contentShape(Rectangle().inset(by: -max(0, (BottomChrome.minTapTarget - size) / 2)))
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

/// Fixed height (not minHeight): a Capsule with unbounded height becomes a circle when the layout
/// proposes a large vertical size (e.g. the idle address bar without the mic's frame).
private struct BottomChromeField: ViewModifier {
    let leading: CGFloat
    let trailing: CGFloat
    @ScaledMetric(relativeTo: .body) private var height = BottomChrome.rowHeight
    @Environment(\.readingPalette) private var reading

    func body(content: Content) -> some View {
        content
            .padding(.leading, leading)
            .padding(.trailing, trailing)
            .padding(.vertical, BottomChrome.fieldVerticalPadding)
            .frame(height: BottomChrome.grown(height, from: BottomChrome.rowHeight))
            .background(BottomChrome.fieldFill(reading), in: Capsule())
    }
}

private struct FieldControlFrame: ViewModifier {
    @ScaledMetric(relativeTo: .body) private var size = BottomChrome.fieldControlSize

    func body(content: Content) -> some View {
        let side = BottomChrome.grown(size, from: BottomChrome.fieldControlSize)
        content
            .font(.body)
            .frame(width: side, height: side)
            .tapTarget(side)
    }
}

private struct FieldTextFrame: ViewModifier {
    @ScaledMetric(relativeTo: .body) private var size = BottomChrome.fieldControlSize

    func body(content: Content) -> some View {
        let side = BottomChrome.grown(size, from: BottomChrome.fieldControlSize)
        content
            .font(.system(size: BottomChrome.toolbarTextSize, weight: .medium).monospacedDigit())
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, Spacing.xxs)
            .frame(minWidth: side, minHeight: side, maxHeight: side)
            .contentShape(Rectangle())
            .tapTarget(side)
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

/// A toolbar row with one wide control: the first item in slot 1, the last in slot 5 (⋯, so the
/// morph menu grows from the same spot as everywhere else), and the middle one across slots 2–4
/// with `Spacing.xs` either side. The end items keep the toolbar row's height at its bottom, so
/// they sit exactly where slot 1 and ⋯ sit in `BottomToolbarLayout` while the wide control may
/// be taller (a 48 pt pill).
///
/// ```
/// Reader   [🔖]  [ ▶  Listen  9 min  ]  [⋯]
/// ```
struct BottomToolbarSpanLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: proposal.width ?? 320, height: max(BottomChrome.rowHeight, height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let slot = BottomToolbarLayout.slotWidth(rowWidth: bounds.width)
        let edge = ProposedViewSize(width: slot, height: BottomChrome.rowHeight)
        let edgeY = bounds.maxY - BottomChrome.rowHeight / 2
        subviews[0].place(at: CGPoint(x: bounds.minX + BottomToolbarLayout.slotCenterX(0, rowWidth: bounds.width),
                                      y: edgeY), anchor: .center, proposal: edge)
        subviews[1].place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center,
                          proposal: ProposedViewSize(width: slot * 3 - Spacing.xs * 2, height: bounds.height))
        subviews[2].place(at: CGPoint(x: bounds.minX + BottomToolbarLayout.slotCenterX(4, rowWidth: bounds.width),
                                      y: edgeY), anchor: .center, proposal: edge)
    }
}

#if DEBUG
/// The bottom band on each surface: the browser's and the Library's three rows, slot for slot,
/// and the Reader's spanning row.
struct BottomToolbarGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("browser") {
                band {
                    barRow(playing)
                    fieldRow(Icons.library) {
                        AddressField(reader: .available, listen: .idle) { Text("news.example.org") }
                    }
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
                    fieldRow(Icons.browser) { SearchField(text: .constant("")) }
                    BottomToolbarLayout {
                        icon(Icons.back).disabled(true).toolbarSlot(0)
                        icon(Icons.forward).disabled(true).toolbarSlot(1)
                        icon(Icons.add).toolbarSlot(2)
                        icon(Icons.history).toolbarSlot(3)
                        icon(Icons.more).toolbarSlot(BottomToolbarLayout.moreSlot)
                    }
                }
            }
            PreviewState("reader") {
                band {
                    BottomToolbarSpanLayout {
                        icon(Icons.save)
                        PlayStateButton(state: .idle, look: .pill(title: "Listen", detail: "9 min", expands: true)) {}
                        icon(Icons.more)
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

    /// The swap, a toolbar button tight to the leading edge, then the field.
    private func fieldRow<Field: View>(_ swap: String, @ViewBuilder field: () -> Field) -> some View {
        BandFieldRow(swap: BandSwap(systemImage: swap, label: "Swap", hint: "", identifier: "preview", action: {}),
                     field: field)
    }

    private func band<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: BottomChrome.rowSpacing) { content() }
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
