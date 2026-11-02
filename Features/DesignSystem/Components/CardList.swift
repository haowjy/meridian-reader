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
    /// least `RowMetrics.oneLineHeight` tall (the proportions of the system's Settings); a row taller by its
    /// content (two lines, a control, large text) keeps its height. With `listCard()` this is the one
    /// card-row policy: no row sets a height of its own; the List's minimum and `SymbolRow`'s
    /// (`rowMinimum`, which grows with the text) are this one value.
    ///
    /// The first content starts `Spacing.belowTopBar` under the top bar's buttons. A list that opens with
    /// a header (a section header, a title line, a folder's header) gets that from the List itself: its
    /// header's text sits there under a system bar. A list that opens with a bare card (`startsWithCard`)
    /// would get the List's own 35 pt top margin instead, so it sets its own.
    func cardListStyle(startsWithCard: Bool = false) -> some View {
        let minimum = RowMetrics.oneLineHeight
        return listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Palette.paper)
            .contentMargins(.horizontal, Spacing.pageMargin, for: .scrollContent)
            .listSectionSpacing(Spacing.m)
            .contentMargins(.top, startsWithCard ? Spacing.belowTopBar - Spacing.systemBarFoot : 0, for: .scrollContent)
            .environment(\.defaultMinListRowHeight, minimum)
            .environment(\.rowMinimum, minimum)
            .modifier(ListRoomReader())
    }

    /// A section's rows on the card's fill, `RowMetrics.edgeInset` in from its sides and no List inset
    /// above or below: the list's minimum (`cardListStyle`) gives a row its height, and a row's own
    /// vertical padding only keeps two lines clear of the separators. A row that pads itself
    /// horizontally (`ListRow`, whose trailing ⋯ slot sits `RowMetrics.accessoryTrailing` in) sets
    /// `.listRowInsets(EdgeInsets())` inside this, which wins.
    func listCard() -> some View {
        listRowBackground(Palette.chrome)
            .listRowInsets(EdgeInsets(top: 0, leading: RowMetrics.edgeInset, bottom: 0, trailing: RowMetrics.edgeInset))
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

    /// A section that is only a header (a screen's title line, a folder's header). A card after it starts
    /// `Spacing.m` under it, the gap between cards (and `Spacing.belowTopBar`): the header keeps
    /// `listHeader`'s `Spacing.xxs` below it, so the section spacing is the rest. A section header after it
    /// carries its own room above its text, as a list's first header does under a system bar, so the
    /// spacing is `Spacing.xxs` (`followedByHeader`).
    func headerOnlySection(followedByHeader: Bool = false) -> some View {
        listSectionSpacing(followedByHeader ? Spacing.xxs : Spacing.m - Spacing.xxs)
    }

    /// A note under a card: a footnote in line with the card, `Spacing.xs` below it. One line of it sits
    /// about 2 pt lower than a wrapped note: the List gives a header or footer a minimum height
    /// (`defaultMinListHeaderHeight`, footers included) and centres one shorter than that. Setting the
    /// minimum to 0 would line them up but moves every section header too.
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
