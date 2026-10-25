import SwiftUI

/// What the Library hands the shell's bottom chrome: its screen state (Edit's selection, the
/// dialogs), the ⋯ menu of the screen on top, the search prompt. Built by the shell
/// (`BrowseStartView`), which owns the chrome, and shared with `LibrarySurface`, which draws the
/// screens.
@MainActor
struct LibraryChrome {
    let shell: ShellState
    let library: LibraryStore
    let speech: SpeechController
    let preparedAudio: PrepareCenter
    let screen: LibraryScreenState
    let topLevelSort: Binding<String>
    /// *Turn Off Prepare* asked from the ⋯: the question shows by it.
    let turningOff: Binding<Folder?>

    var search: SearchSession { shell.librarySearch }

    var screenMenu: LibraryScreenMenu {
        LibraryScreenMenu(library: library, speech: speech, shell: shell, preparedAudio: preparedAudio, screen: screen,
                          top: shell.libraryPath.last, topLevelSort: topLevelSort,
                          showMoved: { shell.libraryPath = library.path(to: $0) },
                          onTurnOffPrepare: { turningOff.wrappedValue = $0 })
    }

    /// The field names what it searches, or would: the folder its search began on, else the
    /// folder screen on top, else the home's tab.
    var searchPrompt: String {
        let folder = search.isActive ? shell.librarySearchFolder.flatMap(library.folder(id:)) : screenMenu.topFolder
        return folder.map { LibraryHomeTab.searchPrompt(naming: $0.name) } ?? shell.homeTab.searchPrompt
    }

    /// The compact ⋯: the screen's menu, with what the old toolbar's ＋ did as rows of it
    /// (*New Folder…*, *Import from…*, *Paste Text…*), so they stay one tap from ⋯.
    var compactMenu: MenuContext {
        var menu = screenMenu.menu(compact: true)
        // Favorites only lists starred items; nothing is created there (C150).
        let creates = !(shell.libraryPath.isEmpty && shell.homeTab == .favorites)
        menu.screen = (creates ? screenMenu.createRows : []) + menu.screen
        return menu
    }

    /// The Library as the chrome host draws it: the search field, ⋯, Edit's bar.
    func chromeScreen() -> ChromeScreen {
        let search = search
        return ChromeScreen(
            destination: .library,
            session: search,
            cancelID: "librarySearchCancel",
            onCancel: shell.endLibrarySearch,
            begin: shell.beginLibrarySearch,
            canGoBack: false,
            canGoForward: false,
            field: { focus in
                AnyView(SearchField(text: Binding(get: { search.text }, set: { search.text = $0 }), prompt: searchPrompt,
                                    focus: focus, fieldIdentifier: "librarySearchField", onSubmit: search.lowerKeyboard))
            },
            more: AnyView(MoreMenuButton(id: "libraryMore", chrome: true) { compactMenu }
                .turnOffPrepareQuestion(turningOff)),
            editBar: screen.isEditing ? AnyView(LibraryEditBar()) : nil
        )
    }
}
