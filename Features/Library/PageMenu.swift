import SwiftUI

/// A page's menu: the one definition every way to a page's menu renders (decisions C4, C98), as a
/// row's ⋯ and long press (`MenuRows`, through this view) and as the item block of the ⋯ panel
/// (`rows`). Which options show where, in what order and greyed or not is `MenuRegistry`'s
/// (docs/MENUS.md); this gives each its title, symbol and action. Built only when the menu opens:
/// rows pass this view, never its `rows`, so nothing here runs on a row's redraw.
struct PageMenu: View {
    /// Where the menu opens.
    enum Place {
        /// A Library list's row (every tab, search, a folder's screen).
        case list
        /// A Favorites tile on the start page.
        case elsewhere
        /// The Now Playing bar's long press; `onStop`: *Stop Listening* (nil: nothing loaded).
        case bar(onStop: (() -> Void)?)
        /// A History visit; `onRemove`: *Remove from History*.
        case history(onRemove: () -> Void)
        /// The Reader, which shows the page.
        case open
        /// The browser, which shows the page.
        case browser
        /// Now Playing, with *Go to* where the page plays from.
        case nowPlaying(GoTo)

        var registryPlace: MenuRegistry.Place {
            switch self {
            case .list: .row
            case .elsewhere: .tile
            case .bar: .bar
            case .history: .history
            case .open: .reader
            case .browser: .browser
            case .nowPlaying: .nowPlaying
            }
        }
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
        MenuRows(blocks: blocks)
    }

    var rows: [MenuRow] { blocks.flatMap { $0 } }

    /// The page's state as the registry reads it.
    var facts: MenuRegistry.Facts {
        let page = actions.page
        var facts = MenuRegistry.Facts()
        facts.hasTarget = page != nil || actions.url != nil
        facts.hasPage = page != nil
        facts.inLibrary = actions.isInLibrary
        facts.isSaved = actions.isSaved
        facts.offersSave = actions.offersSave
        facts.canSave = actions.canSave
        facts.inFolder = page?.folder != nil
        facts.canPlay = actions.isSaved || page?.isWaitingChapter == true
        facts.canFavorite = actions.canFavorite
        facts.hasShareURL = actions.shareURL != nil
        facts.inRecent = !facts.inLibrary && page.map(LibraryQueries.isInRecent) == true
        if case .nowPlaying(let goTo) = place { facts.goToEnabled = goTo.availability == .enabled }
        if case .bar(let onStop) = place { facts.isLoaded = onStop != nil }
        return facts
    }

    var blocks: [[MenuRow]] {
        MenuRegistry.blocks(.page, at: place.registryPlace, facts, row: row)
    }

    private func row(_ option: MenuRegistry.Option) -> MenuRow {
        let page = actions.page
        let library = actions.libraryActions
        let offersSave = actions.offersSave
        switch option {
        case .read:
            return MenuRow(id: "menuRead", title: Verbs.read, icon: Icons.reader, action: actions.read)
        case .goTo:
            guard case .nowPlaying(let goTo) = place else { break }
            return MenuRow(id: "menuGoTo", title: String(localized: "Go to \(goTo.name)"), icon: goTo.symbol,
                           action: goTo.action)
        case .download:
            let has = actions.hasDownload
            return MenuRow(id: "menuDownload", title: has ? Verbs.removeDownload : Verbs.download,
                           icon: has ? Icons.removeDownload : Icons.download, isDestructive: has,
                           action: actions.toggleDownload)
        case .favorite:
            let isFavorite = actions.isFavorite
            return MenuRow(id: "menuFavorite", title: isFavorite ? Verbs.removeFromFavorites : Verbs.addToFavorites,
                           icon: isFavorite ? Icons.unfavorite : Icons.favorite, action: actions.toggleFavorite)
        case .move:
            return MenuRow(id: "menuMove", title: offersSave ? Verbs.saveToFolder : Verbs.moveTo, icon: Icons.move,
                           action: actions.saveToFolder)
        case .finished:
            let isFinished = page?.finishedAt != nil
            return MenuRow(id: "menuFinished", title: isFinished ? Verbs.markUnfinished : Verbs.markFinished,
                           icon: isFinished ? Icons.markUnfinished : Icons.markFinished) {
                if let page { library.setFinished([page], !isFinished) }
            }
        case .playback:
            return MenuRow(id: "menuPlayback", title: Verbs.playback, icon: Icons.playback)
        case .markAllAbove:
            return MenuRow(id: "menuMarkAllAbove", title: Verbs.markAllAboveFinished, icon: Icons.markAllAboveFinished) {
                if let page { library.markAllAbove(page) }
            }
        case .skip:
            // A waiting chapter too: one whose text can't be had is skipped so playback goes past it.
            let skips = page?.skipsInPlayback == true
            return MenuRow(id: "menuSkip", title: skips ? Verbs.playInPlayback : Verbs.skipInPlayback,
                           icon: skips ? Icons.includeInPlayback : Icons.skipInPlayback) {
                if let page { library.toggleSkipsInPlayback(page) }
            }
        case .share:
            return MenuRow(id: "menuShare", title: Verbs.share, icon: Icons.share, action: actions.share)
        case .save:
            return MenuRow(id: "menuSave", title: offersSave ? Verbs.saveToLibrary : Verbs.removeFromLibrary,
                           icon: offersSave ? Icons.save : Icons.unsave, isDestructive: !offersSave,
                           action: actions.toggleSaved)
        case .removeFromRecent:
            // The same remove as the Library's (`LibraryStore.remove`): in no list after, the star kept.
            return MenuRow(id: "menuRemoveFromRecent", title: Verbs.removeFromRecent, icon: Icons.removeFromRecent,
                           isDestructive: true, action: actions.remove)
        case .stopListening:
            guard case .bar(let onStop) = place else { break }
            return MenuRow(id: "menuStopListening", title: Verbs.stopListening, icon: Icons.stop) { onStop?() }
        case .removeFromHistory:
            guard case .history(let onRemove) = place else { break }
            return MenuRow(id: "menuRemoveFromHistory", title: Verbs.removeFromHistory, icon: Icons.delete,
                           isDestructive: true, action: onRemove)
        default: break
        }
        return MenuRow(id: option.rawValue, title: option.rawValue, icon: nil)
    }

    /// A list row's swipe, without building the menu: *Remove from Library* in the Library,
    /// *Remove from Recent* out of it (the menu's own rows, the same action). Cheap: it reads
    /// only the page's flags; the action is made when the swipe runs.
    static func swipe(for page: Page, actions: @escaping () -> PageActions) -> MenuRow? {
        let inLibrary = page.isInLibrary
        guard inLibrary || page.lastPlayedAt != nil else { return nil }
        return MenuRow(id: inLibrary ? "menuSave" : "menuRemoveFromRecent",
                       title: inLibrary ? Verbs.removeFromLibrary : Verbs.removeFromRecent,
                       icon: inLibrary ? Icons.unsave : Icons.removeFromRecent, isDestructive: true) {
            let made = actions()
            inLibrary ? made.toggleSaved() : made.remove()
        }
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
        return MenuContext(item: PageMenu(actions: self, place: place).rows, screen: MenuContext.screenRows(at: place.registryPlace, shell: shell),
                           tiles: MenuContext.tiles(shell, last: website), isOnReadingPage: true)
    }
}
