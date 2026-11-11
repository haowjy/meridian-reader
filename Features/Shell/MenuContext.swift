import SwiftUI

/// The item's menu, then the screen's actions, then (regular width) navigation tiles, drawn as a
/// system menu's sections (`MenuRows(blocks:)`). Registry groups travel with each `MenuRow`.
struct MenuContext {
    var item: [MenuRow] = []
    var screen: [MenuRow]
    var tiles: [MenuRow]

    /// The rows by section for `MenuRows`: the item's, the screen's, then the tiles, a section each.
    var blocks: [[MenuRow]] { [item, screen, tiles] }

    /// The screen's registry rows: *Start Page* and *Browsing History* from here, every other row from `custom`, the
    /// screen's own actions. The registry says which options a place shows; a place showing one its
    /// screen has no row for is a programming error, stopped here rather than drawn as another row.
    @MainActor
    static func screenRows(at place: MenuRegistry.Place, facts: MenuRegistry.Facts = .init(),
                           shell: ShellState, custom: (MenuRegistry.Option) -> MenuRow? = { _ in nil }) -> [MenuRow] {
        MenuRegistry.rows(.screen, at: place, facts) { option in
            switch option {
            case .startPage:
                return MenuRow(id: "moreStartPage", title: Verbs.startPage, icon: Icons.startPage, action: shell.showStartPage)
            case .browsingHistory:
                return MenuRow(id: "moreHistory", title: Verbs.browsingHistory, icon: Icons.history) { shell.present(.history) }
            default:
                break
            }
            guard let row = custom(option) else { preconditionFailure("No row for \(option) at \(place)") }
            return row
        }
    }

    /// The navigation rows `[Settings][Library][last]` on regular width, `[Library][Browsing History][last]`
    /// on compact (`compact`), then *Help*; `last` is the surface's own focus row, nil where it can never apply (Listen
    /// on a reading page). Every ⋯ menu uses these same rows in this order. Compact width has
    /// Settings in the chrome's pill and no 🕘 button, so its menus drop *Settings* and add *Browsing
    /// History* before `last`. The Library row is left out on the Library, where it would do nothing.
    @MainActor
    static func tiles(_ shell: ShellState, compact: Bool, last: MenuRow?) -> [MenuRow] {
        var rows: [MenuRow] = []
        if !compact {
            rows.append(MenuRow(id: "moreSettings", title: Verbs.settings, icon: Icons.settings, action: shell.showSettings))
        }
        if shell.surface != .library {
            rows.append(MenuRow(id: "moreLibrary", title: Verbs.library, icon: Icons.library) { shell.openLibrary() })
        }
        if compact {
            rows.append(MenuRow(id: "moreHistory", title: Verbs.browsingHistory, icon: Icons.history) { shell.present(.history) })
        }
        return rows + [help(shell)] + [last].compactMap { $0 }
    }

    /// *Help*: the welcome article, Listen paused on it. In every `tiles`, and alone in the
    /// compact Library's, which has no other.
    @MainActor
    static func help(_ shell: ShellState) -> MenuRow {
        MenuRow(id: "moreHelp", title: Verbs.help, icon: Icons.help) { shell.openWelcome() }
    }
}
