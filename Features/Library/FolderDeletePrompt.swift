import Foundation

/// What deleting folders asks (`libraryDialogs`): its title, the line saying what goes, and the
/// one choice. Deleting a folder (a book or series as any other, decision D19) always deletes what
/// it holds: *Delete Folder and Contents*, plus Cancel. There is no keep-contents choice (D18).
/// Books alone are named as books (*Delete Book and Contents*), as their menu row is.
struct FolderDeletePrompt: Equatable {
    struct Choice: Equatable {
        var title: String
        var id: String
        /// Every choice deletes pages.
        var isDestructive = true
    }

    var title: String
    var message: String
    var choices: [Choice]

    /// `contents`: what a folder holds (`LibraryStore.contents(of:)`); `isPlaying`: whether any
    /// of these page keys is what you hear, to say "Stops what's playing.".
    init(folders: [Folder], contents: (Folder) -> FolderContents, isPlaying: (Set<UUID>) -> Bool) {
        var inside = FolderContents()
        for folder in folders {
            let inner = contents(folder)
            inside.folders += inner.folders
            inside.articles += inner.articles
            inside.articleKeys.formUnion(inner.articleKeys)
        }
        let one = folders.count == 1
        let books = folders.allSatisfy { $0.kind == .book }
        if books {
            title = one ? String(localized: "Delete the book “\(folders[0].name)”?")
                : String(localized: "Delete \(folders.count) books?")
        } else {
            title = one ? String(localized: "Delete the folder “\(folders[0].name)”?")
                : String(localized: "Delete \(folders.count) folders?")
        }
        var lines: [String] = []
        if let summary = inside.summary {
            lines.append("Everything in \(one ? "it" : "them") is deleted too: \(summary).")
        }
        if isPlaying(inside.articleKeys) { lines.append("What’s playing stops.") }
        message = lines.joined(separator: " ")
        let choice = switch (books, one) {
        case (true, true): String(localized: "Delete Book and Contents")
        case (true, false): String(localized: "Delete Books and Contents")
        case (false, true): String(localized: "Delete Folder and Contents")
        case (false, false): String(localized: "Delete Folders and Contents")
        }
        choices = [Choice(title: choice, id: "deleteFolderAndContents")]
    }
}
