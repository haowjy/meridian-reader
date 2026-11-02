import Foundation

/// One name per action: the tile's name, plus “…” when it opens an input sheet (`Verbs`).
/// Groups always run open/play, add, audio, item actions, remove, screen actions, separated by
/// dividers. A menu never repeats a control already on that screen. Prepared Audio is reached
/// only through Settings; Voice belongs where audio plays or can be prepared, never an in-place
/// reading page. The explicit save group remains available on reading pages beside their bookmark.
///
/// Every menu is assembled here by kind and place; its renderer only supplies labels, symbols
/// and actions. Hide an option only where it can never apply; disable it when it cannot run now.
enum MenuRegistry {
    /// What a menu is for.
    enum Kind: String, CaseIterable { case article, folder, prepare, screen }

    /// Where a menu opens.
    enum Place: String, CaseIterable {
        /// A Library list row's ⋯ and long press (every tab, search, a folder's screen).
        case row
        /// The Now Playing bar's long press.
        case bar
        /// A History visit.
        case history
        /// The Reader's ⋯ menu.
        case reader
        /// Listen's ⋯ (compact width: the player card's system menu; regular width: its band's ⋯ menu).
        case nowPlaying
        /// The browser's ⋯ menu.
        case browser
        /// A folder header's *More*.
        case header
        /// The Library home's title ⋯ (compact width): the create group, then Sort.
        case libraryHome
        /// A folder screen's title ⋯ (compact width): the create group, then Sort.
        case folderScreen
        /// The Library's ⋯ menu at regular width (the home or a folder's screen), beside its own ＋.
        case libraryPanel
        /// A Prepared Audio list row.
        case preparedAudio
        /// The Library's ＋ (the home or a folder's screen).
        case add
        /// A folder screen's bottom bar in Edit.
        case edit
    }

    /// Every option of a kind (menu order is `specs`' order).
    enum Option: String, CaseIterable {
        // A page
        case save, move, follow, read, goTo, prepare, voice, finished, playback, markAllAbove, skip, share,
             removeFromRecent, stopListening, removeVisit
        // A folder, book or series
        case continueFolder, playFromStart, folderPrepare, removePreparedAudio, folderVoice, folderMove,
             editDetails, deleteFolder
        // A prepare
        case reprepare, removePrepare
        // A screen's own rows
        case newFolder, importFile, pasteText, addLink, sort, browsingHistory, playFromParagraph
        // The Prepared Audio list's own ⋯ (C135)
        case deleteAllPrepared, clearListeningAudio
    }

    /// The item's state as a menu needs it: plain values its host already has (no fetch, no disk).
    struct Facts: Equatable {
        // A page
        /// There is a page to act on: a page model, an address or text on screen.
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
        var hasShareURL = false
        var inRecent = false
        var isLoaded = false
        /// It can belong to a story: it has a web address (*Follow…* reads the story from it).
        var followable = false
        /// *Follow…* can run now (nothing else is extracting the page).
        var canFollow = true
        // A folder
        var hasArticlesToPlay = false
        var hasArticles = false
        var prepareIsOn = false
        var hasPreparedAudio = false
        /// A book or series: one voice for every chapter (C138).
        var isBookOrSeries = false
        // A prepare
        var isQueued = false
        /// A row of From Listening: audio made while listening, not prepared (C135).
        var isListeningAudio = false
        /// Playback needs its audio now (the article playing): it can't be deleted.
        var audioInUse = false
        // The Prepared Audio list
        var hasPrepared = false
        var hasListeningAudio = false
        // A screen
        var canJumpToParagraph = false
    }

    struct Spec {
        let option: Option
        let kind: Kind
        /// The places it can ever show in.
        let places: Set<Place>
        /// A sub-option: shows inside this option's submenu.
        var parent: Option?
        /// Its group, in display order, set apart by dividers.
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

    private static let articlePlaces: Set<Place> = [.row, .bar, .history, .reader, .nowPlaying, .browser]
    private static let articleListPlaces: Set<Place> = [.row, .bar, .history]
    private static let readingPlaces: Set<Place> = [.reader, .nowPlaying, .browser]
    private static let audioPlaces: Set<Place> = [.row, .bar, .reader, .browser]
    private static let playbackPlaces: Set<Place> = [.row, .bar, .reader]
    private static let saveEnabled: (Facts) -> Bool = { !$0.offersSave || $0.canSave }
    private static let folderPlaces: Set<Place> = [.row, .header]
    /// The create group: the ＋, Edit's ＋, and compact width's title ⋯ (which has no ＋).
    private static let createPlaces: Set<Place> = [.add, .edit, .libraryHome, .folderScreen]

    static let specs: [Spec] = [
        Spec(option: .read, kind: .article, places: articleListPlaces),
        Spec(option: .save, kind: .article, places: articlePlaces, block: 1,
             applies: { $0.offersSave }, enabled: saveEnabled, hiddenIf: "already saved", greyIf: "nothing to save yet"),
        Spec(option: .move, kind: .article, places: articlePlaces, block: 1,
             applies: { $0.offersSave }, enabled: saveEnabled, hiddenIf: "already saved", greyIf: "nothing to save yet"),
        Spec(option: .follow, kind: .article, places: readingPlaces, block: 1, applies: { $0.followable },
             enabled: { $0.canFollow }, hiddenIf: "no web address", greyIf: "the page is being extracted"),
        Spec(option: .prepare, kind: .article, places: audioPlaces, block: 2,
             enabled: { $0.inLibrary || ($0.hasPage && $0.canSave) }, greyIf: "no extracted article to prepare"),
        Spec(option: .voice, kind: .article, places: [.row, .bar], block: 2, applies: { $0.hasPage },
             hiddenIf: "no page"),
        Spec(option: .goTo, kind: .article, places: [.nowPlaying], block: 2,
             enabled: { $0.goToEnabled }, greyIf: "nowhere to go"),
        Spec(option: .move, kind: .article, places: articlePlaces, block: 3,
             applies: { !$0.offersSave }, enabled: saveEnabled, hiddenIf: "not saved", greyIf: "nothing to save yet"),
        Spec(option: .finished, kind: .article, places: articlePlaces.subtracting([.history]), block: 3,
             enabled: { $0.isSaved }, greyIf: "not saved"),
        Spec(option: .playback, kind: .article, places: playbackPlaces, block: 3,
             applies: { $0.inFolder }, enabled: { $0.canPlay }, hiddenIf: "not in a folder", greyIf: "neither row inside can run"),
        Spec(option: .markAllAbove, kind: .article, places: [.row], parent: .playback,
             applies: { $0.inFolder }, enabled: { $0.isSaved }, hiddenIf: "not in a folder", greyIf: "not saved"),
        Spec(option: .skip, kind: .article, places: playbackPlaces, parent: .playback,
             applies: { $0.inFolder }, enabled: { $0.canPlay }, hiddenIf: "not in a folder", greyIf: "not saved and not a waiting chapter"),
        Spec(option: .share, kind: .article, places: articlePlaces, block: 3,
             applies: { $0.hasShareURL }, hiddenIf: "no web address"),
        Spec(option: .save, kind: .article, places: articlePlaces, block: 4,
             applies: { !$0.offersSave }, enabled: saveEnabled, hiddenIf: "not saved", greyIf: "nothing to save yet"),
        Spec(option: .removeFromRecent, kind: .article, places: [.row, .bar], block: 4,
             applies: { !$0.inLibrary }, enabled: { $0.inRecent }, hiddenIf: "in the Library", greyIf: "not in History"),
        Spec(option: .removeVisit, kind: .article, places: [.history], block: 4),
        Spec(option: .stopListening, kind: .article, places: [.bar], block: 5,
             enabled: { $0.isLoaded }, greyIf: "nothing loaded"),

        Spec(option: .continueFolder, kind: .folder, places: [.row], enabled: { $0.hasArticlesToPlay }, greyIf: "nothing in it plays"),
        Spec(option: .playFromStart, kind: .folder, places: [.header], enabled: { $0.hasArticlesToPlay }, greyIf: "nothing in it plays"),
        Spec(option: .folderPrepare, kind: .folder, places: [.row], block: 2,
             enabled: { $0.prepareIsOn || $0.hasPreparedAudio || $0.hasArticles }, greyIf: "empty, nothing downloaded, toggle off"),
        Spec(option: .removePreparedAudio, kind: .folder, places: [.header], block: 2,
             enabled: { $0.hasPreparedAudio }, greyIf: "nothing downloaded or downloading"),
        Spec(option: .folderVoice, kind: .folder, places: folderPlaces, block: 2,
             applies: { $0.isBookOrSeries }, hiddenIf: "a plain folder (each article keeps its own voice)"),
        Spec(option: .folderMove, kind: .folder, places: folderPlaces, block: 3),
        Spec(option: .editDetails, kind: .folder, places: folderPlaces, block: 3),
        Spec(option: .deleteFolder, kind: .folder, places: folderPlaces, block: 4),

        Spec(option: .reprepare, kind: .prepare, places: [.preparedAudio], applies: { !$0.isListeningAudio },
             enabled: { !$0.isQueued }, hiddenIf: "audio from listening", greyIf: "still preparing"),
        Spec(option: .removePrepare, kind: .prepare, places: [.preparedAudio], block: 4,
             enabled: { !$0.audioInUse }, greyIf: "audio from listening that playback needs now"),

        Spec(option: .addLink, kind: .screen, places: createPlaces),
        Spec(option: .importFile, kind: .screen, places: createPlaces),
        Spec(option: .pasteText, kind: .screen, places: createPlaces),
        Spec(option: .newFolder, kind: .screen, places: createPlaces, block: 1),
        Spec(option: .sort, kind: .screen, places: [.libraryHome, .folderScreen, .libraryPanel], block: 2),
        Spec(option: .browsingHistory, kind: .screen, places: [.browser], block: 5),
        Spec(option: .playFromParagraph, kind: .screen, places: [.nowPlaying], block: 5,
             enabled: { $0.canJumpToParagraph }, greyIf: "no text loaded"),
        Spec(option: .deleteAllPrepared, kind: .screen, places: [.preparedAudio], applies: { $0.hasPrepared },
             hiddenIf: "nothing prepared"),
        Spec(option: .clearListeningAudio, kind: .screen, places: [.preparedAudio], applies: { $0.hasListeningAudio },
             hiddenIf: "no audio from listening"),
    ]

    /// The options a `kind` menu shows at `place` for `facts`, in order, with their submenus. A page's
    /// menu with no page and no address (the browser's start page) is empty.
    static func entries(_ kind: Kind, at place: Place, _ facts: Facts) -> [Entry] {
        if kind == .article && place == .browser && !facts.hasTarget { return [] }
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
        var text = "\nA page's menu with no page and no address (the browser's start page) shows nothing.\n"
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
}
