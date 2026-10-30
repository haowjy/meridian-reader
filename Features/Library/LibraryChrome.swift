import SwiftUI

/// What the Library hands the shell's bottom chrome: its screen state (Edit's selection, the
/// dialogs), the search prompt; and the ⋯ menu of the screen on top, which its title line draws
/// on compact width (`LibraryTitleMenu`). Built by the shell (`BrowseStartView`), which owns the
/// chrome, and shared with `LibrarySurface`, which draws the screens.
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

    /// The compact ⋯ on the title line: the screen's menu, with what regular width's ＋ does as rows
    /// of it (*New Folder…*, *Import from…*, *Paste Text…*).
    var compactMenu: MenuContext {
        var menu = screenMenu.menu(compact: true)
        // Favorites only lists starred items; nothing is created there (C150).
        let creates = !(shell.libraryPath.isEmpty && shell.homeTab == .favorites)
        menu.screen = (creates ? screenMenu.createRows : []) + menu.screen
        return menu
    }

    /// What the folded chrome's strip names: the article being read in place, else the folder on top, else the
    /// home's tab (Library, Favorites, Recent).
    var stripTitle: String {
        let name: String?
        if let article = shell.libraryReader { name = article.title ?? article.sourceLabel } else { name = screenMenu.topFolder?.name }
        return name.flatMap { $0.isEmpty ? nil : $0 } ?? shell.homeTab.title
    }

    /// The Library as the chrome host draws it: the search field, Edit's bar.
    func chromeScreen() -> ChromeScreen {
        let search = search
        return ChromeScreen(
            session: search,
            cancelID: "librarySearchCancel",
            onCancel: shell.endLibrarySearch,
            begin: shell.beginLibrarySearch,
            // Reading a page in place: ‹ puts the Library back.
            canGoBack: shell.libraryReader != nil,
            canGoForward: false,
            backID: "libraryReaderBack",
            onBack: shell.closeLibraryReader,
            field: { focus in
                // Reading a page in place: Aa and the page's site, as the Browser's reader mode shows its page.
                if let article = shell.libraryReader { return AnyView(LibraryReaderField(article: article)) }
                return AnyView(SearchField(text: Binding(get: { search.text }, set: { search.text = $0 }), prompt: searchPrompt,
                                    focus: focus, fieldIdentifier: "librarySearchField", onSubmit: search.lowerKeyboard))
            },
            stripTitle: stripTitle,
            editBar: screen.isEditing ? AnyView(LibraryEditBar()) : nil
        )
    }
}

extension EnvironmentValues {
    /// The Library's chrome on compact width, for its title lines' ⋯ (nil on regular width, where
    /// the dock has ⋯).
    @Entry var libraryChrome: LibraryChrome?
}

/// The ⋯ on a Library screen's title line (compact width): the menu of the screen on top, the same
/// rows in the same order as the chrome's ⋯ had (`compactMenu`). *Turn Off Prepare* asks by it.
/// `face`: how it is drawn (the title's glyph; a glass circle over Library Read's text).
struct LibraryTitleMenu<Face: View>: View {
    @ViewBuilder var face: Face

    @Environment(\.libraryChrome) private var chrome

    var body: some View {
        if let chrome {
            TitleMenuButton(id: "libraryMore", blocks: chrome.compactMenu.blocks) { face }
                .turnOffPrepareQuestion(chrome.turningOff)
        }
    }
}

extension LibraryTitleMenu where Face == TitleMenuGlyph {
    init() { self.init { TitleMenuGlyph() } }
}

/// The Library's Read, row 1's field: Aa (the text appearance panel) and the page's site, as the
/// Browser's reader mode shows Aa with its address. Listening starts from the heading's ▶ Listen.
private struct LibraryReaderField: View {
    let article: ReaderArticle

    @Environment(\.readingPalette) private var reading

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            TextAppearanceControl(arrowEdge: .bottom)
            Text(article.sourceLabel)
                .typeStyle(.row)
                .foregroundStyle(reading?.ink ?? Palette.ink)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .bottomChromeField(leading: Spacing.xxs, trailing: Spacing.s)
    }
}
