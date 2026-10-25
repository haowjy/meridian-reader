import SwiftUI

/// What the ⋯ panel shows: the item's own menu (a page's `ArticleMenu` or a folder's `FolderMenu`;
/// none on a screen with no item), then the screen's own rows ending in *Prepared Audio*, a
/// divider, then the same tile buttons on every surface (C140):
///
///     [Settings]  [Saved]  [History]  [Reader]
///
/// History is there on compact width only: regular width has the 🕘 button. Settings opens
/// Settings. Saved opens the Library (saved articles). History opens the browser's visits. Reader
/// (rightmost, the panel's focus point) varies by surface:
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
    /// apply, then *Prepared Audio*.
    /// `custom` gives the rows only a screen can make (its *Sort*, *Follow…*, *Reload*). Settings
    /// is a tile (C140), not a list row.
    @MainActor
    static func screenRows(at place: MenuRegistry.Place, facts: MenuRegistry.Facts = .init(),
                           shell: ShellState, custom: (MenuRegistry.Option) -> MenuRow? = { _ in nil }) -> [MenuRow] {
        return MenuRegistry.rows(.screen, at: place, facts) { option in
            if let row = custom(option) { return row }
            return MenuRow(id: "morePreparedAudio", title: Verbs.preparedAudio, icon: Icons.preparedAudio) { shell.present(.preparedAudio) }
        }
    }

    /// The tile buttons `[Settings][Saved]([History])[last]`; `last` is the surface's own focus tile. Every ⋯
    /// panel uses these same tiles in this order (C140). The compact chrome has no 🕘 button, so
    /// its panels add *History* as a tile before `last` (`compact`).
    @MainActor
    static func tiles(_ shell: ShellState, compact: Bool, last: MenuRow) -> [MenuRow] {
        var tiles = [
            MenuRow(id: "moreSettings", title: Verbs.settings, icon: Icons.settings) { shell.present(.settings) },
            MenuRow(id: "moreSaved", title: String(localized: "Saved"), icon: Icons.library) { shell.openLibrary() },
        ]
        if compact {
            tiles.append(MenuRow(id: "moreHistory", title: Verbs.history, icon: Icons.history) { shell.present(.history) })
        }
        return tiles + [last]
    }
}
