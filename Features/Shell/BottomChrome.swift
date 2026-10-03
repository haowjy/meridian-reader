import SwiftUI

/// The one bottom-chrome design, shared by the browser, the library and the reader
/// (docs/NAVIGATION.md), so switching surfaces barely changes the bottom of the screen:
///
/// ```
/// ┌ .bar band ────────────────────────────────────┐
/// │ ( field capsule: address field / scrub row  ) │  ← `bottomChromeField()`
/// │  [‹]   [›]   [Search]  [Lib]  [⋯]            │  ← `BottomToolbarLayout` + `toolbarIconFrame()`
/// │  [1×]  [⏮]   [▶︎]      [⏭]    [⋯]            │    (5 equal slots, ⋯ always in slot 5;
/// │  [ ]   [ ]   [Search]  [🌐]   [⋯]            │     Library surface: slot 4 = Browser)
/// └───────────────────────────────── home indicator ┘
/// ```
enum BottomChrome {
    /// Horizontal margin of the band's content.
    static let horizontalMargin: CGFloat = 12
    /// Space above the first row inside the band.
    static let topPadding: CGFloat = 8
    /// Space between the field capsule and the toolbar row.
    static let rowSpacing: CGFloat = 4
    /// Field capsule / toolbar row height.
    static let rowHeight: CGFloat = 44
    /// Toolbar glyph size.
    static let iconSize: CGFloat = 19
    /// Small controls inside the field capsule (mic, Jump, bookmark).
    static let fieldControlSize: CGFloat = 36
    /// The smallest tap area of a control (`tapTarget`), whatever it looks like.
    static let minTapTarget: CGFloat = 44
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
    /// The bottom band: content inset by the standard margins on the system bar material, which
    /// runs down through the home indicator. `bottomInset` = extra bottom padding when the caller
    /// is laid out edge to edge (the reader); 0 when it already sits in the safe area (Browse).
    func bottomChromeBand(bottomInset: CGFloat = 0, bottomPadding: CGFloat = 0) -> some View {
        self.padding(.horizontal, BottomChrome.horizontalMargin)
            .padding(.top, BottomChrome.topPadding)
            .padding(.bottom, bottomPadding + bottomInset)
            .background(.bar)
    }

    /// The field capsule: the browser's address field, the reader's scrub row and title row.
    /// 44 pt, growing with Dynamic Type (up to `maxTextGrowth`) so its text never clips.
    func bottomChromeField(leading: CGFloat = 12, trailing: CGFloat = 4) -> some View {
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

    /// Grows the tap area of a control drawn `size` points wide to `BottomChrome.minTapTarget`
    /// without moving it or changing its look.
    func tapTarget(_ size: CGFloat) -> some View {
        contentShape(Rectangle().inset(by: -max(0, (BottomChrome.minTapTarget - size) / 2)))
    }
}

/// Fixed height (not minHeight): a Capsule with unbounded height becomes a circle when the layout
/// proposes a large vertical size (e.g. the idle address bar without the mic's frame).
private struct BottomChromeField: ViewModifier {
    let leading: CGFloat
    let trailing: CGFloat
    @ScaledMetric(relativeTo: .body) private var height = BottomChrome.rowHeight

    func body(content: Content) -> some View {
        content
            .padding(.leading, leading)
            .padding(.trailing, trailing)
            .padding(.vertical, 4)
            .frame(height: BottomChrome.grown(height, from: BottomChrome.rowHeight))
            .background(Color(.secondarySystemBackground), in: Capsule())
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

/// Toolbar row layout: five equal slots, evenly spaced, one grid for every bottom toolbar,
/// so each icon sits at the same x on every screen:
///
/// ```
/// Browse   [‹]  [›]  [Search]  [Library]  [⋯]
/// Library  [ ]  [ ]  [Search]  [Browser]  [⋯]
/// Reader   [1×] [⏮]  [▶︎]      [⏭]       [⋯]
/// ```
///
/// Leading items fill slots 1, 2, 3…; the last item (⋯) always sits in slot 5, so the morph menu
/// grows from the same spot everywhere (the panel follows the measured ⋯ frame).
struct BottomToolbarLayout: Layout {
    static let slotCount = 5

    /// Width of one slot in a row `rowWidth` wide.
    static func slotWidth(rowWidth: CGFloat) -> CGFloat { rowWidth / CGFloat(slotCount) }

    /// Center x of slot `index` (0-based) from the row's leading edge.
    static func slotCenterX(_ index: Int, rowWidth: CGFloat) -> CGFloat {
        slotWidth(rowWidth: rowWidth) * (CGFloat(index) + 0.5)
    }

    /// Slot for subview `index` of `count`: leading items in order, the last one in slot 5.
    static func slot(forSubview index: Int, count: Int) -> Int {
        index == count - 1 ? slotCount - 1 : min(index, slotCount - 2)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: proposal.width ?? 320, height: max(BottomChrome.rowHeight, height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let slot = Self.slotWidth(rowWidth: bounds.width)
        for (i, view) in subviews.enumerated() {
            let s = Self.slot(forSubview: i, count: subviews.count)
            view.place(at: CGPoint(x: bounds.minX + Self.slotCenterX(s, rowWidth: bounds.width), y: bounds.midY),
                       anchor: .center, proposal: ProposedViewSize(width: slot, height: bounds.height))
        }
    }
}
