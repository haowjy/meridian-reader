import SwiftUI

/// The item's menu, then the screen's actions, then (regular width) navigation tiles, drawn as a
/// system menu's sections (`MenuRows(blocks:)`). Registry groups travel with each `MenuRow`.
struct MenuContext {
    var item: [MenuRow] = []
    var screen: [MenuRow]
    var tiles: [MenuRow]

    /// The rows by section for `MenuRows`: the item's, the screen's, then the tiles, a section each.
    var blocks: [[MenuRow]] { [item, screen, tiles] }

    /// The screen's registry rows: *Browsing History* from here, every other row from `custom`, the
    /// screen's own actions. The registry says which options a place shows; a place showing one its
    /// screen has no row for is a programming error, stopped here rather than drawn as another row.
    @MainActor
    static func screenRows(at place: MenuRegistry.Place, facts: MenuRegistry.Facts = .init(),
                           shell: ShellState, custom: (MenuRegistry.Option) -> MenuRow? = { _ in nil }) -> [MenuRow] {
        MenuRegistry.rows(.screen, at: place, facts) { option in
            if option == .browsingHistory {
                return MenuRow(id: "moreHistory", title: Verbs.browsingHistory, icon: Icons.history) { shell.present(.history) }
            }
            guard let row = custom(option) else { preconditionFailure("No row for \(option) at \(place)") }
            return row
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
