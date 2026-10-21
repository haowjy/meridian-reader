import SwiftUI

/// A folder's menu (a book or series as any other): the one definition its row's ⋯ and long press,
/// its header's *More* and its Favorites tile render (decisions C4, C98). Which options show
/// where, in what order and greyed or not is `MenuRegistry`'s (docs/MENUS.md); this gives each its
/// title, symbol and action. Built only when the menu opens: a row passes this view, never its
/// `rows`, so nothing here runs on a row's redraw.
///
/// The row's one prepare option: *Prepare* (the toggle off, nothing prepared), *Turn Off
/// Prepare* (toggle on, still to finish), *Remove Prepared audio* (all prepared, red). *Turn Off
/// Prepare* asks first (`onTurnOffPrepare`, by the control the menu opened from), then turns it
/// off and keeps what is prepared. *Remove Prepared audio* deletes its pages' audio and keeps them
/// out of its prepare (P8). *Edit Details…* holds the name too (no *Rename…*). Delete asks
/// through `LibraryScreenState`'s dialogs, which the screen hosts.
struct FolderMenu: View {
    enum Place {
        case row, tile, header
        var registryPlace: MenuRegistry.Place {
            switch self {
            case .row: .row
            case .tile: .tile
            case .header: .header
            }
        }
    }

    let folder: Folder
    /// Its pages in play order (what its row or screen already holds).
    let articles: [Article]
    let actions: LibraryActions
    let preparedAudio: PrepareCenter
    let screen: LibraryScreenState
    var place: Place = .row
    /// What its row or header already computed; nil: computed here.
    var progress: FolderProgress?
    /// *Turn Off Prepare*: its host asks `turnOffPrepareQuestion` by the control the menu
    /// opened from (a row's ⋯, the header's *More*).
    let onTurnOffPrepare: () -> Void
    /// After *Move to…* is saved (the folder's own screen shows it where it went).
    var onMoved: () -> Void = {}

    static let deleteRowID = "menuDeleteFolder"

    var body: some View {
        if place == .header {
            // More: the folder's rows, then the create group into this folder (C126), and
            // Delete Folder alone at the bottom, as everywhere else it is the last row (C130).
            let all = rows
            let delete = all.filter { $0.id == Self.deleteRowID }
            MenuRows(blocks: [all.filter { $0.id != Self.deleteRowID },
                              LibraryCreateMenu(library: actions.library, shell: actions.shell, follow: actions.follow,
                                                screen: screen, folder: folder).rows, delete])
        } else {
            MenuRows(rows)
        }
    }

    /// The folder's state as the registry reads it.
    var facts: MenuRegistry.Facts {
        var facts = MenuRegistry.Facts()
        facts.hasArticlesToPlay = (progress ?? actions.progress(of: folder, articles: articles)).hasArticlesToPlay
        facts.hasArticles = !articles.isEmpty
        facts.prepareIsOn = preparedAudio.isOn(folder)
        facts.hasPreparedAudio = preparedAudio.hasPreparedAudio(folder, articles: articles)
        facts.isFixedOrder = folder.kind.isBookOrSeries
        facts.isBookOrSeries = folder.kind.isBookOrSeries
        facts.hasVoices = true // C138a: every article has a voice (an Apple one too)
        return facts
    }

    var rows: [MenuRow] {
        let facts = facts
        return MenuRegistry.rows(.folder, at: place.registryPlace, facts) { row($0, facts) }
    }

    private func row(_ option: MenuRegistry.Option, _ facts: MenuRegistry.Facts) -> MenuRow {
        let shell = actions.shell
        switch option {
        case .continueFolder:
            return MenuRow(id: "menuContinue", title: Verbs.continue, icon: Icons.play) { actions.playFolder(folder) }
        case .playFromStart:
            return MenuRow(id: "menuPlayFromStart", title: Verbs.playFromStart, icon: Icons.previous) {
                actions.playFolderFromStart(folder)
            }
        case .folderPrepare:
            let state = preparedAudio.state(of: folder, articles: articles)
            if facts.prepareIsOn && state != .prepared {
                return MenuRow(id: "menuPrepare", title: Verbs.turnOffPrepare, icon: Icons.turnOffPrepare,
                               action: onTurnOffPrepare)
            }
            if state == .prepared || (!facts.prepareIsOn && facts.hasPreparedAudio) {
                return removePreparedAudio
            }
            return MenuRow(id: "menuPrepare", title: Verbs.prepare, icon: Icons.prepare) {
                PrepareActions(preparedAudio: preparedAudio, shell: shell).prepare(folder)
            }
        case .removePreparedAudio:
            return removePreparedAudio
        case .folderVoice:
            let tts = actions.speech.localTTS
            let selection = folder.voiceID.flatMap(VoiceSelection.init(stored:)) ?? tts.defaultSelection
            return MenuRow(id: "menuVoice", title: Verbs.voiceRow(tts.voiceName(of: selection)),
                           icon: Icons.voice) { shell.present(.voice(.folder(folder.id))) }
        case .folderFavorite:
            let isFavorite = folder.isFavorite
            return MenuRow(id: "menuFavorite", title: isFavorite ? Verbs.removeFromFavorites : Verbs.addToFavorites,
                           icon: isFavorite ? Icons.unfavorite : Icons.favorite) {
                FavoriteFlow(library: actions.library, shell: shell).toggle(folder)
            }
        case .folderMove:
            return MenuRow(id: "menuMove", title: Verbs.moveTo, icon: Icons.move) {
                actions.move([.folder(folder)], onMoved: onMoved)
            }
        case .editDetails:
            return MenuRow(id: "menuEditDetails", title: Verbs.editDetails, icon: Icons.editDetails) {
                shell.present(.folderDetails(folder.id))
            }
        default:
            return MenuRow(id: Self.deleteRowID, title: Verbs.deleteFolder(isBook: folder.kind == .book),
                           icon: Icons.delete, isDestructive: true) { screen.confirmDelete([folder]) }
        }
    }

    private var removePreparedAudio: MenuRow {
        MenuRow(id: "menuRemovePreparedAudio", title: Verbs.removePreparedAudio, icon: Icons.removePrepare,
                isDestructive: true) { preparedAudio.deletePreparedAudio(of: folder) }
    }

    /// A row's swipe, without building the menu: the menu's *Delete Folder…* (it asks first).
    static func swipe(for folder: Folder, screen: LibraryScreenState) -> MenuRow {
        MenuRow(id: Self.deleteRowID, title: Verbs.deleteFolder(isBook: folder.kind == .book), icon: Icons.delete,
                isDestructive: true) { screen.confirmDelete([folder]) }
    }
}
