import SwiftUI

/// Something a folder screen's Edit selects.
enum LibraryItemID: Hashable {
    case folder(UUID)
    case page(UUID)
}

/// What the Library's screens share with their surface:
/// Edit's selection, which the bottom bar acts on, and the dialogs a row or a menu asks for
/// (delete, turn a folder's download off, rename, new folder), shown once by `libraryDialogs`.
@MainActor
@Observable
final class LibraryScreenState {
    /// The folder screen in Edit.
    struct Editing: Equatable {
        var folderID: UUID
    }

    /// Where a new folder goes.
    struct NewFolder {
        var parent: Folder?
    }

    private(set) var editing: Editing?
    var selection = Set<LibraryItemID>()
    /// Folders waiting for the delete question (`FolderDeletePrompt`).
    var pendingDelete: [Folder] = []
    /// The folder waiting for the *Turn Off Download* question.
    var pendingTurnOff: Folder?
    var renaming: Folder?
    var renameText = ""
    var newFolder: NewFolder?
    var newFolderName = ""

    /// The row being dragged, from the moment it lifts (`libraryDrag`) until it is let go: the
    /// drop zone takes the drop only meanwhile (`libraryDropZone`).
    private(set) var dragging: LibraryItemID?
    /// The folder row under the drag that takes it: highlighted.
    private(set) var dropTarget: UUID?
    /// The row the drag would be placed beside, and on which side: marked with a line.
    private(set) var insertion: Insertion?
    /// Drops that landed and drops that were refused, for their haptics.
    private(set) var landedDrops = 0
    private(set) var refusedDrops = 0
    /// Where the rows on screen are, for the drop zone. Not observed: rows write it as they move.
    @ObservationIgnored let dropRows = LibraryDropRows()
    struct Insertion: Equatable {
        var id: LibraryItemID
        var edge: VerticalEdge
    }

    var isEditing: Bool { editing != nil }

    func isEditing(folderID: UUID) -> Bool { editing == Editing(folderID: folderID) }

    func beginEditing(folderID: UUID) {
        selection = []
        editing = Editing(folderID: folderID)
    }

    func endEditing() {
        editing = nil
        selection = []
    }

    // MARK: - Dragging

    /// A row lifted into a drag: the drop zone takes it from here (`libraryDropZone`), and ends
    /// it wherever it is let go.
    func beginDrag(_ id: LibraryItemID) {
        dragging = id
        show(.nothing)
    }

    /// What letting go here would do: a folder highlighted, or a line beside a row.
    func show(_ aim: LibraryDropAim) {
        let target: UUID? = if case .into(let id) = aim { id } else { nil }
        let line: Insertion? = if case .beside(let id, let edge) = aim { Insertion(id: id, edge: edge) } else { nil }
        if dropTarget != target { dropTarget = target }
        if insertion != line { insertion = line }
    }

    /// The drag ended: `landed` when it filed or placed the row, false when it was refused or
    /// couldn't be saved; nil when it changed nothing (let go where it was, or nowhere).
    func endDrop(landed: Bool?) {
        dragging = nil
        show(.nothing)
        switch landed {
        case true?: landedDrops += 1
        case false?: refusedDrops += 1
        case nil: break
        }
    }

    func confirmDelete(_ folders: [Folder]) {
        pendingDelete = folders
    }

    /// The delete question was cancelled: nothing is deleted, and Edit keeps its selection.
    func cancelDelete() {
        pendingDelete = []
    }

    /// *Turn Off Download* (a folder's header control, its menus): asked first, since what
    /// downloads next stops.
    func confirmTurnOffDownload(_ folder: Folder) {
        pendingTurnOff = folder
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
    /// *New Folder*'s alert, the Library's and the Move tree's: a name (blank makes "New Folder",
    /// `LibraryStore.makeFolder`), *Cancel* and *Create*, which runs `create` and closes it.
    func newFolderAlert(isPresented: Binding<Bool>, name: Binding<String>, message: String? = nil,
                        create: @escaping () -> Void) -> some View {
        alert("New Folder", isPresented: isPresented) {
            TextField("Name", text: name)
                .accessibilityIdentifier("newFolderField")
            Button("Cancel", role: .cancel) {}
            Button("Create", action: create)
                .accessibilityIdentifier("newFolderCreate")
        } message: {
            if let message { Text(message) }
        }
    }

    /// The Library's dialogs for `state`: delete confirmations, *Turn Off Download*, rename, new
    /// folder. Attached once per surface.
    func libraryDialogs(_ state: LibraryScreenState, onDeleted: @escaping () -> Void) -> some View {
        modifier(LibraryDialogs(state: state, onDeleted: onDeleted))
    }
}

private struct LibraryDialogs: ViewModifier {
    @Bindable var state: LibraryScreenState
    let onDeleted: () -> Void

    @Environment(LibraryStore.self) private var library
    @Environment(ShellState.self) private var shell
    @Environment(FollowCenter.self) private var follow
    @Environment(\.speechController) private var speech
    @Environment(DownloadCenter.self) private var downloads

    func body(content: Content) -> some View {
        content
            .confirmationDialog(prompt.title, isPresented: deleting, titleVisibility: .visible) {
                deleteButtons
            } message: {
                Text(prompt.message)
            }
            // `DownloadCenter.turnOff`: what is downloaded stays.
            .confirmationDialog(Verbs.turnOffDownload, isPresented: Binding(get: { state.pendingTurnOff != nil },
                                                                           set: { if !$0 { state.pendingTurnOff = nil } }),
                                titleVisibility: .hidden) {
                Button(Verbs.turnOffDownload, role: .destructive) {
                    if let folder = state.pendingTurnOff { downloads.turnOff(folder) }
                    state.pendingTurnOff = nil
                }
                Button(Verbs.cancel, role: .cancel) { state.pendingTurnOff = nil }
            } message: {
                Text("Downloaded audio stays. New pages won’t download.")
            }
            .alert("Rename Folder", isPresented: Binding(get: { state.renaming != nil },
                                                        set: { if !$0 { state.renaming = nil } })) {
                TextField("Name", text: $state.renameText)
                    .accessibilityIdentifier("renameFolderField")
                Button("Cancel", role: .cancel) { state.renaming = nil }
                Button("Rename") {
                    if let folder = state.renaming {
                        shell.attempt(String(localized: "Couldn’t rename")) { try library.rename(folder, to: state.renameText) }
                    }
                    state.renaming = nil
                }
            }
            .newFolderAlert(isPresented: Binding(get: { state.newFolder != nil },
                                                 set: { if !$0 { state.newFolder = nil } }),
                            name: $state.newFolderName) {
                if let target = state.newFolder {
                    MoveTreeList.makeFolder(named: state.newFolderName, in: target.parent, library: library, shell: shell)
                }
            }
    }

    private var deleting: Binding<Bool> {
        Binding(get: { !state.pendingDelete.isEmpty }, set: { if !$0 { state.cancelDelete() } })
    }

    private var prompt: FolderDeletePrompt {
        // The delete also stops a session a waiting merge would move onto a page inside.
        FolderDeletePrompt(folders: state.pendingDelete, contents: library.contents(of:)) { keys in
            speech.activeSessionID.map { keys.union(library.keysWaitingToMerge(into: keys)).contains($0) } ?? false
        }
    }

    @ViewBuilder
    private var deleteButtons: some View {
        ForEach(prompt.choices, id: \.id) { choice in
            Button(choice.title, role: choice.isDestructive ? .destructive : nil) { delete() }
            .accessibilityIdentifier(choice.id)
        }
        Button("Cancel", role: .cancel) { state.cancelDelete() }
    }

    /// Once the delete is saved, Edit ends and the surface leaves screens of folders that are gone.
    /// A delete that can't be saved changes nothing (Edit keeps its selection), and a toast says so.
    private func delete() {
        let folders = state.pendingDelete
        state.pendingDelete = []
        guard LibraryActions(library: library, speech: speech, shell: shell, follow: follow)
            .deleteFolders(folders, in: state) else { return }
        onDeleted()
    }
}
