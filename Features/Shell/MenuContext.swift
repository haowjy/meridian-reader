import SwiftUI

/// What the ⋯ panel shows, in three blocks: the item's own menu (a page's `ArticleMenu` or a
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

    /// A screen's own block, from `MenuRegistry` (C98): *Sort*, *Follow…*, *Reload* where they
    /// apply, then *Downloads* and *Settings*, always last. `custom` gives the rows only a screen
    /// can make (its *Sort*, *Follow…*, *Reload*).
    @MainActor
    static func screenRows(at place: MenuRegistry.Place, facts: MenuRegistry.Facts = .init(), shell: ShellState,
                           custom: (MenuRegistry.Option) -> MenuRow? = { _ in nil }) -> [MenuRow] {
        MenuRegistry.rows(.screen, at: place, facts) { option in
            if let row = custom(option) { return row }
            switch option {
            case .settings:
                return MenuRow(id: "moreSettings", title: Verbs.settings, icon: Icons.settings) { shell.present(.settings) }
            default:
                return MenuRow(id: "moreDownloads", title: Verbs.downloads, icon: Icons.downloads) { shell.present(.downloads) }
            }
        }
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
