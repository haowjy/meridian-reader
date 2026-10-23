import Foundation

/// One book import, from its file to the book's screen, as the import sheet shows it
/// (`ShellSheet.importBook`). It runs `BookImporter` on a file in `BookImportFiles` and deletes
/// that file however the import ends.
///
/// - A picked file starts at once; a prepared one (an `.epub` link) waits in `.ready` for the
///   sheet's *Import*.
/// - *Add to* (`destinationID`) can change while the book is read and prepared. The importer
///   looks it up again in its one save, so the book is stored where *Add to* says, durably, with
///   no second save. It is fixed from *Saving the book…* on. A folder chosen and then deleted
///   fails the import, saying so (`BookImportError.destinationGone`); the Library is unchanged.
/// - A book already in the Library stops after reading and asks *Replace* / *Cancel* (decision
///   D13). *Replace* runs again on the same file and rebuilds the book where it is.
/// - *Cancel* stops the import between chapters, before anything is stored; the library is as
///   it was.
@MainActor
@Observable
final class BookImportFlow: Identifiable {
    enum Phase: Equatable {
        /// A prepared book, waiting for *Import*.
        case ready
        case working(BookImportProgress)
        /// The book (this folder) is in the Library already: *Replace* or *Cancel*.
        case alreadyInLibrary(UUID)
        /// Why it wasn't imported, one line, with OK.
        case failed(String)
        /// Imported, cancelled or failed and seen: the file is gone and the sheet closes.
        case ended
    }

    let id = UUID()
    /// The book's file, in `BookImportFiles`.
    let file: URL
    private(set) var phase: Phase
    /// The book as read from the file (nil until then).
    private(set) var preview: BookImportPreview?
    /// Where the book goes (nil: the Library's top level). Fixed while *Replace* runs: the book
    /// stays where it is.
    private(set) var destinationID: UUID?
    /// *Replace* is running.
    private(set) var isReplacing = false
    /// The Move tree, pushed inside the sheet by *Change*.
    var isChoosingDestination = false

    private let library: LibraryStore
    private let files: BookImportFiles
    /// The book is in the Library: close this flow's sheet and show the book.
    private let land: (BookImportFlow, Folder) -> Void
    /// Close this flow's sheet (not another flow's that came up since).
    private let close: (BookImportFlow) -> Void
    private var task: Task<Void, Never>?
    private var isCancelled = false

    init(file: URL, destinationID: UUID?, waitsForImport: Bool, library: LibraryStore,
         files: BookImportFiles = .standard, land: @escaping (BookImportFlow, Folder) -> Void,
         close: @escaping (BookImportFlow) -> Void) {
        self.file = file
        self.destinationID = destinationID
        self.phase = waitsForImport ? .ready : .working(.reading)
        self.library = library
        self.files = files
        self.land = land
        self.close = close
        if !waitsForImport { run(.cancel) }
    }

    /// Working on the book: the sheet can't be pulled away, only cancelled.
    var isWorking: Bool {
        if case .working = phase { true } else { false }
    }

    /// The file's name, as picked or prepared.
    var fileName: String { file.lastPathComponent }

    /// The book's title: from its package once read, else its file's name.
    var title: String { preview?.title ?? file.deletingPathExtension().lastPathComponent }

    /// Where the book goes, as the library has it now (nil: the top level, or a folder deleted
    /// since it was chosen, `isDestinationGone`).
    var destination: Folder? { destinationID.flatMap(library.folder(id:)) }

    /// The folder *Add to* names was deleted: the import would fail, so the sheet says so.
    var isDestinationGone: Bool { destinationID != nil && destination == nil }

    /// *Change* works: not for *Replace* (the book stays where it is), nor once the book is being
    /// saved (where it goes is settled then).
    var canChangeDestination: Bool {
        switch phase {
        case .ready, .working(.reading), .working(.preparing): !isReplacing
        case .working(.storing), .alreadyInLibrary, .failed, .ended: false
        }
    }

    // MARK: - The sheet's buttons

    /// *Import* on a prepared book.
    func startImport() {
        guard phase == .ready else { return }
        run(.cancel)
    }

    /// D13's *Replace*.
    func replace() {
        guard case .alreadyInLibrary(let id) = phase else { return }
        isReplacing = true
        destinationID = library.folder(id: id)?.parent?.id
        run(.replace)
    }

    /// *Cancel*, D13's *Cancel*, or the sheet pulled away: stops the import (it keeps nothing)
    /// and closes the sheet.
    func cancel() {
        guard phase != .ended else { return }
        isCancelled = true
        task?.cancel()
        if task == nil { files.discard(file) }
        phase = .ended
        close(self)
    }

    /// OK on a failure.
    func acknowledgeFailure() {
        guard case .failed = phase else { return }
        phase = .ended
        close(self)
    }

    /// The Move tree's pick: the book goes there (nil: the top level).
    func choose(_ folder: Folder?) {
        isChoosingDestination = false
        guard canChangeDestination else { return }
        destinationID = folder?.id
    }

    /// The Move tree's *New Folder*: the folder is made, then chosen. One
    /// that can't be saved chooses nothing and leaves the tree up; the toast says so.
    func chooseNewFolder(named name: String, in parent: Folder?, shell: ShellState) {
        guard let folder = MoveTreeList.makeFolder(named: name, in: parent, library: library, shell: shell) else { return }
        choose(folder)
    }

    /// The sheet is gone, however it went: an import still running or waiting stops.
    func sheetGone() {
        if phase != .ended { cancel() }
    }

    // MARK: - Running

    private func run(_ choice: ReimportChoice) {
        phase = .working(.reading)
        task = Task {
            do {
                // `destinationID` is read again in the importer's save: *Add to* as it is then.
                let outcome = try await BookImporter(library: library).importBook(
                    at: file, into: self.destinationID, ifAlreadyInLibrary: choice,
                    progress: progressed, read: { self.preview = $0 })
                finished(outcome)
            } catch {
                failed(error)
            }
        }
    }

    private func progressed(_ progress: BookImportProgress) {
        guard !isCancelled else { return }
        phase = .working(progress)
    }

    private func failed(_ error: Error) {
        task = nil
        files.discard(file)
        guard !isCancelled else { return }
        if error is CancellationError { return }
        let message = (error as? BookImportError)?.localizedDescription
            ?? String(localized: "Meridian couldn't import this book.")
        library.log("import \(fileName) failed: \(error)")
        phase = .failed(message)
    }

    private func finished(_ outcome: BookImportOutcome) {
        task = nil
        switch outcome {
        case .alreadyInLibrary(let book):
            // The file stays for *Replace*.
            guard !isCancelled else { return files.discard(file) }
            phase = .alreadyInLibrary(book.id)
        case .added(let book), .replaced(let book):
            files.discard(file)
            end(landingOn: book)
        }
    }

    /// Imported: the sheet closes on the book, unless *Cancel* came too late to stop it (then
    /// the book stays in the Library and the sheet is already gone).
    private func end(landingOn book: Folder) {
        guard !isCancelled else { return }
        phase = .ended
        land(self, book)
    }
}

extension BookImportFlow: Equatable {
    nonisolated static func == (a: BookImportFlow, b: BookImportFlow) -> Bool { a === b }
}
