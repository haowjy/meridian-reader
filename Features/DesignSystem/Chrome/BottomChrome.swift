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
    static let horizontalMargin = Spacing.bandMargin
    /// Space above the first row inside the band.
    static let topPadding = Spacing.xs
    /// Space between the field capsule and the toolbar row.
    static let rowSpacing = Spacing.xxs
    /// Vertical padding inside the field capsule.
    static let fieldVerticalPadding = Spacing.xxs
    /// Field capsule / toolbar row height.
    static let rowHeight: CGFloat = 44
    /// Toolbar glyph size.
    static let iconSize: CGFloat = 19
    /// Text standing in for a glyph in a toolbar slot (the speed label). Like the glyphs it keeps
    /// its size at large text sizes, so the five slots never crowd.
    static let toolbarTextSize: CGFloat = 17
    /// Small controls inside the field capsule (mic, Jump, bookmark).
    static let fieldControlSize: CGFloat = 36
    /// The smallest tap area of a control (`tapTarget`), whatever it looks like.
    static let minTapTarget: CGFloat = 44
    /// Now Playing's round play / pause in the transport's centre slot. Fixed like the toolbar
    /// glyphs (the large content viewer shows it at large text sizes). The row stays
    /// `rowHeight`; the disc reaches past it above and below by half the difference.
    static let transportDiscSize: CGFloat = 64
    /// The glyph inside the transport disc.
    static let transportDiscGlyph: CGFloat = 26
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
    /// player, `playerChrome`), which runs down through the home indicator. `bottomInset` = extra
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

    /// Toolbar text (the speed label): its cell of the toolbar row, 44 pt tall, full-cell tap
    /// target, at the fixed `toolbarTextSize` with even-width digits.
    func toolbarTextFrame() -> some View {
        self.font(.system(size: BottomChrome.toolbarTextSize, weight: .medium).monospacedDigit())
            .frame(maxWidth: .infinity, minHeight: BottomChrome.rowHeight)
            .contentShape(Rectangle())
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

private struct BottomChromeBandBackground: ViewModifier {
    @Environment(\.onPlayerPalette) private var onPlayer

    func body(content: Content) -> some View {
        if onPlayer {
            content.background(Palette.playerChrome)
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
    @Environment(\.onPlayerPalette) private var onPlayer

    func body(content: Content) -> some View {
        content
            .padding(.leading, leading)
            .padding(.trailing, trailing)
            .padding(.vertical, BottomChrome.fieldVerticalPadding)
            .frame(height: BottomChrome.grown(height, from: BottomChrome.rowHeight))
            .background(onPlayer ? Palette.playerCard : Palette.chrome, in: Capsule())
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

/// A toolbar row with one wide control: the first item in slot 1, the last in slot 5 (⋯, so the
/// morph menu grows from the same spot as everywhere else), and the middle one across slots 2–4
/// with `Spacing.xs` either side. The end items keep the toolbar row's height at its bottom, so
/// they sit exactly where slot 1 and ⋯ sit in `BottomToolbarLayout` while the wide control may
/// be taller (a 48 pt pill).
///
/// ```
/// Reader   [🔖]  [ ▶  Listen · 9 min  ]  [⋯]
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
/// The bottom band on each surface: field capsule over the five-slot toolbar, and the Reader's
/// spanning row.
struct BottomToolbarGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("browser") {
                band {
                    AddressField(reader: .available, listen: .idle) { Text("news.example.org") }
                    BottomToolbarLayout {
                        icon("chevron.backward"); icon("chevron.forward"); icon("magnifyingglass")
                        icon("books.vertical"); icon("ellipsis")
                    }
                }
            }
            PreviewState("library") {
                band {
                    SearchField(text: .constant(""))
                    BottomToolbarLayout {
                        icon("plus"); Color.clear.frame(height: BottomChrome.rowHeight); icon("magnifyingglass")
                        icon("globe"); icon("ellipsis")
                    }
                }
            }
            PreviewState("reader") {
                band {
                    BottomToolbarSpanLayout {
                        icon("bookmark")
                        PlayStateButton(state: .idle, look: .pill(title: "Listen · 9 min", expands: true)) {}
                        icon("ellipsis")
                    }
                }
            }
            PreviewState("disabled slot") {
                band {
                    BottomToolbarLayout {
                        icon("chevron.backward").disabled(true); icon("ellipsis")
                    }
                }
            }
        }
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
