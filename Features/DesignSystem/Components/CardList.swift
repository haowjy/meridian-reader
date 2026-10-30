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
    /// Grouped cards on paper, at the page margin, `Spacing.s` between sections. Rows are as tall
    /// as their content unless `rowHeight` sets a minimum (Settings').
    func cardListStyle(rowHeight: CGFloat = 0) -> some View {
        listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Palette.paper)
            .contentMargins(.horizontal, Spacing.pageMargin, for: .scrollContent)
            .listSectionSpacing(Spacing.s)
            .environment(\.defaultMinListRowHeight, rowHeight)
    }

    /// A section's rows on the card's fill.
    func listCard() -> some View {
        listRowBackground(Palette.chrome)
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

    /// A note under a card: a footnote in line with the card, `gap` below it (Settings' notes
    /// take `Spacing.xs`, clear of its taller rows).
    func listFooter(gap: CGFloat = Spacing.xxs) -> some View {
        footnote()
            .textCase(nil)
            .listRowInsets(EdgeInsets(top: gap, leading: 0, bottom: 0, trailing: 0))
    }
}
