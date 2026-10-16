import Foundation

/// One label per action, app-wide: the ⋯ panel, long-press menus, header buttons, Edit's bar and
/// sheet titles say the same thing for the same action, next to the same symbol (`Icons`). An
/// ellipsis ends a label only when a picker or a question follows (the Move tree, *Delete…*).
///
/// | Verb | Symbol |
/// |---|---|
/// | Move to… | `Icons.move` |
/// | Save to Folder… | `Icons.save` |
/// | Save to Library / Remove from Library | `Icons.save` / `Icons.unsave` |
/// | Add to Favorites / Remove from Favorites | `Icons.favorite` / `Icons.unfavorite` |
/// | From Start (Play from Start in menus) | `Icons.previous` |
/// | Mark as Finished / Mark as Unfinished | `Icons.markFinished` / `Icons.markUnfinished` |
/// | Remove | `Icons.delete` |
/// | Download, Download Folder, Download Book | `Icons.download` |
/// | Delete Downloads | `Icons.deleteDownloads` |
/// | Delete Folder…, Delete Book… | `Icons.delete` |
/// | Voice Settings | `Icons.voice` |
/// | Downloads | `Icons.downloads` |
enum Verbs {
    static let moveTo = String(localized: "Move to…")
    static let saveToFolder = String(localized: "Save to Folder…")
    static let saveToLibrary = String(localized: "Save to Library")
    static let removeFromLibrary = String(localized: "Remove from Library")
    static let addToFavorites = String(localized: "Add to Favorites")
    static let removeFromFavorites = String(localized: "Remove from Favorites")
    /// A folder header's secondary button; it keeps this name at every width (an icon alone
    /// before a shorter word).
    static let fromStart = String(localized: "From Start")
    /// *From Start* where the menu has no folder to name it against.
    static let playFromStart = String(localized: "Play from Start")
    static let markFinished = String(localized: "Mark as Finished")
    static let markUnfinished = String(localized: "Mark as Unfinished")
    static let remove = String(localized: "Remove")
    static let download = String(localized: "Download")
    static let deleteDownloads = String(localized: "Delete Downloads")
    static let voiceSettings = String(localized: "Voice Settings")
    static let downloads = String(localized: "Downloads")
    static let done = String(localized: "Done")
    static let cancel = String(localized: "Cancel")

    /// *Download Folder* / *Download Book*: a book or series is named as one.
    static func downloadFolder(isBook: Bool) -> String {
        isBook ? String(localized: "Download Book") : String(localized: "Download Folder")
    }

    /// *Delete Folder…* / *Delete Book…*.
    static func deleteFolder(isBook: Bool) -> String {
        isBook ? String(localized: "Delete Book…") : String(localized: "Delete Folder…")
    }
}
