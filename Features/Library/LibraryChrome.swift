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
    let follow: FollowCenter
    let screen: LibraryScreenState
    let topLevelSort: Binding<String>
    /// *Stop Preparing* asked from the ⋯: the question shows by it.
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
        menu.screen = screenMenu.createRows + menu.screen
        return menu
    }

    /// Library Read's menu (its top group's ⋯ and a press and hold on the field's reader icon): the
    /// page's own menu (`ArticleMenu` where the page is open, its *Save* group first), then the
    /// Library's rows (`compactMenu`).
    func readingMenu(_ article: ReaderArticle) -> [[MenuRow]] {
        let page = library.article(key: article.id, canonicalURL: article.origin.canonicalURL)
        let actions = ArticleActions(article: page, readerArticle: article, library: library, shell: shell,
                                     speech: speech, preparedAudio: preparedAudio, follow: follow)
        return ArticleMenu(actions: actions, place: .open).blocks + compactMenu.blocks
    }

    /// What the folded chrome's bubble names: the folder on top, else the home's tab (Library, History).
    /// Library Read never folds.
    var bubbleTitle: String {
        let name = screenMenu.topFolder?.name
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
                // Reading a page in place: the lit reader icon and the page's site, as the Browser's reader mode field.
                if let article = shell.libraryReader {
                    return AnyView(LibraryReaderField(article: article, menu: readingMenu(article),
                                                      openPage: article.origin.url.map { url in { shell.openWebsite(url) } }))
                }
                return AnyView(SearchField(text: Binding(get: { search.text }, set: { search.text = $0 }), prompt: searchPrompt,
                                    focus: focus, fieldIdentifier: "librarySearchField", onSubmit: search.lowerKeyboard))
            },
            bubbleTitle: bubbleTitle,
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
/// rows in the same order as the chrome's ⋯ had (`compactMenu`). *Stop Preparing* asks by it.
/// `face`: how it is drawn (the title's glyph, or the bare symbol in a toolbar).
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

/// The Library's Read, row 1's field: the lit reader icon where the Browser's reader mode has it, then
/// the page's site, the rest of the field. A tap on the icon opens the article's live page in the
/// Browser; a press and hold opens the screen's menu, the top group's ⋯. A page with no web address
/// (a book's chapter, pasted text) has none to open: the icon's tap opens the menu, and it reads as *More*. Listening starts from the top group's ▶ Listen.
private struct LibraryReaderField: View {
    let article: ReaderArticle
    let menu: [[MenuRow]]
    let openPage: (() -> Void)?

    var body: some View {
        AddressField(reader: .showing, holdMenu: menu, onOpenReader: openPage) {
            Text(article.sourceLabel)
                .lineLimit(1)
                .truncationMode(.middle)
        } accessory: {
            EmptyView()
        }
    }
}
