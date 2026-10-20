import Foundation

/// What deleting folders asks (`libraryDialogs`): its title, the line saying what goes, and the
/// one choice. Deleting a folder (a book or series as any other, decision D19) always deletes what
/// it holds: *Delete Folder and Contents*, plus Cancel. There is no keep-contents choice (D18).
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
        title = one ? "Delete the folder “\(folders[0].name)”?" : "Delete \(folders.count) folders?"
        var lines: [String] = []
        if let summary = inside.summary {
            lines.append("\(one ? "It holds" : "They hold") \(summary). They're deleted too.")
        }
        if isPlaying(inside.articleKeys) { lines.append("Stops what's playing.") }
        message = lines.joined(separator: " ")
        choices = [Choice(title: one ? "Delete Folder and Contents" : "Delete Folders and Contents",
                          id: "deleteFolderAndContents")]
    }
}
