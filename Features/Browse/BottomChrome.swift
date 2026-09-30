import SwiftUI

/// The one bottom-chrome design, shared by the browser and the reader (Nav G, docs/NAVIGATION.md),
/// so switching Browse ↔ Reader barely changes the bottom of the screen:
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
    func bottomChromeField(leading: CGFloat = 12, trailing: CGFloat = 4) -> some View {
        self.padding(.leading, leading)
            .padding(.trailing, trailing)
            .padding(.vertical, 4)
            .frame(minHeight: BottomChrome.rowHeight)
            .background(Color(.secondarySystemBackground), in: Capsule())
    }

    /// Toolbar icon: its cell of the toolbar row, 44 pt tall, full-cell tap target.
    func toolbarIconFrame() -> some View {
        self.font(.system(size: BottomChrome.iconSize))
            .frame(maxWidth: .infinity, minHeight: BottomChrome.rowHeight)
            .contentShape(Rectangle())
    }

    /// A small control inside the field capsule (mic, Jump, bookmark): 36 pt, body-size glyph.
    func fieldControlFrame() -> some View {
        self.font(.body)
            .frame(width: BottomChrome.fieldControlSize, height: BottomChrome.fieldControlSize)
            .contentShape(Rectangle())
    }
}

/// Toolbar row layout (Nav I): five equal slots, evenly spaced, one grid for every bottom toolbar,
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
