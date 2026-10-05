import SwiftUI

/// Something a folder screen's Edit selects.
enum LibraryItemID: Hashable {
    case folder(UUID)
    case page(UUID)
}

/// What the Library's screens share with their surface (the Library, or the Favorites sheet):
/// Edit's selection, which the bottom bar acts on, and the dialogs a row or a menu asks for
/// (delete, rename, new folder), shown once by `libraryDialogs`.
@MainActor
@Observable
final class LibraryScreenState {
    /// The screen in Edit: its folder (nil: the top level's pages).
    struct Editing: Equatable {
        var folderID: UUID?
    }

    /// Where a new folder goes.
    struct NewFolder {
        var parent: Folder?
    }

    private(set) var editing: Editing?
    var selection = Set<LibraryItemID>()
    /// Folders waiting for *Delete Folder Only* / *Delete Folder and Contents* (or *Delete Book*).
    var pendingDelete: [Folder] = []
    var renaming: Folder?
    var renameText = ""
    var newFolder: NewFolder?
    var newFolderName = ""

    var isEditing: Bool { editing != nil }

    func isEditing(folderID: UUID?) -> Bool { editing == Editing(folderID: folderID) }

    func beginEditing(folderID: UUID?) {
        selection = []
        editing = Editing(folderID: folderID)
    }

    func endEditing() {
        editing = nil
        selection = []
    }

    func confirmDelete(_ folders: [Folder]) {
        pendingDelete = folders.filter { $0.kind != .favorites }
    }

    func rename(_ folder: Folder) {
        renameText = folder.name
        renaming = folder
    }

    func makeFolder(in parent: Folder?) {
        newFolderName = ""
        newFolder = NewFolder(parent: parent)
    }
}

extension View {
    /// The Library's dialogs for `state`: delete confirmations, rename, new folder. Attached once
    /// per surface.
    func libraryDialogs(_ state: LibraryScreenState, onDeleted: @escaping () -> Void) -> some View {
        modifier(LibraryDialogs(state: state, onDeleted: onDeleted))
    }
}

private struct LibraryDialogs: ViewModifier {
    @Bindable var state: LibraryScreenState
    let onDeleted: () -> Void

    @Environment(LibraryStore.self) private var library
    @Environment(\.speechController) private var speech

    func body(content: Content) -> some View {
        content
            .confirmationDialog(deleteTitle, isPresented: deleting, titleVisibility: .visible) {
                deleteButtons
            } message: {
                Text(deleteMessage)
            }
            .alert("Rename Folder", isPresented: Binding(get: { state.renaming != nil },
                                                        set: { if !$0 { state.renaming = nil } })) {
                TextField("Name", text: $state.renameText)
                    .accessibilityIdentifier("renameFolderField")
                Button("Cancel", role: .cancel) { state.renaming = nil }
                Button("Rename") {
                    if let folder = state.renaming { try? library.rename(folder, to: state.renameText) }
                    state.renaming = nil
                }
            }
            .alert("New Folder", isPresented: Binding(get: { state.newFolder != nil },
                                                     set: { if !$0 { state.newFolder = nil } })) {
                TextField("Name", text: $state.newFolderName)
                    .accessibilityIdentifier("newFolderField")
                Button("Cancel", role: .cancel) { state.newFolder = nil }
                Button("Create") {
                    let name = state.newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let target = state.newFolder {
                        _ = try? library.makeFolder(name: name.isEmpty ? String(localized: "New Folder") : name,
                                                    in: target.parent)
                    }
                    state.newFolder = nil
                }
                .accessibilityIdentifier("newFolderCreate")
            }
    }

    private var deleting: Binding<Bool> {
        Binding(get: { !state.pendingDelete.isEmpty }, set: { if !$0 { state.pendingDelete = [] } })
    }

    private var isBook: Bool { state.pendingDelete.count == 1 && state.pendingDelete[0].kind.isFixed }

    private var deleteTitle: String {
        let folders = state.pendingDelete
        if folders.count == 1 {
            let folder = folders[0]
            switch folder.kind {
            case .book: return "Delete “\(folder.displayName)”?"
            case .series: return "Delete the series “\(folder.displayName)”?"
            default: return "Delete the folder “\(folder.displayName)”?"
            }
        }
        return "Delete \(folders.count) folders?"
    }

    private var deleteMessage: String {
        var total = FolderContents()
        for folder in state.pendingDelete {
            let inner = library.contents(of: folder)
            total.folders += inner.folders
            total.pages += inner.pages
            total.books += inner.books
            total.pageKeys.formUnion(inner.pageKeys)
        }
        var lines: [String] = []
        if isBook {
            lines.append("Its chapters and their downloads are deleted.")
        } else if let summary = total.summary {
            lines.append("It holds \(summary). Delete Folder Only moves them up one level.")
        }
        if let playing = speech.activeSessionID, total.pageKeys.contains(playing) {
            lines.append("Stops what's playing.")
        }
        return lines.joined(separator: " ")
    }

    @ViewBuilder
    private var deleteButtons: some View {
        if isBook {
            Button(state.pendingDelete[0].kind == .series ? "Delete Series" : "Delete Book", role: .destructive) {
                delete(keepContents: false)
            }
            .accessibilityIdentifier("deleteBook")
        } else {
            Button("Delete Folder Only") { delete(keepContents: true) }
                .accessibilityIdentifier("deleteFolderOnly")
            Button("Delete Folder and Contents", role: .destructive) { delete(keepContents: false) }
                .accessibilityIdentifier("deleteFolderAndContents")
        }
        Button("Cancel", role: .cancel) { state.pendingDelete = [] }
    }

    private func delete(keepContents: Bool) {
        for folder in state.pendingDelete {
            try? library.deleteFolder(folder, keepContents: keepContents)
        }
        state.pendingDelete = []
        state.endEditing()
        onDeleted()
    }
}
