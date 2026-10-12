import Foundation

/// What deleting folders asks (`libraryDialogs`): its title, the line saying what goes, and the
/// one choice. Deleting a folder always deletes what it holds: *Delete Folder and Contents* (or
/// *Delete Book* for books and series), plus Cancel. There is no keep-contents choice.
struct FolderDeletePrompt: Equatable {
    struct Choice: Equatable {
        var title: String
        /// Plain folders' contents move up (books and series go whatever this says).
        var keepsContents: Bool
        var id: String
        /// Every choice deletes pages.
        var isDestructive = true
    }

    var title: String
    var message: String
    var choices: [Choice]

    /// `contents`: what a folder holds (`LibraryStore.contents(of:)`); `isPlaying`: whether any
    /// of these page keys is what you hear. "Stops what's playing." is said of the choices that
    /// delete the page playing: every choice for a book's chapter; for a plain folder's page, the
    /// choice deleting the contents, by name.
    init(folders: [Folder], contents: (Folder) -> FolderContents, isPlaying: (Set<UUID>) -> Bool) {
        let plain = folders.filter { !$0.kind.isFixed }
        let fixed = folders.filter { $0.kind.isFixed }
        var inside = FolderContents()
        var keys = Set<UUID>()
        var bookKeys = Set<UUID>()
        for folder in folders {
            let inner = contents(folder)
            keys.formUnion(inner.pageKeys)
            if folder.kind.isFixed { bookKeys.formUnion(inner.pageKeys) }
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
                lines.append("\(one ? "It holds" : "They hold") \(summary). They're deleted too.")
            }
            choices = [
                Choice(title: one ? "Delete Folder and Contents" : "Delete Folders and Contents", keepsContents: false,
                       id: "deleteFolderAndContents"),
            ]
        } else {
            let one = plain.count == 1
            let folderNoun = one ? "1 folder" : "\(plain.count) folders"
            title = "Delete \(folderNoun) and \(books.lower)?"
            let named = fixed.count == 1 ? "“\(fixed[0].displayName)” is" : "The \(books.lower) are"
            lines.append("\(named) deleted with \(fixed.count == 1 ? "its" : "their") chapters and downloads.")
            if let summary = inside.summary {
                lines.append("\(one ? "The folder holds" : "The folders hold") \(summary).")
            }
            choices = [
                Choice(title: one ? "Delete Folder and Contents" : "Delete Folders and Contents", keepsContents: false, id: "deleteFolderAndContents"),
            ]
        }
        // A choice keeping contents deletes only the books and series (`LibraryStore.deleteFolders`).
        let playingBooks = isPlaying(bookKeys)
        let playingAll = playingBooks || isPlaying(keys)
        let stopping = choices.filter { $0.keepsContents ? playingBooks : playingAll }
        if stopping.count == choices.count {
            lines.append("Stops what's playing.")
        } else if let choice = stopping.first {
            lines.append("\(choice.title) stops what's playing.")
        }
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
