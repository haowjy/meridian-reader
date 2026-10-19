import SwiftUI

/// Aa: opens the text appearance panel. A round field control (36 pt, 44 pt to tap) in both
/// sheets' top bars, just left of ☝︎, on the card fill, the highlight while its panel is open.
struct TextAppearanceButton: View {
    let isOpen: Bool
    let action: () -> Void

    @Environment(\.readingPalette) private var reading

    var body: some View {
        Button(action: action) {
            Image(systemName: Icons.textAppearance)
                .foregroundStyle(isOpen ? reading?.accent ?? Palette.accent : reading?.ink ?? Palette.ink)
                .roundFieldControl(fill: isOpen ? reading?.highlight ?? Palette.playingTint : BottomChrome.fieldFill(reading))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("textAppearanceButton")
        .accessibilityLabel("Text Appearance")
    }
}

/// How the page reads, changed live under it: the reading theme, the typeface, the text size, the
/// line spacing and Scroll or Pages. Shown by Aa on the Reader and Now Playing; Settings › Reading
/// holds the same controls (`ReadingThemePicker`, `ChoicePicker`, `TextSizeStepper`), bound to the
/// same store.
///
/// ```
/// (◐)  (Aa)  (Aa)  (Aa)  (Aa)       themes: Match App, Light, Sepia, Dark, Black
/// [ Serif | Sans Serif | Rounded ]
/// [ A ]        100%        [ A ]
/// [ Compact | Normal | Relaxed ]
/// [ Scroll | Pages ]
/// ```
struct TextAppearancePanel: View {
    @Binding var theme: ReadingTheme
    @Binding var font: ReadingFont
    @Binding var lineSpacing: ReadingLineSpacing
    @Binding var layout: ReadingLayout
    let textSize: TextSizeStepper.Model
    /// The app's colour, for the swatches that take it.
    let accent: AccentTheme

    @Environment(\.readingPalette) private var reading

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            ReadingThemePicker(selection: $theme, accent: accent)
            ChoicePicker(options: ReadingFont.allCases, selection: $font, identifier: "readingFont") { option in
                Text(option.title).typeStyle(.row, weight: .medium, design: option.design)
            }
            TextSizeStepper(model: textSize)
            ChoicePicker(options: ReadingLineSpacing.allCases, selection: $lineSpacing,
                         identifier: "readingLineSpacing") { option in
                Text(option.title).typeStyle(.row)
            }
            ChoicePicker(options: ReadingLayout.allCases, selection: $layout, identifier: "readingLayout") { option in
                Text(option.title).typeStyle(.row)
            }
        }
        .padding(Spacing.m)
        .frame(width: Panel.width)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("textAppearancePanel")
    }
}

/// The reading themes as swatches: each its page colour with "Aa" in its ink. *Match App* is
/// split, the app's light and dark paper.
struct ReadingThemePicker: View {
    @Binding var selection: ReadingTheme
    let accent: AccentTheme

    var body: some View {
        SwatchPicker(options: ReadingTheme.allCases, selection: $selection, identifier: "readingTheme",
                     title: \.title) { theme, side in
            let palette = theme.palette(accent: accent)
            let label = Text("Aa").font(.system(size: side * 0.36, weight: .semibold, design: .serif))
            if theme == .matchApp {
                // The app's light paper and ink on the left half, its dark ones on the right.
                ZStack {
                    ZStack { Circle().fill(Palette.paper.resolved(.light)); label.foregroundStyle(Palette.ink.resolved(.light)) }
                    ZStack { Circle().fill(Palette.paper.resolved(.dark)); label.foregroundStyle(Palette.ink.resolved(.dark)) }
                        .mask(Rectangle().frame(width: side / 2).offset(x: side / 4))
                }
            } else {
                ZStack { Circle().fill(palette.background); label.foregroundStyle(palette.ink) }
            }
        }
    }
}

/// The app's colours as swatches, each a disc of its accent.
struct AccentThemePicker: View {
    @Binding var selection: AccentTheme

    var body: some View {
        SwatchPicker(options: AccentTheme.allCases, selection: $selection, identifier: "appAccent",
                     title: \.title) { theme, _ in
            Circle().fill(theme.accent)
        }
    }
}

/// A row of round swatches with their names under them; the chosen one ringed in the accent and
/// named in ink. Names never wrap; they shrink a little.
struct SwatchPicker<Option: Identifiable & Hashable, Face: View>: View {
    let options: [Option]
    @Binding var selection: Option
    /// Accessibility identifiers are `<identifier>-<option id>`.
    let identifier: String
    let title: (Option) -> String
    /// The swatch for an option, `side` points across.
    @ViewBuilder let face: (Option, CGFloat) -> Face

    @Environment(\.readingPalette) private var reading
    @ScaledMetric(relativeTo: .caption) private var swatch: CGFloat = 44

    var body: some View {
        let side = min(swatch, 56)
        HStack(alignment: .top, spacing: 0) {
            ForEach(options) { option in
                let chosen = option == selection
                Button { selection = option } label: {
                    VStack(spacing: Spacing.xxs) {
                        face(option, side)
                            .frame(width: side, height: side)
                            .overlay(Circle().strokeBorder(reading?.hairline ?? Palette.hairline, lineWidth: 1))
                            .padding(Spacing.xxs)
                            .overlay {
                                if chosen { Circle().strokeBorder(reading?.accent ?? Palette.accent, lineWidth: Glyph.stroke) }
                            }
                        Text(title(option))
                            .typeStyle(.caption, weight: chosen ? .semibold : nil)
                            .foregroundStyle(chosen ? reading?.ink ?? Palette.ink : reading?.secondaryInk ?? Palette.secondaryInk)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title(option))
                .accessibilityAddTraits(chosen ? .isSelected : [])
                .accessibilityIdentifier("\(identifier)-\(String(describing: option.id))")
            }
        }
    }
}

/// A choice among a few options: equal segments on a card capsule, the chosen one on the page
/// colour with its label in ink, the others in secondary ink. One line while every label fits
/// whole; otherwise the segments go in rows (half as many to a row, then a third, … one), so a
/// label never shrinks or truncates while a narrower arrangement would show it whole.
struct ChoicePicker<Option: Identifiable & Hashable, Label: View>: View {
    let options: [Option]
    @Binding var selection: Option
    /// Accessibility identifiers are `<identifier>-<option id>`.
    let identifier: String
    @ViewBuilder let label: (Option) -> Label

    @Environment(\.readingPalette) private var reading
    @ScaledMetric(relativeTo: .callout) private var height: CGFloat = 40

    /// How many segments to a row, widest arrangement first: 6 → 6, 3, 2, 1.
    private var perRow: [Int] {
        var counts: [Int] = []
        for parts in 1...max(1, options.count) {
            let count = (options.count + parts - 1) / parts
            if counts.last != count { counts.append(count) }
        }
        return counts
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(perRow, id: \.self) { count in
                rows(of: count)
            }
        }
    }

    private func rows(of count: Int) -> some View {
        let rows = stride(from: 0, to: options.count, by: count).map { Array(options[$0..<min($0 + count, options.count)]) }
        return VStack(spacing: Spacing.xxs) {
            ForEach(rows.indices, id: \.self) { index in
                EqualSegmentsLayout(spacing: Spacing.xxs) {
                    ForEach(rows[index]) { segment($0) }
                    // A short last row keeps the others' segment width.
                    ForEach(rows[index].count..<count, id: \.self) { _ in Color.clear.frame(height: 0) }
                }
            }
        }
        .padding(Spacing.xxs)
        .background(ChoicePickerTrack.fill(reading),
                    in: rows.count == 1 ? AnyShape(Capsule()) : AnyShape(RoundedRectangle(cornerRadius: Radius.pill,
                                                                                           style: .continuous)))
    }

    private func segment(_ option: Option) -> some View {
        let chosen = option == selection
        return Button { selection = option } label: {
            label(option)
                .foregroundStyle(chosen ? reading?.ink ?? Palette.ink : reading?.secondaryInk ?? Palette.secondaryInk)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, Spacing.xxs)
                .frame(maxWidth: .infinity, minHeight: min(height, 56))
                .background {
                    if chosen {
                        Capsule().fill(reading?.background ?? Palette.paper)
                            .overlay(Capsule().strokeBorder(reading?.hairline ?? Palette.hairline, lineWidth: 1))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityIdentifier("\(identifier)-\(String(describing: option.id))")
    }
}

/// Segments side by side, all as wide as the widest needs: asked for its ideal width (as a
/// `ViewThatFits` asks) it answers that many of the widest label, so a row only "fits" when
/// every label shows whole; given a width it splits it evenly.
private struct EqualSegmentsLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let gaps = spacing * CGFloat(subviews.count - 1)
        let width = proposal.width
            ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max()! * CGFloat(subviews.count) + gaps
        let segment = max(0, (width - gaps) / CGFloat(subviews.count))
        let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: segment, height: nil)).height }.max()!
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let gaps = spacing * CGFloat(subviews.count - 1)
        let segment = max(0, (bounds.width - gaps) / CGFloat(subviews.count))
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + CGFloat(index) * (segment + spacing), y: bounds.midY),
                          anchor: .leading, proposal: ProposedViewSize(width: segment, height: bounds.height))
        }
    }
}

/// The capsule a choice sits in: a step darker than the card it is on, so it shows on Settings'
/// cards and on the Aa panel alike.
enum ChoicePickerTrack {
    static func fill(_ reading: ReadingPalette?) -> Color { reading?.track ?? Palette.hairline }
}

/// Smaller and larger text, the size between them: `[A]  100%  [A]`.
struct TextSizeStepper: View {
    struct Model {
        /// "100%".
        let label: String
        let canShrink: Bool
        let canGrow: Bool
        let shrink: () -> Void
        let grow: () -> Void
    }

    let model: Model

    @Environment(\.readingPalette) private var reading
    @ScaledMetric(relativeTo: .callout) private var height: CGFloat = 40

    var body: some View {
        HStack(spacing: 0) {
            step(Icons.textSmaller, "Smaller Text", enabled: model.canShrink, id: "readingTextSmaller", action: model.shrink)
            Text(model.label)
                .typeStyle(.row, weight: .semibold)
                .monospacedDigit()
                .foregroundStyle(reading?.ink ?? Palette.ink)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("readingTextSize")
            step(Icons.textLarger, "Larger Text", enabled: model.canGrow, id: "readingTextLarger", action: model.grow)
        }
        .padding(Spacing.xxs)
        .frame(minHeight: min(height, 56) + Spacing.xs)
        .background(ChoicePickerTrack.fill(reading), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Text Size")
    }

    private func step(_ symbol: String, _ label: String, enabled: Bool, id: String,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .rowSymbol()
                .fontWeight(.medium)
                .foregroundStyle(reading?.ink ?? Palette.ink)
                .opacity(enabled ? 1 : Palette.disabledOpacity)
                .frame(width: BottomChrome.minTapTarget * 1.5, height: BottomChrome.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

#if DEBUG
struct TextAppearancePanelGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("the Aa panel on the app's colours") { panel(.matchApp) }
            PreviewState("on Sepia, in Pages") { panel(.sepia, layout: .pages).onReadingPreview(.sepia) }
            PreviewState("on Black, larger text at its largest") {
                panel(.black, canGrow: false).onReadingPreview(.black)
            }
        }
    }

    private func panel(_ theme: ReadingTheme, layout: ReadingLayout = .scroll, canGrow: Bool = true) -> some View {
        TextAppearancePanel(theme: .constant(theme), font: .constant(.serif), lineSpacing: .constant(.normal),
                            layout: .constant(layout),
                            textSize: .init(label: canGrow ? "100%" : "165%", canShrink: true, canGrow: canGrow,
                                            shrink: {}, grow: {}),
                            accent: .jade)
    }
}

#Preview("TextAppearancePanel · light", traits: .sizeThatFitsLayout) { TextAppearancePanelGallery().previewVariant(.light) }
#Preview("TextAppearancePanel · dark", traits: .sizeThatFitsLayout) { TextAppearancePanelGallery().previewVariant(.dark) }
#Preview("TextAppearancePanel · AX5", traits: .sizeThatFitsLayout) { TextAppearancePanelGallery().previewVariant(.largestText) }
#endif
