import SwiftUI

/// What the ⋯ panel shows, in three blocks: the item's own menu (a page's `PageMenu` or a
/// folder's `FolderMenu`, the same rows as everywhere that item's menu shows; none on a screen
/// with no item, the Library's home and the start page), then the screen's own rows, ending in
/// *Downloads* and *Settings* (`tail`), then the big buttons, the rightmost (nearest the thumb,
/// the panel's focus point) last:
///
/// - browser:  `[Favorites][History][Reader]`
/// - the Reader and Now Playing:  `[Favorites][History][Website]`
/// - Library: `[Favorites][History][Browser]`
struct MenuContext {
    var item: [MenuRow] = []
    var screen: [MenuRow]
    var tiles: [MenuRow]
    /// Opened on a reading page (the Reader or Now Playing): the panel takes its colours.
    var isOnReadingPage = false

    /// The rows every screen's block ends with: *Downloads*, then *Settings*, always last.
    @MainActor
    static func tail(_ shell: ShellState) -> [MenuRow] {
        [
            MenuRow(id: "moreDownloads", title: Verbs.downloads, icon: Icons.downloads) { shell.present(.downloads) },
            MenuRow(id: "moreSettings", title: Verbs.settings, icon: Icons.settings) { shell.present(.settings) },
        ]
    }

    /// The first two big buttons, the same on every surface; `last` is the surface's own.
    @MainActor
    static func tiles(_ shell: ShellState, last: MenuRow) -> [MenuRow] {
        [
            MenuRow(id: "moreFavorites", title: Verbs.favorites, icon: Icons.favorite, action: shell.showFavorites),
            MenuRow(id: "moreHistory", title: Verbs.history, icon: Icons.history) { shell.present(.history) },
            last,
        ]
    }
}
