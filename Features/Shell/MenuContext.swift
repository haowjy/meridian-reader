import SwiftUI

/// The item's menu, then the screen's actions. Compact width draws system-menu sections;
/// regular width keeps its navigation tiles. Registry groups travel with each `MenuRow`.
struct MenuContext {
    var item: [MenuRow] = []
    var screen: [MenuRow]
    var tiles: [MenuRow]
    /// Opened on a reading page (the Reader, Now Playing or the Browser's reader mode): the panel takes its colours.
    var isOnReadingPage = false

    /// The same rows in a system menu (`MenuRows`, a title line's ⋯ on compact width): the item's, the
    /// screen's, then the tiles as rows, a section each.
    var blocks: [[MenuRow]] { [item, screen, tiles] }

    /// The screen's registry rows. The caller supplies actions specific to its screen.
    @MainActor
    static func screenRows(at place: MenuRegistry.Place, facts: MenuRegistry.Facts = .init(),
                           shell: ShellState, custom: (MenuRegistry.Option) -> MenuRow? = { _ in nil }) -> [MenuRow] {
        MenuRegistry.rows(.screen, at: place, facts) { option in
            if let row = custom(option) { return row }
            return MenuRow(id: "moreHistory", title: Verbs.browsingHistory, icon: Icons.history) { shell.present(.history) }
        }
    }

    /// The tile buttons `[Settings][Library][last]` on regular width, `[Library][Browsing History][last]`
    /// on compact (`compact`); `last` is the surface's own focus tile. Every ⋯ panel uses these same tiles
    /// in this order (C140). Compact width has Settings in the chrome's pill and no 🕘 button, so its
    /// menus drop *Settings* and add *Browsing History* before `last`.
    @MainActor
    static func tiles(_ shell: ShellState, compact: Bool, last: MenuRow) -> [MenuRow] {
        let library = MenuRow(id: "moreLibrary", title: Verbs.library, icon: Icons.library) { shell.openLibrary() }
        guard compact else {
            return [MenuRow(id: "moreSettings", title: Verbs.settings, icon: Icons.settings, action: shell.showSettings), library, last]
        }
        return [library, MenuRow(id: "moreHistory", title: Verbs.browsingHistory, icon: Icons.history) { shell.present(.history) }, last]
    }
}
