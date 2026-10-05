import Foundation

/// How an import starts: *Import Book…* (the Library's ＋ and ⋯, the empty Library's card) opens
/// the Files picker, and the picked file is copied in and imported at once; a book downloaded
/// from an `.epub` link waits in the sheet for *Import*. Either way the import sheet shows it
/// (`BookImportFlow`) and lands on the book's screen.
@MainActor
struct BookImportActions {
    let library: LibraryStore
    let shell: ShellState
    var files = BookImportFiles.standard

    /// *Import Book…*: the book goes into `destination` (nil: the top level). With
    /// `-importTestEPUB` (Debug) the synthetic EPUB stands in for the picker, which a UI test
    /// can't drive.
    func pickBook(into destination: Folder?) {
        #if DEBUG
        if LaunchOptions.current.importsTestEPUB {
            importTestBook(into: destination?.id)
            return
        }
        #endif
        shell.pickBook(into: destination?.id)
    }

    /// The picker's file: copied in under its security-scoped access, then imported.
    func importPicked(_ url: URL, into destinationID: UUID?) {
        do {
            start(try files.copyIn(url), into: destinationID, waitsForImport: false)
        } catch {
            library.log("import: couldn't copy \(url.lastPathComponent): \(error)")
            shell.showToast(ShellToast(message: String(localized: "Couldn't open this file"),
                                       systemImage: "exclamationmark.triangle"))
        }
    }

    /// A book downloaded from a link (already in `BookImportFiles`): the sheet asks first.
    func importDownloaded(_ file: URL) {
        start(file, into: nil, waitsForImport: true)
    }

    private func start(_ file: URL, into destinationID: UUID?, waitsForImport: Bool) {
        let shell = shell
        let library = library
        let flow = BookImportFlow(file: file, destinationID: destinationID, waitsForImport: waitsForImport,
                                  library: library, files: files) { book in
            shell.sheet = nil
            shell.showLibrary(at: library.path(to: book))
        } close: {
            if case .importBook = shell.sheet { shell.sheet = nil }
        }
        shell.present(.importBook(flow))
    }

    #if DEBUG
    private func importTestBook(into destinationID: UUID?) {
        do {
            let file = try files.newFile(named: TestEPUB.fileName)
            try TestEPUB.write(to: file)
            start(file, into: destinationID, waitsForImport: false)
        } catch {
            library.log("import: couldn't write the test EPUB: \(error)")
        }
    }
    #endif
}
