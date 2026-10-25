import SwiftUI

/// What the ⋯ panel shows: the item's own menu (a page's `ArticleMenu` or a folder's `FolderMenu`;
/// none on a screen with no item), then the screen's own rows ending in *Prepared Audio*, a
/// divider, then the same three tile buttons on every surface (C140):
///
///     [Settings]  [Saved]  [Reader]
///
/// Settings opens Settings. Saved opens the Library (saved articles). Reader (rightmost, the
/// panel's focus point) varies by surface:
///
/// - browser:  open the current page in the Reader (greyed when not readable)
/// - Library:  go to Now Playing (greyed when nothing is playing)
/// - Browse Reader / Now Playing:  disabled (already in the reading view)
struct MenuContext {
    var item: [MenuRow] = []
    var screen: [MenuRow]
    var tiles: [MenuRow]
    /// Opened on a reading page (the Reader or Now Playing): the panel takes its colours.
    var isOnReadingPage = false

    /// A screen's own block, from `MenuRegistry` (C98): *Sort*, *Follow…*, *Reload* where they
    /// apply, then *Prepared Audio* and, in the compact chrome's ⋯ (`compact`), *History*.
    /// `custom` gives the rows only a screen can make (its *Sort*, *Follow…*, *Reload*). Settings
    /// is a tile (C140), not a list row.
    @MainActor
    static func screenRows(at place: MenuRegistry.Place, facts: MenuRegistry.Facts = .init(), compact: Bool,
                           shell: ShellState, custom: (MenuRegistry.Option) -> MenuRow? = { _ in nil }) -> [MenuRow] {
        var facts = facts
        facts.compact = compact
        return MenuRegistry.rows(.screen, at: place, facts) { option in
            if let row = custom(option) { return row }
            if option == .history {
                return MenuRow(id: "moreHistory", title: Verbs.history, icon: Icons.history) { shell.present(.history) }
            }
            return MenuRow(id: "morePreparedAudio", title: Verbs.preparedAudio, icon: Icons.preparedAudio) { shell.present(.preparedAudio) }
        }
    }

    /// The three tile buttons `[Settings][Saved][last]`; `last` is the surface's own focus tile.
    /// Every ⋯ panel uses these same three tiles in this order (C140).
    @MainActor
    static func tiles(_ shell: ShellState, last: MenuRow) -> [MenuRow] {
        [
            MenuRow(id: "moreSettings", title: Verbs.settings, icon: Icons.settings) { shell.present(.settings) },
            MenuRow(id: "moreSaved", title: String(localized: "Saved"), icon: Icons.library) { shell.openLibrary() },
            last,
        ]
    }
}
