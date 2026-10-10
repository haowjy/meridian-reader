import Foundation

/// What deleting folders asks (`libraryDialogs`): its title, the line saying what goes, and the
/// choices. Plain folders offer *Delete Folder Only* (their contents move up one level) or
/// *Delete Folder and Contents*. A book or series is always deleted with its chapters
/// (`LibraryStore.deleteFolders`), so a selection holding one never offers *Folder Only*: its
/// choices name the books, and the message says they go either way.
struct FolderDeletePrompt: Equatable {
    struct Choice: Equatable {
        var title: String
        /// Plain folders' contents move up (books and series go whatever this says).
        var keepsContents: Bool
        var id: String
        /// Deletes pages: everything but *Delete Folder Only*.
        var isDestructive = true
    }

    var title: String
    var message: String
    var choices: [Choice]

    /// `contents`: what a folder holds (`LibraryStore.contents(of:)`); `isPlaying`: whether any
    /// of these page keys is what you hear.
    init(folders: [Folder], contents: (Folder) -> FolderContents, isPlaying: (Set<UUID>) -> Bool) {
        let plain = folders.filter { !$0.kind.isFixed }
        let fixed = folders.filter { $0.kind.isFixed }
        var inside = FolderContents()
        var keys = Set<UUID>()
        for folder in folders {
            let inner = contents(folder)
            keys.formUnion(inner.pageKeys)
            guard !folder.kind.isFixed else { continue }
            inside.folders += inner.folders
            inside.pages += inner.pages
            inside.books += inner.books
        }
        let books = Self.books(fixed)
        var lines: [String] = []

        if plain.isEmpty {
            if fixed.count == 1 {
                let book = fixed[0]
                title = book.kind == .series ? "Delete the series “\(book.displayName)”?" : "Delete “\(book.displayName)”?"
                lines.append("Its chapters and their downloads are deleted.")
            } else {
                title = "Delete \(books.lower)?"
                lines.append("Their chapters and downloads are deleted.")
            }
            choices = [Choice(title: "Delete \(books.title)", keepsContents: false, id: "deleteBook")]
        } else if fixed.isEmpty {
            let one = plain.count == 1
            title = one ? "Delete the folder “\(plain[0].displayName)”?" : "Delete \(plain.count) folders?"
            if let summary = inside.summary {
                lines.append("\(one ? "It holds" : "They hold") \(summary). Delete \(one ? "Folder" : "Folders") Only moves them up one level.")
            }
            choices = [
                Choice(title: one ? "Delete Folder Only" : "Delete Folders Only", keepsContents: true, id: "deleteFolderOnly",
                       isDestructive: false),
                Choice(title: one ? "Delete Folder and Contents" : "Delete Folders and Contents", keepsContents: false,
                       id: "deleteFolderAndContents"),
            ]
        } else {
            let one = plain.count == 1
            let folderNoun = one ? "1 folder" : "\(plain.count) folders"
            title = "Delete \(folderNoun) and \(books.lower)?"
            let named = fixed.count == 1 ? "“\(fixed[0].displayName)” is" : "The \(books.lower) are"
            lines.append("\(named) deleted with \(fixed.count == 1 ? "its" : "their") chapters and downloads either way.")
            if let summary = inside.summary {
                lines.append("\(one ? "The folder holds" : "The folders hold") \(summary).")
            }
            choices = [
                Choice(title: "Delete \(books.title), Keep Folder Contents", keepsContents: true,
                       id: "deleteBooksKeepFolderContents"),
                Choice(title: "Delete Everything", keepsContents: false, id: "deleteFolderAndContents"),
            ]
        }
        if isPlaying(keys) { lines.append("Stops what's playing.") }
        message = lines.joined(separator: " ")
    }

    /// "Book", "2 Books", "Series", "1 Book and 1 Series" (title case) and lower case.
    private static func books(_ fixed: [Folder]) -> (title: String, lower: String) {
        let series = fixed.filter { $0.kind == .series }.count
        let books = fixed.count - series
        if fixed.count == 1 { return series == 1 ? ("Series", "the series") : ("Book", "the book") }
        let parts = [(books, "Book", "Books"), (series, "Series", "Series")]
            .filter { $0.0 > 0 }
            .map { count, one, many in "\(count) \(count == 1 ? one : many)" }
        let title = parts.joined(separator: " and ")
        return (title, title.lowercased())
    }
}
