import Foundation

/// Every menu option in the app, each defined once (C98, docs/MENUS.md). An option says where it
/// can ever apply (its item kind, the places it shows in, and `applies`, a fact of the item that
/// no state change in that place undoes) and when it can run now (`enabled`). Outside where it
/// applies it is hidden; where it applies but can't run now it is greyed out (DR-09 as refined
/// by C98: grey when some other state could make it usable there, hidden when nothing could).
/// Every menu (a row's ⋯ and long press, a folder header's *More*, the ⋯ panels, the Prepared audio
/// rows, the Now Playing bar, History) is assembled from here by kind and place; the renderer
/// only adds each option's title, symbol and action (`MenuRegistry.rows`). Pure values, so the
/// table test (`MenuRegistryTests`) checks every kind × place × state.
enum MenuRegistry {
    /// What a menu is for.
    enum Kind: String, CaseIterable { case article, folder, prepare, screen }

    /// Where a menu opens.
    enum Place: String, CaseIterable {
        /// A Library list row's ⋯ and long press (every tab, search, a folder's screen).
        case row
        /// A Favorites tile on the start page.
        case tile
        /// The Now Playing bar's long press.
        case bar
        /// A History visit.
        case history
        /// The Reader's ⋯ panel.
        case reader
        /// Now Playing's ⋯ panel.
        case nowPlaying
        /// The browser's ⋯ panel.
        case browser
        /// A folder header's *More*.
        case header
        /// The Library home's ⋯ panel.
        case libraryHome
        /// A folder screen's ⋯ panel.
        case folderScreen
        /// A Prepared Audio list row.
        case preparedAudio
        /// The Library's ＋ (the home or a folder's screen).
        case add
        /// A folder screen's bottom bar in Edit.
        case edit
    }

    /// Every option, in menu order within its kind.
    enum Option: String, CaseIterable {
        // A page
        case read, goTo, prepare, voice, favorite, move, finished, playback, markAllAbove, skip, share, save,
             removeFromRecent, stopListening, removeFromHistory
        // A folder, book or series
        case continueFolder, playFromStart, folderPrepare, removePreparedAudio, folderVoice, folderFavorite, folderMove,
             editDetails, deleteFolder
        // A prepare
        case reprepare, removePrepare
        // A screen's own rows
        case newFolder, importFile, pasteText, follow, sort, reload, preparedAudio, history, settings
        // The Prepared Audio list's own ⋯ (C135)
        case deleteAllPrepared, clearListeningAudio
    }

    /// The item's state as a menu needs it: plain values its host already has (no fetch, no disk).
    struct Facts: Equatable {
        // A page
        var hasTarget = true
        /// A page model exists (played, saved or a link), not only a page in the browser.
        var hasPage = false
        var goToEnabled = true
        var inLibrary = false
        var isSaved = false
        var offersSave = false
        var canSave = false
        var inFolder = false
        var canPlay = false
        var canFavorite = false
        var hasShareURL = false
        var inRecent = false
        var isLoaded = false
        // A folder
        var hasArticlesToPlay = false
        var hasArticles = false
        var prepareIsOn = false
        var hasPreparedAudio = false
        /// A book or series: one voice for every chapter (C138).
        var isBookOrSeries = false
        /// An on-device voice speaks (Kokoro): *Voice* can pick one (C138).
        var hasVoices = false
        // A prepare
        var isQueued = false
        /// A row of From Listening: audio made while listening, not prepared (C135).
        var isListeningAudio = false
        // The Prepared Audio list
        var hasPrepared = false
        var hasListeningAudio = false
        // A screen
        var hasWebPage = false
        /// *Follow…* can run (the browser: a web page is up).
        var canFollow = true
        /// The compact chrome draws the ⋯, and it has no 🕘 button: *History* is a row.
        var compact = false
        /// Kept for menu compatibility; always false since C149.
        var isFixedOrder = false
    }

    struct Spec {
        let option: Option
        let kind: Kind
        /// The places it can ever show in.
        let places: Set<Place>
        /// A sub-option: shows inside this option's submenu.
        var parent: Option?
        /// Its block: block 1 comes after block 0, set apart by a divider.
        var block = 0
        /// The item can ever take it (false: hidden).
        var applies: (Facts) -> Bool = { _ in true }
        /// It can run now (false: greyed out).
        var enabled: (Facts) -> Bool = { _ in true }
        /// For the table (docs/MENUS.md): when it is hidden in its places, and when greyed.
        var hiddenIf = ""
        var greyIf = ""
    }

    /// One shown option: whether it runs now, and its submenu's options.
    struct Entry: Equatable {
        let option: Option
        let availability: MenuAvailability
        var children: [Entry] = []
        var block = 0
    }

    private static let articlePlaces: Set<Place> = [.row, .tile, .bar, .history, .reader, .nowPlaying, .browser]
    /// Where a page isn't on screen with its own bookmark: *Read* and *Save* show there.
    private static let articleListPlaces: Set<Place> = [.row, .tile, .bar, .history]
    private static let folderPlaces: Set<Place> = [.row, .tile, .header]
    private static let panelPlaces: Set<Place> = [.libraryHome, .folderScreen, .browser, .reader, .nowPlaying]

    static let specs: [Spec] = [
        // A page. The row's tap plays it; Edit is on screen; the Reader, Now Playing and the
        // browser have the bookmark, so *Save* isn't in their menus.
        Spec(option: .read, kind: .article, places: articleListPlaces, enabled: { $0.hasTarget }, greyIf: "no page or address"),
        Spec(option: .goTo, kind: .article, places: [.nowPlaying], enabled: { $0.goToEnabled }, greyIf: "nowhere to go"),
        Spec(option: .prepare, kind: .article, places: articlePlaces, enabled: { $0.inLibrary || ($0.hasPage && $0.canSave) }, greyIf: "nothing to save yet (downloading saves it, C104)"),
        // C138: the voice it speaks in (its book's for a chapter); picking one remakes its audio.
        Spec(option: .voice, kind: .article, places: articlePlaces, applies: { $0.hasPage }, enabled: { $0.hasVoices },
             hiddenIf: "no page (a page in the browser only)", greyIf: "Apple's voice is selected"),
        Spec(option: .favorite, kind: .article, places: articlePlaces, enabled: { $0.canFavorite }, greyIf: "it can\u{2019}t be starred"),
        Spec(option: .move, kind: .article, places: articlePlaces, enabled: { !$0.offersSave || $0.canSave }, greyIf: "nothing to save yet"),
        Spec(option: .finished, kind: .article, places: articlePlaces, enabled: { $0.isSaved }, greyIf: "not saved"),
        // Chapter-only and rare: one submenu, only for a page in a folder.
        Spec(option: .playback, kind: .article, places: articlePlaces, applies: { $0.inFolder }, enabled: { $0.canPlay }, hiddenIf: "not in a folder", greyIf: "neither row inside can run"),
        Spec(option: .markAllAbove, kind: .article, places: [.row], parent: .playback,
             applies: { $0.inFolder }, enabled: { $0.isSaved }, hiddenIf: "not in a folder; outside a list row", greyIf: "not saved"),
        Spec(option: .skip, kind: .article, places: articlePlaces, parent: .playback,
             applies: { $0.inFolder }, enabled: { $0.canPlay }, hiddenIf: "not in a folder", greyIf: "not saved and not a waiting chapter"),
        Spec(option: .share, kind: .article, places: articlePlaces, applies: { $0.hasShareURL }, hiddenIf: "no web address"),
        Spec(option: .save, kind: .article, places: articleListPlaces, enabled: { !$0.offersSave || $0.canSave }, greyIf: "nothing to save yet"),
        Spec(option: .removeFromRecent, kind: .article, places: articlePlaces,
             applies: { !$0.inLibrary }, enabled: { $0.inRecent }, hiddenIf: "in the Library", greyIf: "not in Recent"),
        Spec(option: .stopListening, kind: .article, places: [.bar], block: 1, enabled: { $0.isLoaded }, greyIf: "nothing loaded"),
        Spec(option: .removeFromHistory, kind: .article, places: [.history], block: 1),

        // A folder. Its row's tap opens it; its header has ▶ and Prepare beside *More*.
        Spec(option: .continueFolder, kind: .folder, places: [.row, .tile], enabled: { $0.hasArticlesToPlay }, greyIf: "nothing in it plays"),
        Spec(option: .playFromStart, kind: .folder, places: [.header], enabled: { $0.hasArticlesToPlay }, greyIf: "nothing in it plays"),
        // One row: Prepare, Turn Off Prepare while on, Remove Prepared audio once all is prepared.
        Spec(option: .folderPrepare, kind: .folder, places: [.row, .tile],
             enabled: { $0.prepareIsOn || $0.hasPreparedAudio || $0.hasArticles }, greyIf: "empty, nothing downloaded, toggle off"),
        Spec(option: .removePreparedAudio, kind: .folder, places: [.header], enabled: { $0.hasPreparedAudio }, greyIf: "nothing downloaded or downloading"),
        // Its screen's More makes a subfolder in it (C122); never in a folder that keeps its own order.
        Spec(option: .folderVoice, kind: .folder, places: folderPlaces, applies: { $0.isBookOrSeries },
             enabled: { $0.hasVoices }, hiddenIf: "a plain folder (each article keeps its own voice)",
             greyIf: "Apple's voice is selected"),
        Spec(option: .folderFavorite, kind: .folder, places: folderPlaces),
        Spec(option: .folderMove, kind: .folder, places: folderPlaces),
        Spec(option: .editDetails, kind: .folder, places: folderPlaces),
        Spec(option: .deleteFolder, kind: .folder, places: folderPlaces),

        // A prepare. Its ↓ mark pauses and resumes.
        Spec(option: .reprepare, kind: .prepare, places: [.preparedAudio], applies: { !$0.isListeningAudio },
             enabled: { !$0.isQueued }, hiddenIf: "audio from listening", greyIf: "still preparing"),
        Spec(option: .removePrepare, kind: .prepare, places: [.preparedAudio]),

        // A screen's own rows (＋ has New Folder and Import Book; the address field starts a search).
        // ＋ makes things in the screen on top; the ⋯ panels keep only Sort, Reload and the tail.
        // The one create group (C126): ＋ (home and folder), a folder header's More and Edit's
        // bar show it, into the folder on screen; Edit's New Folder files the selection in it.
        // Hidden whole in a folder that keeps its own order (an imported EPUB, a followed story).
        Spec(option: .newFolder, kind: .screen, places: [.add, .edit],
             applies: { !$0.isFixedOrder }, hiddenIf: "the folder keeps its own order (imported, followed)"),
        Spec(option: .importFile, kind: .screen, places: [.add, .edit],
             applies: { !$0.isFixedOrder }, hiddenIf: "the folder keeps its own order (imported, followed)"),
        Spec(option: .pasteText, kind: .screen, places: [.add, .edit],
             applies: { !$0.isFixedOrder }, hiddenIf: "the folder keeps its own order (imported, followed)"),
        Spec(option: .follow, kind: .screen, places: [.browser],
             enabled: { $0.canFollow }, greyIf: "browser: no web page up"),
        Spec(option: .sort, kind: .screen, places: [.libraryHome, .folderScreen],
             applies: { !$0.isFixedOrder }, hiddenIf: "the folder keeps its own order (imported, followed)"),
        Spec(option: .reload, kind: .screen, places: [.browser], enabled: { $0.hasWebPage }, greyIf: "no page up"),
        Spec(option: .preparedAudio, kind: .screen, places: panelPlaces),
        Spec(option: .history, kind: .screen, places: panelPlaces, applies: { $0.compact },
             hiddenIf: "regular width (🕘 is in the toolbar)"),
        // The Prepared Audio list's ⋯: each only while its section has rows.
        Spec(option: .deleteAllPrepared, kind: .screen, places: [.preparedAudio], applies: { $0.hasPrepared },
             hiddenIf: "nothing prepared"),
        Spec(option: .clearListeningAudio, kind: .screen, places: [.preparedAudio], applies: { $0.hasListeningAudio },
             hiddenIf: "no audio from listening"),
        // Settings is a tile in every ⋯ panel (C140), not a list row.
    ]

    /// The options a `kind` menu shows at `place` for `facts`, in order, with their submenus.
    static func entries(_ kind: Kind, at place: Place, _ facts: Facts) -> [Entry] {
        func entry(_ spec: Spec) -> Entry? {
            guard spec.kind == kind, spec.places.contains(place), spec.applies(facts) else { return nil }
            let children = specs.filter { $0.parent == spec.option }.compactMap(entry)
            if specs.contains(where: { $0.parent == spec.option }) && children.isEmpty { return nil }
            let enabled = spec.enabled(facts) && (children.isEmpty || children.contains { $0.availability == .enabled })
            return Entry(option: spec.option, availability: enabled ? .enabled : .disabled, children: children,
                         block: spec.block)
        }
        return specs.filter { $0.parent == nil }.compactMap(entry)
    }

    /// The grey / hidden table for every menu (docs/MENUS.md), from the specs: per kind and
    /// place, each option it shows, when it is hidden there and when greyed.
    static var table: String {
        var text = ""
        for kind in Kind.allCases {
            for place in Place.allCases {
                let shown = specs.filter { $0.kind == kind && $0.places.contains(place) }
                guard !shown.isEmpty else { continue }
                text += "\n### \(kind.rawValue) at \(place.rawValue)\n\n| Option | Hidden when | Greyed when |\n|---|---|---|\n"
                for spec in shown {
                    let name = spec.parent.map { "\($0.rawValue) › \(spec.option.rawValue)" } ?? spec.option.rawValue
                    text += "| \(name) | \(spec.hiddenIf.isEmpty ? "never" : spec.hiddenIf) | \(spec.greyIf.isEmpty ? "never" : spec.greyIf) |\n"
                }
            }
        }
        return text
    }

    /// The spec of `option`.
    static func spec(_ option: Option) -> Spec { specs.first { $0.option == option }! }
}
