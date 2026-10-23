import SwiftUI

/// One SF Symbol per concept, app-wide (decision D24): the same thing reads the same on every
/// surface, in a toolbar, a ⋯ row, a context menu or a toast. Feature code names the concept
/// (`Icons.save`), never the symbol. A concept's states pair up as outline at rest and filled when
/// on (`save` / `saved`, `jump` / `jumpOn`).
///
/// Size and weight come from where a symbol sits, not from here: `toolbarIconFrame()` (a toolbar
/// slot), `fieldControlFrame()` (a round control in a field capsule or a sheet's top bar),
/// `PillSymbol` (before a pill's title), the ⋯ panel's rows and tiles.
enum Icons {
    // MARK: Moving around

    /// ‹ in the toolbar, the Reader's back pill.
    static let back = "chevron.backward"
    /// › in the toolbar.
    static let forward = "chevron.forward"
    /// Now Playing's close pill: it shrinks back into the bar.
    static let collapse = "chevron.down"
    /// Closes a sheet or a search, dismisses a banner.
    static let close = "xmark"
    /// Empties a text field.
    static let clearText = "xmark.circle.fill"
    /// A row that opens a screen or a submenu.
    static let disclosure = "chevron.right"
    /// ⋯.
    static let more = "ellipsis"
    /// The web: the swap to the browser, Website, search the web.
    static let browser = "globe"
    /// The Library: the swap to it, a place at its top level.
    static let library = "books.vertical"
    /// The Reader (open a page in it).
    static let reader = "doc.plaintext"
    /// The Reader text is showing in the page's place (Follow's chapter preview).
    static let readerShowing = "doc.plaintext.fill"
    /// History (the browser's: pages visited).
    static let history = "clock"
    /// Recent (the Library's tab: pages listened to without saving).
    static let recent = "clock.arrow.circlepath"
    static let search = "magnifyingglass"
    /// Puts a suggestion into the field to keep typing.
    static let fillField = "arrow.up.backward"
    static let dictate = "mic"
    /// Dictation under way (the mic's place while it listens).
    static let dictating = "mic.fill"
    /// Load again: the browser's Reload, and Follow's *Try Again* and *Check Now* (the story's
    /// page fetched again).
    static let reload = "arrow.clockwise"

    // MARK: The Library

    /// 🔖: save to the Library (outline), saved (filled), remove from it.
    static let save = "bookmark"
    static let saved = "bookmark.fill"
    static let unsave = "bookmark.slash"
    /// Remove from Recent: a page played without saving leaves the Library's Recent tab (the
    /// system has no struck-out form of `recent`).
    static let removeFromRecent = "clock.badge.xmark"
    /// ＋ in the Library's toolbar.
    static let add = "plus"
    static let folder = "folder"
    static let newFolder = "folder.badge.plus"
    /// A book (a folder with details), Import Book.
    /// Import EPUB… (nothing is a book: an import is a folder, C100).
    static let importFile = "square.and.arrow.down"
    /// Move to… and Save to Folder…: into a folder (a folder itself is `folder`). The arrow-folder
    /// symbol is iOS 26's; before that the plain folder stands in.
    static var move: String {
        if #available(iOS 26.0, *) { "arrow.forward.folder" } else { folder }
    }
    static let favorite = "star"
    static let favorited = "star.fill"
    static let unfavorite = "star.slash"
    static let rename = "pencil"
    static let editDetails = "square.and.pencil"
    static let share = "square.and.arrow.up"
    /// Something goes for good: *Delete Folder…*, Edit's *Remove*, *Remove from History*, *Remove
    /// Cover*. (A page leaving the Library is `unsave`; a prepare going, `removePrepare`.)
    static let delete = "trash"
    static let sort = "arrow.up.arrow.down"
    /// ≡ Drag handle for reorder in Edit (C148).
    static let reorder = "line.3.horizontal"
    /// Select (Edit's check circles).
    static let select = "checkmark.circle"
    /// Checked: the chosen option in a list or menu (where the system draws the same ✓ in its own
    /// pickers). Not Select's circle, nor the filled circle that means prepared, nor a finished
    /// page (that is the listening ring, full).
    static let checkmark = "checkmark"
    /// Mark as Finished: a filled circle, the listening ring made full (a finished page shows the
    /// full `ProgressRing` before "Finished"; rings mean listening, ✓ is selection's only). Filled, not the bare ring, so Edit's toolbar slot doesn't read as one of
    /// Edit's empty selection circles.
    static let markFinished = "checkmark.circle"
    /// Mark as Unfinished: the ring undone.
    static let markUnfinished = "circle.dashed"
    /// Mark All Above as Finished: a list of pages, rings full (no ✓; the circle-✓ is *Select*'s).
    static let markAllAboveFinished = "list.bullet.circle"
    static let skipInPlayback = "forward.end"
    /// The *Playback* submenu (C98).
    static let playback = "list.bullet"
    static let includeInPlayback = "play.square"
    static let photo = "photo"
    static let photos = "photo.on.rectangle"
    /// Choose from Files (a file picker; a Library folder is `folder`).
    static let files = "doc"
    /// A web address standing in for a page with no title.
    static let link = "link"
    static let paste = "doc.on.clipboard"
    /// Follow a story (⋯ → *Follow…*), a followed story's status line; Unfollow.
    static let follow = "antenna.radiowaves.left.and.right"
    static let unfollow = "antenna.radiowaves.left.and.right.slash"
    /// A chapter kept (checked) or left out in Follow's Review.
    static let included = "checkmark.square.fill"
    static let excluded = "square"
    /// Some of a list kept: Review's *Select All* between all and none.
    static let partlyIncluded = "minus.square.fill"
    /// Waiting on a site that asked to slow down.
    static let waiting = "hourglass"

    // MARK: Listening

    /// 🎧 Listen (the address field's badge, a toast about listening).
    static let listen = "headphones"
    static let play = "play.fill"
    static let pause = "pause.fill"
    static let stop = "stop.fill"
    /// ⏮: the previous paragraph, and From Start / Play from Start.
    static let previous = "backward.end"
    static let next = "forward.end"
    /// ☝︎ Listen from a paragraph: off, on.
    static let jump = "hand.tap"
    static let jumpOn = "hand.tap.fill"
    /// Playing (bars beside a title, the tinted pill).
    static let playing = "waveform"
    static let sleepTimer = "moon.fill"
    /// A voice's sample: play, stop.
    static let previewPlay = "play.circle"
    static let previewStop = "stop.circle"
    /// Developer options' listen debug: its switch and its panel.
    static let debug = "ladybug"

    // MARK: Prepared audio

    /// Prepare (a row's menu, a toast, a folder header's control before it prepared audio).
    static let prepare = "arrow.down.circle"
    /// The arrow alone, inside a prepare's filling circle (`PrepareMark`).
    static let prepareArrow = "arrow.down"
    /// Prepared: the grey badge before a row's second line, a folder header's control, a voice
    /// model in Settings.
    /// Waiting to prepare with Reduce Motion on, in place of the spinner (C93).
    static let prepareQueued = "hourglass"
    /// A filled ↓, not a ✓ (C89): ✓ means only selection and a picked option.
    static let prepared = "arrow.down.circle.fill"
    /// The Prepared Audio list.
    static let preparedAudio = "tray.and.arrow.down"
    /// *Remove Prepare* (a page) and *Remove Prepared audio* (a folder), in their menus and the
    /// Prepared Audio list: the audio deleted.
    static let removePrepare = "trash.circle"
    static let removeModelDownload = "trash.circle"
    /// Turning a folder's Prepare off (its audio stays).
    static let turnOffPrepare = "arrow.down.circle.dotted"
    /// *Prepare Again*: down again (not the browser's Reload arrow).
    static let reprepare = "arrow.uturn.down.circle"
    /// *Resume* a paused prepare (not Prepare's arrow, nor listening's ▶).
    static let resume = "playpause.fill"
    /// Keep (a design-system preview's pill).
    static let keep = "pin"
    /// *Voice: Heart*, an article's or a book's voice (C138).
    static let voice = "person.wave.2"

    // MARK: Settings and reading

    /// Settings (the last row of every ⋯ panel).
    static let settings = "gearshape"
    /// Aa: how the page reads (the reading theme, font, size and spacing panel).
    static let textAppearance = "textformat.size"
    static let textSmaller = "textformat.size.smaller"
    static let textLarger = "textformat.size.larger"
    /// Block Ads (Settings › Browsing).
    static let blockAds = "hand.raised"
    /// Prepared audio and storage (Settings).
    static let storage = "internaldrive"
    /// Privacy Policy (Settings › About).
    static let privacy = "doc.text"
    /// Support (Settings › About).
    static let support = "questionmark.circle"

    // MARK: Notices

    static let warning = "exclamationmark.triangle"
}

extension Text {
    /// A symbol inside running text (an empty state naming a toolbar button): the toolbar's own
    /// symbol, in ink, so the prose and the button match.
    static func symbol(_ name: String) -> Text {
        Text(Image(systemName: name)).foregroundStyle(Palette.ink)
    }
}
