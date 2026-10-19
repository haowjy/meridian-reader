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
    /// History (the browser's: pages visited, searches made).
    static let history = "clock"
    /// Recent (the Library's tab: pages listened to without saving).
    static let recent = "clock.arrow.circlepath"
    static let search = "magnifyingglass"
    /// Puts a suggestion into the field to keep typing.
    static let fillField = "arrow.up.backward"
    static let dictate = "mic"
    /// Dictation under way (the mic's place while it listens).
    static let dictating = "mic.fill"
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
    static let book = "book.closed"
    /// Move to a folder.
    static let move = folder
    static let favorite = "star"
    static let favorited = "star.fill"
    static let unfavorite = "star.slash"
    static let rename = "pencil"
    static let editDetails = "square.and.pencil"
    static let share = "square.and.arrow.up"
    static let delete = "trash"
    static let sort = "arrow.up.arrow.down"
    /// Select (Edit's check circles).
    static let select = "checkmark.circle"
    /// The chosen option in a list; Finished, before a row's status.
    static let checkmark = "checkmark"
    /// Mark as Finished: the plain ✓ a finished row shows (not Select's circle, nor the filled
    /// circle that means downloaded).
    static let markFinished = checkmark
    static let markUnfinished = "circle"
    static let markAllAboveFinished = "checkmark.circle.badge.questionmark"
    static let skipInPlayback = "forward.end"
    static let includeInPlayback = "play.square"
    static let photo = "photo"
    static let photos = "photo.on.rectangle"
    /// A web address standing in for a page with no title.
    static let link = "link"
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
    static let previous = "backward.end.fill"
    static let next = "forward.end.fill"
    /// ☝︎ Listen from a paragraph: off, on.
    static let jump = "hand.tap"
    static let jumpOn = "hand.tap.fill"
    /// Playing (bars beside a title, the tinted pill).
    static let playing = "waveform"
    static let sleepTimer = "moon.fill"
    static let voice = "person.wave.2"
    /// A voice's sample: play, stop.
    static let previewPlay = "play.circle"
    static let previewStop = "stop.circle"
    /// Developer options' listen debug: its switch and its panel.
    static let debug = "ladybug"

    // MARK: Downloads

    /// Download (a row's menu, a toast, a folder header's control before it downloads).
    static let download = "arrow.down.circle"
    /// The arrow alone, inside a download's filling circle (`DownloadMark`).
    static let downloadArrow = "arrow.down"
    /// Downloading: the jade disc over a row's dimmed tile.
    static let downloading = "arrow.down.circle.fill"
    /// Downloaded: the grey badge before a row's second line, a folder header's control, a voice
    /// model in Settings.
    static let downloaded = "checkmark.circle.fill"
    /// The Downloads list.
    static let downloads = "tray.and.arrow.down"
    /// *Remove Download* (a page, a download in the list) and *Remove Downloads* (a folder's
    /// pages): the audio deleted.
    static let removeDownload = "trash.circle"
    /// Turning a folder's Download off (its audio stays).
    static let turnOffDownload = "arrow.down.circle.dotted"
    static let redownload = reload
    /// Keep a download made with another voice.
    static let keep = "pin"

    // MARK: Settings and reading

    /// Settings (the last row of every ⋯ panel).
    static let settings = "gearshape"
    /// Aa: how the page reads (the reading theme, font, size and spacing panel).
    static let textAppearance = "textformat.size"
    static let textSmaller = "textformat.size.smaller"
    static let textLarger = "textformat.size.larger"
    /// The app's appearance (Settings › Appearance).
    static let appearance = "circle.lefthalf.filled"
    /// Block Ads (Settings › Browsing).
    static let blockAds = "hand.raised"
    /// Downloads and storage (Settings).
    static let storage = "internaldrive"
    /// Developer options (Settings › Developer).
    static let developer = "hammer"

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
