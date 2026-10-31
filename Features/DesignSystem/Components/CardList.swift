import SwiftUI

/// The app's lists of cards (the Library, a folder, Settings, Prepared audio, Follow, the Move tree):
/// grouped cards on paper at the page margin, each section's title a `SectionHeader` in line with
/// the cards, and a note under a card in caption type.
///
/// ```
/// Listening                                  `SectionHeader` + `.listHeader()`
/// ╭──────────────────────────────────────╮
/// │ Phonon                             ✓ │   rows on `.listCard()`
/// ╰──────────────────────────────────────╯
/// On-device voices prepare once, …          `.listFooter()`
/// ```
extension View {
    /// Grouped cards on paper, at the page margin, `Spacing.m` between sections, every row at
    /// least `Control.bar` tall (the proportions of the system's Settings); a row taller by its
    /// content (two lines, a control, large text) keeps its height. With `listCard()` this is the one
    /// card-row policy: no row sets a height of its own; the List's minimum and `SymbolRow`'s
    /// (`rowMinimum`, which grows with the text) are this one value.
    func cardListStyle() -> some View {
        let minimum = Control.bar
        return listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Palette.paper)
            .contentMargins(.horizontal, Spacing.pageMargin, for: .scrollContent)
            .listSectionSpacing(Spacing.m)
            .environment(\.defaultMinListRowHeight, minimum)
            .environment(\.rowMinimum, minimum)
    }

    /// A section's rows on the card's fill, `Spacing.m` in from its sides and no List inset above
    /// or below: the list's minimum (`cardListStyle`) gives a row its height, and a row's own
    /// vertical padding only keeps two lines clear of the separators. A row that pads itself
    /// horizontally (`ListRow`, which centres its ⋯ on the toolbar's) sets `.listRowInsets(EdgeInsets())`
    /// inside this, which wins.
    func listCard() -> some View {
        listRowBackground(Palette.chrome)
            .listRowInsets(EdgeInsets(top: 0, leading: Spacing.m, bottom: 0, trailing: Spacing.m))
    }

    /// A note's look: caption, secondary ink. A card's footer (`listFooter()`) and a note outside
    /// a list (Follow's under its chapters).
    func footnote() -> some View {
        typeStyle(.caption)
            .foregroundStyle(Palette.secondaryInk)
    }

    /// A section header (a `SectionHeader`) in line with the cards: no extra header inset.
    func listHeader() -> some View {
        textCase(nil)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: Spacing.xxs, trailing: 0))
    }

    /// A note under a card: a footnote in line with the card, `Spacing.xs` below it.
    func listFooter() -> some View {
        footnote()
            .textCase(nil)
            .listRowInsets(EdgeInsets(top: Spacing.xs, leading: 0, bottom: 0, trailing: 0))
    }
}

extension EnvironmentValues {
    /// A `SymbolRow`'s minimum height at the default text size: the tap floor, `Control.tap`, outside a
    /// card list; a card list's row minimum on one (`cardListStyle`).
    @Entry var rowMinimum: CGFloat = Control.tap
}
