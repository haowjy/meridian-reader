import SwiftUI

/// A page's menu: the one definition every way to a page's menu renders (decision C4), as a
/// row's ⋯ and long press (`MenuRows`, through this view) and as the item block of the ⋯ panel
/// (`rows`). Library rows on every tab and in search, a folder's rows, Favorites tiles, History
/// visits, the Now Playing bar, the Reader, Now Playing and the browser all show these rows, in
/// this order, with these names and symbols:
///
/// | Row | Shows |
/// |---|---|
/// | Read / Go to <place> | *Read* where the page isn't open (hidden in the Reader, Now Playing and the browser); Now Playing's *Go to* in its place |
/// | Play from Here | a page in a folder, in a list |
/// | Download / Remove Download (red) | dimmed out of the Library |
/// | Add to / Remove from Favorites | dimmed when it can't be starred |
/// | Move to… / Save to Folder… | *Save to Folder…* out of the Library, *Move to…* in it |
/// | Mark as Finished / Unfinished | dimmed until saved |
/// | Mark All Above as Finished | a page in a folder, in a list |
/// | Skip in / Play in Playback | a page in a folder |
/// | Share | a page with a web address |
/// | Select | a list with Edit |
/// | Save to Library / Remove from Library (red) | dimmed with no text to save |
/// | Remove from Recent (red) | out of the Library; dimmed while it isn't in Recent |
///
/// A place only hides or dims rows (DR-09: hidden where the row can never apply there, dimmed
/// where it applies but can't run now); what a place adds of its own comes after, in its own
/// block. *Remove Download* takes the page out of every download and keeps it out (P8).
struct PageMenu: View {
    /// Where the menu opens: what decides the rows that can't apply there.
    enum Place {
        /// A Library list's row (every tab, search, a folder's screen). `onSelect`: *Select*,
        /// Edit with this row selected (folder screens only).
        case list(onSelect: (() -> Void)?)
        /// A Favorites tile on the start page, a History visit, the Now Playing bar.
        case elsewhere
        /// The Reader and the browser, which show the page.
        case open
        /// Now Playing, with *Go to* where the page plays from.
        case nowPlaying(GoTo)
    }

    /// Now Playing's *Go to <place>*: the folder the page plays from, or the Library.
    struct GoTo {
        let name: String
        let symbol: String
        let availability: MenuAvailability
        let action: () -> Void
    }

    let actions: PageActions
    let place: Place

    var body: some View {
        MenuRows(rows)
    }

    var rows: [MenuRow] {
        let page = actions.page
        let inLibrary = actions.isInLibrary
        let isSaved = actions.isSaved
        let inFolder = page?.folder != nil
        let canPlay = isSaved || page?.isWaitingChapter == true
        let hasDownload = actions.hasDownload
        let isFavorite = actions.isFavorite
        let isFinished = page?.finishedAt != nil
        let skips = page?.skipsInPlayback == true
        let library = actions.libraryActions
        return [
            first,
            MenuRow(id: "menuPlayFromHere", title: Verbs.playFromHere, icon: Icons.play,
                    availability: MenuAvailability(applies: isList && inFolder, when: canPlay)) {
                if let page { library.playFromStart(page) }
            },
            MenuRow(id: "menuDownload", title: hasDownload ? Verbs.removeDownload : Verbs.download,
                    icon: hasDownload ? Icons.removeDownload : Icons.download, isDestructive: hasDownload,
                    availability: MenuAvailability(when: inLibrary), action: actions.toggleDownload),
            MenuRow(id: "menuFavorite", title: isFavorite ? Verbs.removeFromFavorites : Verbs.addToFavorites,
                    icon: isFavorite ? Icons.unfavorite : Icons.favorite,
                    availability: MenuAvailability(when: actions.canFavorite), action: actions.toggleFavorite),
            MenuRow(id: "menuMove", title: inLibrary ? Verbs.moveTo : Verbs.saveToFolder, icon: Icons.move,
                    availability: MenuAvailability(when: inLibrary || actions.canSave), action: actions.saveToFolder),
            MenuRow(id: "menuFinished", title: isFinished ? Verbs.markUnfinished : Verbs.markFinished,
                    icon: isFinished ? Icons.markUnfinished : Icons.markFinished,
                    availability: MenuAvailability(when: isSaved)) {
                if let page { library.setFinished([page], !isFinished) }
            },
            MenuRow(id: "menuMarkAllAbove", title: Verbs.markAllAboveFinished, icon: Icons.markAllAboveFinished,
                    availability: MenuAvailability(applies: isList && inFolder, when: isSaved)) {
                if let page { library.markAllAbove(page) }
            },
            // A waiting chapter too: one whose text can't be had is skipped so playback goes past it.
            MenuRow(id: "menuSkip", title: skips ? Verbs.playInPlayback : Verbs.skipInPlayback,
                    icon: skips ? Icons.includeInPlayback : Icons.skipInPlayback,
                    availability: MenuAvailability(applies: inFolder, when: canPlay)) {
                if let page { library.toggleSkipsInPlayback(page) }
            },
            MenuRow(id: "menuShare", title: Verbs.share, icon: Icons.share,
                    availability: MenuAvailability(applies: actions.shareURL != nil), action: actions.share),
            MenuRow(id: "menuSelect", title: Verbs.select, icon: Icons.select,
                    availability: MenuAvailability(applies: onSelect != nil)) { onSelect?() },
            MenuRow(id: "menuSave", title: inLibrary ? Verbs.removeFromLibrary : Verbs.saveToLibrary,
                    icon: inLibrary ? Icons.unsave : Icons.save, isDestructive: inLibrary,
                    availability: MenuAvailability(when: inLibrary || actions.canSave), action: actions.toggleSaved),
            // The same remove as the Library's (`LibraryStore.remove`): in no list after, the star kept.
            MenuRow(id: "menuRemoveFromRecent", title: Verbs.removeFromRecent, icon: Icons.removeFromRecent,
                    isDestructive: true,
                    availability: MenuAvailability(applies: !inLibrary, when: page.map(LibraryQueries.isInRecent) == true),
                    action: actions.remove),
        ]
    }

    /// *Read*, or Now Playing's *Go to*: the page's first row.
    private var first: MenuRow {
        switch place {
        case .nowPlaying(let goTo):
            MenuRow(id: "menuGoTo", title: String(localized: "Go to \(goTo.name)"), icon: goTo.symbol,
                    availability: goTo.availability, action: goTo.action)
        case .open:
            MenuRow(id: "menuRead", title: Verbs.read, icon: Icons.reader, availability: .hidden)
        case .list, .elsewhere:
            MenuRow(id: "menuRead", title: Verbs.read, icon: Icons.reader,
                    availability: MenuAvailability(when: actions.page != nil || actions.url != nil), action: actions.read)
        }
    }

    private var isList: Bool {
        if case .list = place { return true }
        return false
    }

    private var onSelect: (() -> Void)? {
        if case .list(let onSelect) = place { return onSelect }
        return nil
    }
}

extension PageActions {
    /// The ⋯ panel of the Reader and Now Playing (decision D24): the page's menu, then *Downloads*
    /// and *Settings*, then `[Favorites][History][Website]`. *Website* is the page's own web page
    /// in the browser, wherever the sheet was opened from; playback keeps going.
    func readingPageMenu(_ place: PageMenu.Place) -> MenuContext {
        let website = MenuRow(id: "moreWebsite", title: String(localized: "Website"), icon: Icons.browser,
                              availability: MenuAvailability(when: websiteURL != nil),
                              accessibilityLabel: String(localized: "View Website"),
                              accessibilityHint: String(localized: "Opens the page in the browser")) { [self] in
            if let websiteURL { shell.openWebsite(websiteURL) }
        }
        return MenuContext(item: PageMenu(actions: self, place: place).rows, screen: MenuContext.tail(shell),
                           tiles: MenuContext.tiles(shell, last: website), isOnReadingPage: true)
    }
}
