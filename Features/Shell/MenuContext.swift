import SwiftUI

/// What a ⋯ shows: the item's own menu (a page's `ArticleMenu` or a folder's `FolderMenu`;
/// none on a screen with no item), then the screen's own rows ending in *Prepared Audio*, a
/// divider, then the same tile buttons on every surface (C140). The ⋯ panel draws them; compact
/// width's title lines and the Browser field's hold menu draw the same rows as a system menu (`blocks`):
///
///     [Settings]  [Library]  [History]  [Reader]
///
/// History is there on compact width only: regular width has the 🕘 button. Settings is there on
/// regular width only: compact width has it in the chrome's pill. Library opens the Library. History opens the browser's visits. Reader
/// (rightmost, the panel's focus point) varies by surface:
///
/// - browser:  open the current page in the Reader (greyed when not readable)
/// - Library:  go to Now Playing (greyed when nothing is playing)
/// - Browse Reader / Now Playing:  disabled (already in the reading view)
struct MenuContext {
    var item: [MenuRow] = []
    var screen: [MenuRow]
    var tiles: [MenuRow]
    /// Opened on a reading page (the Reader, Now Playing or the Browser's reader mode): the panel takes its colours.
    var isOnReadingPage = false

    /// The same rows in a system menu (`MenuRows`, a title line's ⋯ on compact width): the item's, the
    /// screen's, then the tiles as rows, a section each.
    var blocks: [[MenuRow]] { [item, screen, tiles] }

    /// A screen's own block, from `MenuRegistry` (C98): *Text Appearance*, *Sort*, *Reload* where they
    /// apply, then *Prepared Audio*.
    /// `custom` gives the rows only a screen can make (its *Sort*, *Reload*). Settings
    /// is a tile (C140), not a list row.
    @MainActor
    static func screenRows(at place: MenuRegistry.Place, facts: MenuRegistry.Facts = .init(),
                           shell: ShellState, custom: (MenuRegistry.Option) -> MenuRow? = { _ in nil }) -> [MenuRow] {
        return MenuRegistry.rows(.screen, at: place, facts) { option in
            if let row = custom(option) { return row }
            return MenuRow(id: "morePreparedAudio", title: Verbs.preparedAudio, icon: Icons.preparedAudio) { shell.present(.preparedAudio) }
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
