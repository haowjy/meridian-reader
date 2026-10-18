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
/// | Remove from History | `Icons.removeFromHistory` |
/// | Add to Favorites / Remove from Favorites | `Icons.favorite` / `Icons.unfavorite` |
/// | Play from Start | `Icons.previous` |
/// | Mark as Finished / Mark as Unfinished | `Icons.markFinished` / `Icons.markUnfinished` |
/// | Remove | `Icons.delete` |
/// | Download, Download Folder, Download Book | `Icons.download` |
/// | Remove Download (a page) | `Icons.removeDownload` |
/// | Turn Off Download (a folder) | `Icons.turnOffDownload` |
/// | Delete Downloads | `Icons.deleteDownloads` |
/// | Read | `Icons.reader` |
/// | Delete Folder…, Delete Book… | `Icons.delete` |
/// | Settings | `Icons.settings` |
/// | Downloads | `Icons.downloads` |
/// | Follow… / Unfollow / Follow Again | `Icons.follow` / `Icons.unfollow` / `Icons.follow` |
/// | Check Now | `Icons.reload` |
enum Verbs {
    static let moveTo = String(localized: "Move to…")
    static let saveToFolder = String(localized: "Save to Folder…")
    static let saveToLibrary = String(localized: "Save to Library")
    static let removeFromLibrary = String(localized: "Remove from Library")
    /// A History row's: the same remove as *Remove from Library* (in no list after, star kept).
    static let removeFromHistory = String(localized: "Remove from History")
    static let addToFavorites = String(localized: "Add to Favorites")
    static let removeFromFavorites = String(localized: "Remove from Favorites")
    static let playFromStart = String(localized: "Play from Start")
    /// A page row's menu: open it to read (the Reader; Now Playing for the page you hear).
    static let read = String(localized: "Read")
    static let markFinished = String(localized: "Mark as Finished")
    static let markUnfinished = String(localized: "Mark as Unfinished")
    static let remove = String(localized: "Remove")
    static let download = String(localized: "Download")
    static let removeDownload = String(localized: "Remove Download")
    static let turnOffDownload = String(localized: "Turn Off Download")
    static let deleteDownloads = String(localized: "Delete Downloads")
    /// The ⋯ panel's last row and the screen it opens.
    static let settings = String(localized: "Settings")
    static let downloads = String(localized: "Downloads")
    /// ⋯ → *Follow…*: a story's table of contents, read into a folder of chapters.
    static let follow = String(localized: "Follow…")
    static let unfollow = String(localized: "Unfollow")
    static let followAgain = String(localized: "Follow Again")
    static let checkNow = String(localized: "Check Now")
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
