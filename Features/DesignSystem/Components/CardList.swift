import SwiftUI

/// The app's lists of cards (the Library, a folder, Settings, Downloads, Follow, the Move tree):
/// grouped cards on paper at the page margin, each section's title a `SectionHeader` in line with
/// the cards, and a note under a card in caption type.
///
/// ```
/// Listening                                  `SectionHeader` + `.listHeader()`
/// ╭──────────────────────────────────────╮
/// │ Apple                              ✓ │   rows on `.listCard()`
/// ╰──────────────────────────────────────╯
/// On-device voices download once, …          `.listFooter()`
/// ```
extension View {
    /// Grouped cards on paper, at the page margin, `Spacing.l` between sections.
    func cardListStyle() -> some View {
        listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Palette.paper)
            .contentMargins(.horizontal, Spacing.pageMargin, for: .scrollContent)
            .listSectionSpacing(Spacing.l)
            .environment(\.defaultMinListRowHeight, 0)
    }

    /// A section's rows on the card's fill.
    func listCard() -> some View {
        listRowBackground(Palette.chrome)
    }

    /// A section header (a `SectionHeader`) in line with the cards: no extra header inset.
    func listHeader() -> some View {
        textCase(nil)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: Spacing.xs, trailing: 0))
    }

    /// A note under a card: caption, secondary ink, in line with the card.
    func listFooter() -> some View {
        typeStyle(.caption)
            .foregroundStyle(Palette.secondaryInk)
            .textCase(nil)
            .listRowInsets(EdgeInsets(top: Spacing.xs, leading: 0, bottom: 0, trailing: 0))
    }
}
