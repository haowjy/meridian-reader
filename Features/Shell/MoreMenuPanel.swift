import SwiftUI

/// The ⋯ menu panel's content (shown by `MorphMenuOverlay`), drawn from a `MenuContext`: the
/// item's rows (a page's or a folder's own menu, the same rows its ⋯ and long press show), a
/// divider, the screen's rows ending in *Prepared Audio*, a divider, then the row of big
/// buttons whose rightmost one is the panel's focus point (`morphMenuFocus`). It draws rows as
/// they come (`MenuRow`): hidden ones left out, dimmed ones disabled, destructive ones red, a
/// submenu (*Sort*) with its chevron. Every row closes the panel and runs its action once the
/// panel has started collapsing. On the Reader and Now Playing the panel takes the reading page's
/// colours (`readingPalette`).
struct MoreMenuPanel: View {
    let context: MenuContext
    let close: MorphMenuClose

    @Environment(\.readingPalette) private var reading

    private var ink: Color { reading?.ink ?? Palette.ink }
    private var secondaryInk: Color { reading?.secondaryInk ?? Palette.secondaryInk }

    var body: some View {
        VStack(spacing: 0) {
            // At the default text size every panel fits (`RowHeight.menu`); at large sizes a
            // folder's screen has more rows than the screen is tall: they scroll, and the big
            // buttons stay at the bottom, under the thumb.
            ViewThatFits(in: .vertical) {
                rows
                ScrollView { rows }
                    .scrollBounceBehavior(.basedOnSize)
            }
            divider
            HStack(spacing: 0) {
                ForEach(Array(context.tiles.enumerated()), id: \.element.id) { index, tile in
                    self.tile(tile, focus: index == context.tiles.count - 1)
                }
            }
            .padding(.horizontal, Spacing.xs)
        }
        .padding(.vertical, Spacing.xs)
        .frame(width: Panel.width)
    }

    /// The item's rows, a divider, the screen's rows.
    private var rows: some View {
        VStack(spacing: 0) {
            let item = context.item.filter(\.isShown)
            if !item.isEmpty {
                ForEach(item) { row($0) }
                divider
            }
            ForEach(context.screen.filter(\.isShown)) { row($0) }
        }
    }

    // MARK: - Building blocks

    @ViewBuilder
    private func row(_ row: MenuRow) -> some View {
        if row.submenu.isEmpty {
            Button { close(then: row.action) } label: { rowLabel(row) }
                .buttonStyle(MenuRowStyle())
                .disabled(row.availability == .disabled)
                .accessibilityIdentifier(row.id)
        } else {
            Menu {
                ForEach(row.submenu.filter(\.isShown)) { choice in
                    Button { close(then: choice.action) } label: {
                        if let icon = choice.icon { Label(choice.title, systemImage: icon) } else { Text(choice.title) }
                    }
                }
            } label: {
                rowLabel(row, trailing: Icons.disclosure)
            }
            .disabled(row.availability == .disabled)
            .accessibilityIdentifier(row.id)
        }
    }

    private func rowLabel(_ row: MenuRow, trailing: String? = nil) -> some View {
        SymbolRow(row.title, symbol: row.icon, ink: row.isDestructive ? Palette.destructive : nil) {
            if let trailing {
                Image(systemName: trailing)
                    .disclosureSymbol()
                    .foregroundStyle(secondaryInk)
            }
        }
        .rowHeight(RowHeight.menu)
        .padding(.horizontal, Spacing.l)
    }

    private var divider: some View {
        Divider()
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.xs)
    }

    /// A big button. `focus`: its icon is the panel's focus point (placed by `MorphMenuOverlay`
    /// slightly up and left of the ⋯ glyph).
    private func tile(_ tile: MenuRow, focus: Bool) -> some View {
        Button { close(then: tile.action) } label: {
            VStack(spacing: Spacing.xs) {
                Image(systemName: tile.icon ?? Icons.more)
                    .tileSymbol()
                    .morphMenuFocus(focus)
                Text(tile.title)
                    .typeStyle(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowStyle(cornerRadius: Radius.card))
        .disabled(tile.availability == .disabled)
        .accessibilityLabel(tile.accessibilityLabel ?? tile.title)
        .accessibilityHint(tile.accessibilityHint ?? "")
        .accessibilityIdentifier(tile.id)
    }
}

/// Pressed-state highlight for menu panel rows (like a system menu).
private struct MenuRowStyle: ButtonStyle {
    var cornerRadius: CGFloat = 0
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.readingPalette) private var reading

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? 1 : Palette.disabledOpacity)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill((reading?.ink ?? Palette.ink).opacity(configuration.isPressed ? 0.08 : 0))
            )
    }
}

extension ArticleSort {
    /// Its name in the Sort menu.
    var title: String {
        switch self {
        case .manual: String(localized: "Manual")
        case .newest: String(localized: "Newest")
        case .title: String(localized: "Title")
        }
    }
}

/// The ⋯ toolbar button (browser, library, reader listen bar): opens
/// `menu()` in the shell's morph panel, grown from this button's frame. Its glyph fades while a
/// menu is open, so the button reads as turning
/// into the panel.
struct MoreMenuButton: View {
    let id: String
    /// The compact bottom chrome's ⋯: a round surface filling the frame it is given.
    var chrome = false
    let menu: () -> MenuContext

    @Environment(ShellState.self) private var shell
    @State private var frame: CGRect = .zero

    private var isOpen: Bool { shell.menu != nil }

    var body: some View {
        if chrome {
            button.buttonStyle(.plain)
        } else {
            button
        }
    }

    private var button: some View {
        Button {
            shell.openMenu(menu(), from: frame)
        } label: {
            if chrome {
                ChromeRoundLabel(symbol: Icons.more, label: Verbs.more)
            } else {
                Image(systemName: Icons.more)
                    .toolbarIconFrame()
            }
        }
        .accessibilityLabel(Verbs.more)
        .accessibilityIdentifier(id)
        .morphMenuButtonHidden(isOpen)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
    }
}
