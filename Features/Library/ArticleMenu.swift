import SwiftUI

/// A page's menu: the one definition every way to a page's menu renders (decisions C4, C98), as a
/// row's ⋯ and long press (`MenuRows`, through this view) and as the item block of the ⋯ panel
/// (`rows`). Which options show where, in what order and greyed or not is `MenuRegistry`'s
/// (docs/MENUS.md); this gives each its title, symbol and action. Built only when the menu opens:
/// rows pass this view, never its `rows`, so nothing here runs on a row's redraw.
struct ArticleMenu: View {
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

    let actions: ArticleActions
    let place: Place

    var body: some View {
        MenuRows(blocks: blocks)
    }

    var rows: [MenuRow] { blocks.flatMap { $0 } }

    /// The page's state as the registry reads it.
    var facts: MenuRegistry.Facts {
        let article = actions.article
        var facts = MenuRegistry.Facts()
        facts.hasTarget = article != nil || actions.url != nil
        facts.hasPage = article != nil
        facts.inLibrary = actions.isInLibrary
        facts.isSaved = actions.isSaved
        facts.offersSave = actions.offersSave
        facts.canSave = actions.canSave
        facts.inFolder = article?.folder != nil
        facts.canPlay = actions.isSaved || article?.isWaitingChapter == true
        facts.canFavorite = actions.canFavorite
        facts.hasVoices = true // C138a: every article has a voice (an Apple one too)
        facts.hasShareURL = actions.shareURL != nil
        facts.inRecent = !facts.inLibrary && article.map(LibraryQueries.isInRecent) == true
        if case .nowPlaying(let goTo) = place { facts.goToEnabled = goTo.availability == .enabled }
        if case .bar(let onStop) = place { facts.isLoaded = onStop != nil }
        return facts
    }

    var blocks: [[MenuRow]] {
        MenuRegistry.blocks(.article, at: place.registryPlace, facts, row: row)
    }

    private func row(_ option: MenuRegistry.Option) -> MenuRow {
        let article = actions.article
        let library = actions.libraryActions
        let offersSave = actions.offersSave
        switch option {
        case .read:
            return MenuRow(id: "menuRead", title: Verbs.read, icon: Icons.reader, action: actions.read)
        case .goTo:
            guard case .nowPlaying(let goTo) = place else { break }
            return MenuRow(id: "menuGoTo", title: String(localized: "Go to \(goTo.name)"), icon: goTo.symbol,
                           action: goTo.action)
        case .prepare:
            let has = actions.hasPrepare
            return MenuRow(id: "menuPrepare", title: has ? Verbs.removePrepare : Verbs.prepare,
                           icon: has ? Icons.removePrepare : Icons.prepare, isDestructive: has,
                           action: actions.togglePrepare)
        case .voice:
            let tts = actions.speech.localTTS
            let name = article.map { tts.voiceName(of: tts.effectiveSelection(of: $0.listenKey)) }
            return MenuRow(id: "menuVoice", title: name.map(Verbs.voiceRow) ?? Verbs.voice, icon: Icons.voice) {
                if let article { actions.shell.present(.voice(.article(article.listenKey))) }
            }
        case .favorite:
            let isFavorite = actions.isFavorite
            return MenuRow(id: "menuFavorite", title: isFavorite ? Verbs.removeFromFavorites : Verbs.addToFavorites,
                           icon: isFavorite ? Icons.unfavorite : Icons.favorite, action: actions.toggleFavorite)
        case .move:
            return MenuRow(id: "menuMove", title: offersSave ? Verbs.saveToFolder : Verbs.moveTo, icon: Icons.move,
                           action: actions.saveToFolder)
        case .finished:
            let isFinished = article?.finishedAt != nil
            return MenuRow(id: "menuFinished", title: isFinished ? Verbs.markUnfinished : Verbs.markFinished,
                           icon: isFinished ? Icons.markUnfinished : Icons.markFinished) {
                if let article { library.setFinished([article], !isFinished) }
            }
        case .playback:
            return MenuRow(id: "menuPlayback", title: Verbs.playback, icon: Icons.playback)
        case .markAllAbove:
            return MenuRow(id: "menuMarkAllAbove", title: Verbs.markAllAboveFinished, icon: Icons.markAllAboveFinished) {
                if let article { library.markAllAbove(article) }
            }
        case .skip:
            // A waiting chapter too: one whose text can't be had is skipped so playback goes past it.
            let skips = article?.skipsInPlayback == true
            return MenuRow(id: "menuSkip", title: skips ? Verbs.playInPlayback : Verbs.skipInPlayback,
                           icon: skips ? Icons.includeInPlayback : Icons.skipInPlayback) {
                if let article { library.toggleSkipsInPlayback(article) }
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
    static func swipe(for article: Article, actions: @escaping () -> ArticleActions) -> MenuRow? {
        let inLibrary = article.isInLibrary
        guard inLibrary || article.lastPlayedAt != nil else { return nil }
        return MenuRow(id: inLibrary ? "menuSave" : "menuRemoveFromRecent",
                       title: inLibrary ? Verbs.removeFromLibrary : Verbs.removeFromRecent,
                       icon: inLibrary ? Icons.unsave : Icons.removeFromRecent, isDestructive: true) {
            let made = actions()
            inLibrary ? made.toggleSaved() : made.remove()
        }
    }
}

extension ArticleActions {
    /// The ⋯ panel of the Reader and Now Playing (decision D24, C140): the page's menu, then
    /// *Prepared Audio*, then `[Settings][Saved][Reader]`. Reader is disabled: already reading.
    /// Website is reachable via Share in the article's own menu rows.
    func readingPageMenu(_ place: ArticleMenu.Place) -> MenuContext {
        let reader = MenuRow(id: "moreReader", title: Verbs.reader, icon: Icons.reader,
                             availability: .disabled,
                             accessibilityHint: String(localized: "Already in the Reader"))
        return MenuContext(item: ArticleMenu(actions: self, place: place).rows,
                           screen: MenuContext.screenRows(at: place.registryPlace, shell: shell),
                           tiles: MenuContext.tiles(shell, last: reader), isOnReadingPage: true)
    }
}
