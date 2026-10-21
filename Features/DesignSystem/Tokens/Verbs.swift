import Foundation

/// One label per action, app-wide: menus, the ⋯ panel, swipes, header buttons, Edit's bar and
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
/// | Prepare / Turn Off Prepare (a folder) | `Icons.prepare` / `Icons.turnOffPrepare` |
/// | Remove Prepared audio (a folder, its menu and its prepare in the list) | `Icons.removePrepare` |
/// | Add to Favorites / Remove from Favorites | `Icons.favorite` / `Icons.unfavorite` |
/// | Move to… / Save to Folder… | `Icons.move` |
/// | Mark as Finished / Mark as Unfinished | `Icons.markFinished` / `Icons.markUnfinished` |
/// | Mark All Above as Finished | `Icons.markAllAboveFinished` |
/// | Share | `Icons.share` |
/// | Select | `Icons.select` |
/// | Save to Library / Remove from Library | `Icons.save` / `Icons.unsave` |
/// | Remove from Recent | `Icons.removeFromRecent` |
/// | Rename…, Edit Details… | `Icons.rename`, `Icons.editDetails` |
/// | Delete Folder…, Delete Book… | `Icons.delete` |
/// | Pause / Resume (a prepare), Prepare Again, Keep | `Icons.pause` / `Icons.resume`, `Icons.reprepare`, `Icons.keep` |
/// | New Folder…, Import Book…, Follow… | `Icons.newFolder`, `Icons.importFile`, `Icons.follow` |
/// | Prepared audio, Settings | `Icons.prepared audio`, `Icons.settings` |
enum Verbs {
    // MARK: A page

    /// Open it to read (the Reader; Now Playing for the page you hear; a link in the browser).
    static let read = String(localized: "Read")
    /// A folder's ▶ and the Reader's Listen for a page part-way: on from where it was left.
    static let `continue` = String(localized: "Continue")
    /// A page in a folder: play from its start, on through the folder.
    static let playFromHere = String(localized: "Play from Here")
    static let playFromStart = String(localized: "Play from Start")
    static let prepare = String(localized: "Prepare Audio")
    /// A page's, in its menu and in the Prepared Audio list: its audio deleted, and it stays out of
    /// every download (P8). A voice model's in Settings (its swipe): the model deleted, to be
    /// prepared again before the engine speaks.
    static let removePrepare = String(localized: "Remove Prepared Audio")
    /// A voice model's, in Settings (its swipe) and the CPU route bench: a real file download.
    static let removeModelDownload = String(localized: "Remove Prepared Audio")
    /// The Prepared Audio list's row action (C135): the audio only, never the article.
    static let deleteAudio = String(localized: "Delete Audio")
    static let deleteAllPrepared = String(localized: "Delete All…")
    static let clearListeningAudio = String(localized: "Clear Audio From Listening…")
    /// A folder's, in its menu and in the Prepared Audio list: its prepare off and gone, and
    /// *Remove Prepare* for each of its pages.
    static let removePreparedAudio = String(localized: "Remove Prepared Audio")
    /// A prepare done: the Prepared Audio list's section, a folder header's control, the ↓ VoiceOver
    /// reads before a prepared row's line two.
    static let prepared = String(localized: "Prepared")
    static let turnOffPrepare = String(localized: "Turn Off Prepare Audio")
    static let addToFavorites = String(localized: "Add to Favorites")
    static let removeFromFavorites = String(localized: "Remove from Favorites")
    static let moveTo = String(localized: "Move to…")
    /// The Move tree when it saves a page into the folder picked (🔖 held, a menu's row).
    static let saveToFolder = String(localized: "Save to Folder…")
    static let markFinished = String(localized: "Mark as Finished")
    static let markUnfinished = String(localized: "Mark as Unfinished")
    static let markAllAboveFinished = String(localized: "Mark All Above as Finished")
    static let skipInPlayback = String(localized: "Skip in Playback")
    /// The submenu holding a chapter's rare playback rows (C98).
    static let playback = String(localized: "Playback")
    static let playInPlayback = String(localized: "Play in Playback")
    static let share = String(localized: "Share")
    static let select = String(localized: "Select")
    static let saveToLibrary = String(localized: "Save to Library")
    static let removeFromLibrary = String(localized: "Remove from Library")
    /// A page out of the Library: the same remove as *Remove from Library* (in no list after,
    /// the star kept).
    static let removeFromRecent = String(localized: "Remove from Recent")
    static let stopListening = String(localized: "Stop Listening")
    /// Edit's bar: the selected pages removed from the Library, the selected folders deleted
    /// after asking.
    static let remove = String(localized: "Remove")

    // MARK: A folder

    static let rename = String(localized: "Rename…")
    static let editDetails = String(localized: "Edit Details…")

    /// *Delete Folder…* / *Delete Book…*: a book is named as one.
    static func deleteFolder(isBook: Bool) -> String {
        String(localized: "Delete Folder…")
    }

    // MARK: Playing

    /// ▶ from the start or a page not begun (VoiceOver on a ▶; a paused page says *Continue*).
    static let play = String(localized: "Play")
    /// ⏸, what you hear; a prepare's too.
    static let pause = String(localized: "Pause")

    // MARK: A prepare

    static let resume = String(localized: "Resume")
    static let pauseAll = String(localized: "Pause All")
    static let resumeAll = String(localized: "Resume All")
    static let reprepare = String(localized: "Prepare Again")
    /// Keep a prepare made in another voice.
    static let keep = String(localized: "Keep")

    // MARK: Screens

    static let newFolder = String(localized: "New Folder…")
    static let importBook = String(localized: "Import from…")
    static let saveFromWebsite = String(localized: "Save from Website…")
    static let pasteText = String(localized: "Paste Text…")
    static let create = String(localized: "Add")
    /// A story's table of contents, read into a folder of chapters.
    static let follow = String(localized: "Follow…")
    static let unfollow = String(localized: "Unfollow")
    static let followAgain = String(localized: "Follow Again")
    static let checkNow = String(localized: "Check Now")
    static let sort = String(localized: "Sort")
    static let newSearch = String(localized: "New Search")
    static let reload = String(localized: "Reload")
    /// The ⋯ panel's last rows and the screens they open.
    static let preparedAudio = String(localized: "Prepared Audio")
    static let settings = String(localized: "Settings")
    static let favorites = String(localized: "Favorites")
    /// The browser's: pages visited.
    /// The visits sheet's button and title: *Recent*, as the Library's tab (C100).
    static let history = String(localized: "History")
    static let removeFromHistory = String(localized: "Remove from History")
    /// The start page's and the search layer's section of searches made, and its action.
    static let recentSearches = String(localized: "Recent Searches")
    static let clearAll = String(localized: "Clear All")
    /// The two surfaces, as the swap, the back pill and the ⋯'s big button name them; *Library*
    /// is also the home's title and Now Playing's *Go to*.
    static let library = String(localized: "Library")
    static let browser = String(localized: "Browser")
    /// The browser's Reader toggle and big button.
    static let reader = String(localized: "Reader")
    /// The band's ‹ and ›.
    static let back = String(localized: "Back")
    static let forward = String(localized: "Forward")
    /// ⋯ (a row's, a folder header's, the toolbar's) and the folder header's caption.
    static let more = String(localized: "More")
    /// A section header's action that opens the whole list.
    static let showAll = String(localized: "Show All")
    /// The Reader's 📄 in the address field and the browser's ⋯ big button.
    static let openInReader = String(localized: "Open in Reader")
    /// The Reader's pill before a page is started (a part-way page says *Continue*).
    static let listen = String(localized: "Listen")
    /// *Import Book…*'s short title and the import sheet's confirming button.
    static let `import` = String(localized: "Import")
    /// A book's or story's chapter list (the import sheet's, Follow's review).
    static let chapters = String(localized: "Chapters")
    /// A folder's name field (New Folder, Rename, Edit Details).
    static let name = String(localized: "Name")
    /// Settings' appearance and reading themes.
    static let theme = String(localized: "Theme")
    /// Settings rows and the pages or panels they open.
    static let speed = String(localized: "Speed")
    static let voice = String(localized: "Voice")
    /// An article's or a book's menu row (C138): "Voice: Heart".
    static func voiceRow(_ name: String) -> String { String(localized: "Voice: \(name)") }
    static let changeVoice = String(localized: "Change Voice")
    static let language = String(localized: "Language")
    static let textSize = String(localized: "Text Size")
    static let listenDebug = String(localized: "Listen Debug")

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
