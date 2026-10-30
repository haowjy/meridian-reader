import SwiftUI

/// The app's lists of cards (the Library, a folder, Settings, Prepared audio, Follow, the Move tree):
/// grouped cards on paper at the page margin, each section's title a `SectionHeader` in line with
/// the cards, and a note under a card in caption type.
///
/// ```
/// Listening                                  `SectionHeader` + `.listHeader()`
/// ╭──────────────────────────────────────╮
/// │ Apple                              ✓ │   rows on `.listCard()`
/// ╰──────────────────────────────────────╯
/// On-device voices prepare once, …          `.listFooter()`
/// ```
extension View {
    /// Grouped cards on paper, at the page margin, `Spacing.m` between sections, every row at
    /// least `RowHeight.card` tall (the proportions of the system's Settings); a row taller by its
    /// content (a two-line `ListRow`) keeps its height.
    func cardListStyle() -> some View {
        listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Palette.paper)
            .contentMargins(.horizontal, Spacing.pageMargin, for: .scrollContent)
            .listSectionSpacing(Spacing.m)
            .environment(\.defaultMinListRowHeight, RowHeight.card)
    }

    /// A section's rows on the card's fill, `Spacing.m` in from its sides and no List inset above
    /// or below: a row holds its own tap height (`SymbolRow`), and the List's inset on top of it
    /// would double it. A row that pads itself (`ListRow`) sets `.listRowInsets(EdgeInsets())`
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
