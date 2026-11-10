import Foundation

/// One label per action, app-wide: menus, the ⋯ menu, swipes, header buttons, Edit's bar and
/// sheet titles say the same thing for the same action, next to the same symbol (`Icons`). A
/// label used in more than one place lives here; a literal repeating one is a bug.
///
/// **Case.** Title Case (iOS's: words of four letters or fewer that join, like *to*, *from*,
/// *in*, *as*, stay lower case) for what names a control or a place: buttons, menu rows, swipe
/// actions, sheet and screen titles, section headers, setting and fact labels ("Last Checked"),
/// tab names, empty-state titles. Sentence case for what reads as a sentence or a value: notes,
/// footers, empty-state descriptions, toasts, a row's status, a setting's or fact's value
/// ("today 8:02 AM").
///
/// **Swipes.** A list row's swipe is one word, no noun and no ellipsis, as iOS's are: *Delete*,
/// *Remove* (`MenuRow.swipeTitle`), even when it asks first; the swipe is on the thing, and the
/// question names it. Its menu row keeps the full label (*Delete Folder…*).
///
/// **Ellipsis.** A label ends in "…" only when more input follows before anything happens: a
/// picker, a question or a name to type (*Move to…*, *Rename…*, *Delete Folder…*). A sheet's title
/// is its label without it ("Save to Folder").
///
/// | Verb | Symbol |
/// |---|---|
/// | Read | `Icons.reader` |
/// | Continue | `Icons.play` |
/// | Play from Here, Play from Start | `Icons.play`, `Icons.previous` |
/// | Prepare / Remove Prepare (a page, its menu and its prepare in the list) | `Icons.prepare` / `Icons.removePrepare` |
/// | Prepare / Stop Preparing (a folder) | `Icons.prepare` / `Icons.turnOffPrepare` |
/// | Remove Prepared Audio (a folder, its menu and its prepare in the list) | `Icons.removePrepare` |
/// | Move to… / Save to Folder… | `Icons.move` |
/// | Mark as Finished / Mark as Unfinished | `Icons.markFinished` / `Icons.markUnfinished` |
/// | Mark All Above as Finished | `Icons.markAllAboveFinished` |
/// | Share | `Icons.share` |
/// | Save to Library / Remove from Library | `Icons.save` / `Icons.unsave` |
/// | Remove from Recent | `Icons.removeFromRecent` |
/// | Rename…, Edit Details… | `Icons.rename`, `Icons.editDetails` |
/// | Delete Folder…, Delete Book… | `Icons.delete` |
/// | Pause (a prepare), Prepare Again | `Icons.pause`, `Icons.reprepare` |
/// | New Folder…, Import a File…, Paste Text…, Add a Link…, Follow… | `Icons.newFolder`, `Icons.importFile`, `Icons.paste`, `Icons.link`, `Icons.follow` |
/// | Prepared Audio, Settings | `Icons.preparedAudio`, `Icons.settings` |
enum Verbs {
    // MARK: A page

    /// Open it to read (the Reader; Now Playing for the page you hear; a link in the browser).
    static let read = String(localized: "Read")
    /// A folder's ▶ and the Reader's Listen for a page part-way: on from where it was left.
    static let `continue` = String(localized: "Continue")
    /// A page in a folder: play from its start, on through the folder.
    static let playFromHere = String(localized: "Play from Here")
    static let playFromStart = String(localized: "Play from Start")
    /// The Reader's and Now Playing's ⋯ on compact width: the next tap on a paragraph plays from it.
    static let playFromParagraph = String(localized: "Play from a Paragraph")
    /// ☝︎ while on: the next tap on a paragraph no longer plays from it.
    static let cancelPlayFromParagraph = String(localized: "Cancel Play from a Paragraph")
    static let prepare = String(localized: "Prepare Audio")
    /// A page's, in its menu and in the Prepared Audio list: its audio deleted, and it stays out of
    /// every download.
    static let removePrepare = String(localized: "Remove Prepared Audio")
    /// A voice model's, in Settings › Voice (and the CPU route bench): the model files deleted so
    /// they download again before the engine speaks. Not prepared-audio removal.
    static let removeModelDownload = String(localized: "Remove Download")
    /// The Prepared Audio list's row action: the audio only, never the article.
    static let deleteAudio = String(localized: "Delete Audio")
    static let deleteAllPrepared = String(localized: "Delete All…")
    static let clearListeningAudio = String(localized: "Clear Audio from Listening…")
    /// A folder's, in its menu and in the Prepared Audio list: its prepare off and gone, and
    /// *Remove Prepared Audio* for each of its pages.
    static let removePreparedAudio = String(localized: "Remove Prepared Audio")
    /// A prepare done: the Prepared Audio list's section, a folder header's control, the ↓ VoiceOver
    /// reads before a prepared row's line two.
    static let prepared = String(localized: "Prepared")
    static let turnOffPrepare = String(localized: "Stop Preparing Audio")
    static let moveTo = String(localized: "Move to…")
    /// The Move tree when it saves a page into the folder picked (🔖 held, a menu's row).
    static let saveToFolder = String(localized: "Save to Folder…")
    static let markFinished = String(localized: "Mark as Finished")
    static let markUnfinished = String(localized: "Mark as Unfinished")
    static let markAllAboveFinished = String(localized: "Mark All Above as Finished")
    static let skipInPlayback = String(localized: "Skip When Playing")
    /// The submenu holding a chapter's rare playback rows.
    static let playback = String(localized: "Playback")
    static let playInPlayback = String(localized: "Don’t Skip")
    static let share = String(localized: "Share")
    static let select = String(localized: "Select")
    static let saveToLibrary = String(localized: "Save to Library")
    static let removeFromLibrary = String(localized: "Remove from Library")
    static let removeFromLibraryQuestion = String(localized: "Remove from Library?")
    /// A page out of the Library: the same remove as *Remove from Library* (in no list after).
    static let removeFromRecent = String(localized: "Remove from History")
    static let stopListening = String(localized: "Stop Listening")
    /// Edit's bar: the selected pages removed from the Library, the selected folders deleted
    /// after asking.
    static let remove = String(localized: "Remove")

    // MARK: A folder

    static let rename = String(localized: "Rename…")
    static let editDetails = String(localized: "Edit Details…")

    /// *Delete Folder…* / *Delete Book…*: a book is named as one.
    static func deleteFolder(isBook: Bool) -> String {
        isBook ? String(localized: "Delete Book…") : String(localized: "Delete Folder…")
    }

    // MARK: Playing

    /// ▶ from the start or a page not begun (VoiceOver on a ▶; a paused page says *Continue*).
    static let play = String(localized: "Play")
    /// ⏸, what you hear; a prepare's too.
    static let pause = String(localized: "Pause")

    // MARK: A prepare

    static let resume = String(localized: "Resume")
    /// The toast after the voice stopped (`ListenNotice.offersRetry`): play on from there.
    static let retry = String(localized: "Retry")
    static let pauseAll = String(localized: "Pause All")
    static let resumeAll = String(localized: "Resume All")
    static let reprepare = String(localized: "Prepare Again")

    // MARK: Screens

    static let newFolder = String(localized: "New Folder…")
    static let importBook = String(localized: "Import a File…")
    static let pasteText = String(localized: "Paste Text…")
    static let addLink = String(localized: "Add a Link…")
    static let create = String(localized: "Add")
    /// A story's table of contents, read into a folder of chapters.
    static let follow = String(localized: "Follow…")
    static let unfollow = String(localized: "Unfollow")
    static let followAgain = String(localized: "Follow Again")
    static let checkNow = String(localized: "Check Now")
    static let sort = String(localized: "Sort")
    static let newSearch = String(localized: "New Search")
    static let reload = String(localized: "Reload")
    /// The Aa panel: the Browser's reader mode has no Aa on screen, so its ⋯ opens it.
    static let textAppearance = String(localized: "Text Appearance")
    /// ✕ in the address field while a page loads.
    static let stopLoading = String(localized: "Stop Loading")
    /// The ⋯ menu's last rows and the screens they open.
    static let preparedAudio = String(localized: "Prepared Audio")
    static let settings = String(localized: "Settings")
    /// ⋯ › Help, and Settings › About's row: the bundled article that explains the app.
    static let help = String(localized: "Help")
    static let howItWorks = String(localized: "How Meridian Reader Works")
    /// The Library's tab of pages played or opened and not kept.
    static let history = String(localized: "History")
    /// The browser's pages visited: its sheet's title and the buttons and menu rows that open it.
    static let browsingHistory = String(localized: "Browsing History")
    /// A Browsing History visit's remove: the visit goes, the page (and the Library's copy) stays.
    static let removeVisit = String(localized: "Remove from History")
    /// The start page's and the search layer's section of searches made, and its action.
    static let recentSearches = String(localized: "Recent Searches")
    /// The start page's sites with the most pages in History.
    static let frequentlyVisited = String(localized: "Frequently Visited")
    static let clearAll = String(localized: "Clear All")
    /// The two surfaces, as the swap, the back pill and the ⋯'s big button name them; *Library*
    /// is also the home's title and Now Playing's *Go to*.
    static let search = String(localized: "Search")
    static let library = String(localized: "Library")
    static let browser = String(localized: "Browser")
    /// The browser's Reader toggle and big button.
    static let reader = String(localized: "Reader")
    /// The band's ‹ and ›.
    static let back = String(localized: "Back")
    static let jumpToAudio = String(localized: "Jump to Audio")
    static let forward = String(localized: "Forward")
    /// ⋯ (a row's, a folder header's, the toolbar's) and the folder header's caption.
    static let more = String(localized: "More")
    /// A section header's action that opens the whole list.
    static let showAll = String(localized: "Show All")
    /// The Reader's 📄 in the address field and the browser's ⋯ big button.
    static let openInReader = String(localized: "Open in Reader")
    /// The address field's 📄 while the page shows as its reader view.
    static let showWebPage = String(localized: "Show Web Page")
    /// The Reader's pill before a page is started (a part-way page says *Continue*).
    static let listen = String(localized: "Listen")
    /// *Import Book…*'s short title and the import sheet's confirming button.
    static let `import` = String(localized: "Import")
    /// A book's or story's chapter list (the import sheet's, Follow's review).
    static let chapters = String(localized: "Chapters")
    static let posts = String(localized: "Posts")
    /// A folder's name field (New Folder, Rename, Edit Details).
    static let name = String(localized: "Name")
    /// Settings' appearance and reading themes.
    static let theme = String(localized: "Theme")
    /// Settings rows and the pages or panels they open.
    static let speed = String(localized: "Speed")
    static let voice = String(localized: "Voice")
    /// An article's or a book's menu row, with what the screen calls its voice
    /// (`LocalTTSCoordinator.voiceSummary`): "Voice: Default", "Voice: Kokoro".
    static func voiceRow(_ name: String) -> String { String(localized: "Voice: \(name)") }
    static let changeVoice = String(localized: "Change Voice")
    /// The prompt before a large voice download on cellular or in Low Data Mode.
    static let downloadAnyway = String(localized: "Download")
    static let notNow = String(localized: "Not Now")
    static let textSize = String(localized: "Text Size")
    static let listenDebug = String(localized: "Listen Debug")
    /// The reading pages' ▶ Listen once the page is what you hear: it only opens Listen.
    static let openListen = String(localized: "Open Listen")

    // MARK: Sheets

    static let done = String(localized: "Done")
    /// An alert's only button, and Follow's confirming pill.
    static let ok = String(localized: "OK")
    /// Where an imported book goes: the import sheet's section and the picker it opens.
    static let addTo = String(localized: "Add to")
    static let cancel = String(localized: "Cancel")
    static let delete = String(localized: "Delete")
    static let clear = String(localized: "Clear")
    static let save = String(localized: "Save")
    static let edit = String(localized: "Edit")

    /// A sheet's title for the picker a label opens: the label without its ellipsis.
    static func title(_ label: String) -> String {
        label.hasSuffix("…") ? String(label.dropLast()) : label
    }
}
