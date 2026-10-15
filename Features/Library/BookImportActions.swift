import Foundation

/// How an import starts: *Import Book…* (the Library's ＋ and ⋯, the empty Library's card) opens
/// the Files picker, and the picked file is copied in and imported at once; a book downloaded
/// from an `.epub` link waits in the sheet for *Import*. Either way the import sheet shows it
/// (`BookImportFlow`) and lands on the book's screen.
///
/// One import at a time: a book arriving while the import sheet is up (a second download
/// finishing) is not imported; its file goes and a toast says so. Each flow closes and lands
/// only its own sheet (`ShellState.closeImport`).
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
                                       systemImage: Icons.warning))
        }
    }

    /// A book downloaded from a link (already in `BookImportFiles`): the sheet asks first.
    func importDownloaded(_ file: URL) {
        start(file, into: nil, waitsForImport: true)
    }

    private func start(_ file: URL, into destinationID: UUID?, waitsForImport: Bool) {
        guard shell.importFlow == nil else {
            files.discard(file)
            library.log("import: \(file.lastPathComponent) arrived while another import was open; not imported")
            shell.showToast(ShellToast(message: String(localized: "Another import is open; “\(file.lastPathComponent)” wasn't imported"),
                                       systemImage: Icons.warning))
            return
        }
        let shell = shell
        let library = library
        let flow = BookImportFlow(file: file, destinationID: destinationID, waitsForImport: waitsForImport,
                                  library: library, files: files) { flow, book in
            guard shell.closeImport(flow) else { return }
            shell.showLibrary(at: library.path(to: book))
        } close: { flow in
            shell.closeImport(flow)
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
