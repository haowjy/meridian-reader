#if DEBUG
import SwiftUI
import SwiftData

/// What the probe panel shows: a menu's production rows, for a screenshot. A native menu can't be
/// opened from code, so the panel lists the rows a tap on that ⋯ would show (`MenuRows` over the
/// same `MenuContext`), with the same actions.
@MainActor @Observable
final class MenuProbeState {
    static let shared = MenuProbeState()
    var blocks: [[MenuRow]]?
    /// `-openPageMenu`: the first reading page shown offers its ⋯ menu (`offerPageMenu`).
    var wantsPageMenu = false

    /// A reading page's ⋯ blocks, the same `MenuRows` input its own ⋯ draws, shown 3 s after the
    /// page appears; only the first page offered while `-openPageMenu` is on.
    func offerPageMenu(_ make: @escaping @MainActor () -> [[MenuRow]]) {
        guard wantsPageMenu else { return }
        wantsPageMenu = false
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            blocks = make()
        }
    }
}

struct MenuProbePanel: View {
    @State private var state = MenuProbeState.shared

    var body: some View {
        if let blocks = state.blocks {
            List { MenuRows(blocks: blocks) }
                .frame(width: 320, height: 560)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                .shadow(radius: 12)
                .accessibilityIdentifier("menuProbePanel")
        }
    }
}

/// Fills the probe panel with the production menu rows for offline screenshot probes.
@MainActor
enum MenuProbe {
    static func open(_ name: String, library: LibraryStore, speech: SpeechController,
                     shell: ShellState, follow: FollowCenter, preparedAudio: PrepareCenter) {
        let screen = LibraryScreenState()
        let articles = (try? library.context.fetch(FetchDescriptor<Article>()))?.filter(\.isLive) ?? []
        let folders = (try? library.context.fetch(LibraryQueries.folders))?.filter(\.isLive) ?? []
        let saved = articles.first { $0.isSavedToLibrary }
        let unsaved = articles.first { !$0.isInLibrary && LibraryQueries.isInRecent($0) }
        let folder = shell.libraryPath.last.flatMap { route -> Folder? in
            if case .folder(let id) = route { return library.folder(id: id) }
            return nil
        } ?? folders.first { $0.kind.isBookOrSeries } ?? folders.first
        let libraryActions = LibraryActions(library: library, speech: speech, shell: shell, follow: follow)
        func actions(_ article: Article?, reader: ReaderArticle? = nil, url: URL? = nil) -> ArticleActions {
            ArticleActions(article: article, readerArticle: reader, url: url, library: library,
                           shell: shell, speech: speech, preparedAudio: preparedAudio, follow: follow)
        }
        let context: MenuContext
        switch name {
        case "library", "folderScreen", "create", "editCreate":
            let top = name == "folderScreen" ? folder.map { LibraryRoute.folder($0.id) } : nil
            if name == "create" || name == "editCreate" {
                let rows = LibraryCreateMenu(library: library, shell: shell, follow: follow, screen: screen,
                                             folder: folder, place: name == "create" ? .add : .edit).rows
                context = MenuContext(screen: rows, tiles: [])
            } else {
                context = LibraryScreenMenu(library: library, speech: speech, shell: shell,
                                            follow: follow, screen: screen,
                                            top: top, topLevelSort: Binding(
                                                get: { LibraryTopLevel.sort.rawValue },
                                                set: { LibraryTopLevel.sort = ArticleSort(rawValue: $0) ?? .newest })).menu(compact: true)
            }
        case "folderRow", "folderHeader":
            guard let folder else { return missing(name, "seed a folder") }
            let menu = FolderMenu(folder: folder, articles: library.articles(in: folder), actions: libraryActions,
                                  preparedAudio: preparedAudio, screen: screen,
                                  place: name == "folderRow" ? .row : .header, onTurnOffPrepare: {})
            context = MenuContext(item: menu.rows, screen: [], tiles: [])
        case "article", "historyArticle", "bar":
            guard let article = name == "historyArticle" ? unsaved : saved else {
                return missing(name, name == "historyArticle" ? "use -seedPlayedPages 1" : "use -seedDemoArticle")
            }
            let place: ArticleMenu.Place = name == "bar" ? .bar(onStop: { speech.stop() }) : .list
            context = MenuContext(item: ArticleMenu(actions: actions(article), place: place).rows, screen: [], tiles: [])
        case "historyVisit":
            guard let visit = try? library.context.fetch(FetchDescriptor<RecentVisit>()).first else {
                return missing(name, "use -seedHistory")
            }
            let menu = ArticleMenu(actions: actions(visit.url.flatMap { library.article(url: $0) }, url: visit.url),
                                   place: .history(onRemove: { library.removeVisit(visit) }))
            context = MenuContext(item: menu.rows, screen: [], tiles: [])
        case "browser", "reader":
            let reader = shell.libraryReader ?? shell.pageReader ?? saved.map { ReaderArticle(article: $0) }
            let article = reader.flatMap { library.article(key: $0.id, canonicalURL: $0.origin.canonicalURL) }
            let pageActions = actions(article, reader: reader, url: shell.web.currentURL)
            let place: ArticleMenu.Place = name == "browser" ? .browser : .open
            let tail = name == "browser" ? MenuContext.screenRows(at: .browser, shell: shell) : []
            context = MenuContext(item: ArticleMenu(actions: pageActions, place: place).rows,
                                  screen: tail, tiles: [])
        case "prepared":
            let overview = preparedAudio.pageOverview
            guard let item = (overview.now + overview.waiting + overview.done + overview.differentVoice).first else {
                return missing(name, "prepare a seeded folder with -prepareFolder")
            }
            let rows = PrepareMenu(item: item, preparedAudio: preparedAudio, library: library).rows
            context = MenuContext(item: rows, screen: [], tiles: [])
        default:
            return missing(name, "unknown menu")
        }
        let rows = context.item + context.screen + context.tiles
        ListenTimingLog.log("menu_probe", ["name": name,
                            "rows": rows.map { "\($0.group):\($0.title):\($0.availability)" }.joined(separator: " | ")], console: true)
        MenuProbeState.shared.blocks = context.blocks
    }

    private static func missing(_ name: String, _ reason: String) {
        ListenTimingLog.log("menu_probe_missing", ["name": name, "reason": reason], console: true)
    }
}
#endif
