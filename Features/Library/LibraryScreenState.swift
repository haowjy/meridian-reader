import SwiftUI

/// Something a folder screen's Edit selects.
enum LibraryItemID: Hashable {
    case folder(UUID)
    case article(UUID)
}

/// What the Library's screens share with their surface:
/// Edit's selection, which the bottom bar acts on, and the dialogs a row or a menu asks for
/// (delete, rename, new folder), shown once by `libraryDialogs`. *Stop Preparing* is asked
/// where it was tapped instead (`turnOffPrepareQuestion`).
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
        /// Edit's selection, filed into the new folder once it is made (Files' "New Folder with Items").
        var items: [LibraryItem] = []
    }

    private(set) var editing: Editing?
    var selection = Set<LibraryItemID>()
    /// Folders waiting for the delete question (`FolderDeletePrompt`).
    var pendingDelete: [Folder] = []
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

    func commitEditing() {
        editing = nil
        selection = []
    }

    func cancelEditing() {
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

    func rename(_ folder: Folder) {
        renameText = folder.name
        renaming = folder
    }

    func makeFolder(in parent: Folder?, with items: [LibraryItem] = []) {
        newFolderName = ""
        newFolder = NewFolder(parent: parent, items: items)
    }

    func pasteText(into folder: Folder?, shell: ShellState) {
        shell.present(.pasteText(folder?.id))
    }

    /// Add a Link starts the shared address and story-review sheet.
    func addLink(into folder: Folder?, shell: ShellState, follow: FollowCenter) {
        let flow = FollowFlow(url: nil, parentID: folder?.id, center: follow)
        flow.address = UIPasteboard.general.hasURLs ? UIPasteboard.general.url?.absoluteString ?? "" : ""
        shell.present(.follow(flow))
    }

    /// The typed address as a web address, or nil when it isn't one. A bare host and path
    /// ("example.com/a", "localhost:8080" with its port) gets `https://`; an address with a scheme
    /// keeps it and must be http or https ("mailto:…", "ftp://…" are refused, not rewritten).
    /// The host needs a real name: localhost, or two or more labels of letters, digits and hyphens ("." and
    /// "example." are refused); no user name or password.
    static func linkURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        // A scheme is letters then ":"; "host:8080" is a port, not a scheme.
        let hasScheme = trimmed.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*:(?!\d+(?:[/?#]|$))"#,
                                      options: .regularExpression) != nil
        guard let url = URL(string: hasScheme ? trimmed : "https://" + trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.user == nil, url.password == nil, let host = url.host(percentEncoded: false) else { return nil }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        let isLabel: (Substring) -> Bool = { label in
            !label.isEmpty && !label.hasPrefix("-") && !label.hasSuffix("-")
                && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
        guard labels.count >= 2 || host == "localhost", labels.allSatisfy(isLabel) else { return nil }
        return url
    }
}

extension View {
    /// *New Folder*'s alert, the Library's and the Move tree's: a name (blank makes "New Folder",
    /// `LibraryStore.makeFolder`), *Cancel* and *Create*, which runs `create` and closes it.
    func newFolderAlert(isPresented: Binding<Bool>, name: Binding<String>, message: String? = nil,
                        create: @escaping () -> Void) -> some View {
        alert(Verbs.title(Verbs.newFolder), isPresented: isPresented) {
            TextField(Verbs.name, text: name)
                .accessibilityIdentifier("newFolderField")
            Button(Verbs.cancel, role: .cancel) {}
            Button("Create", action: create)
                .accessibilityIdentifier("newFolderCreate")
        } message: {
            if let message { Text(message) }
        }
    }

    /// The Library's dialogs for `state`: delete confirmations, rename, new folder. Attached once
    /// per surface.
    func libraryDialogs(_ state: LibraryScreenState, onDeleted: @escaping () -> Void) -> some View {
        modifier(LibraryDialogs(state: state, onDeleted: onDeleted))
    }

    /// *Stop Preparing*'s question for `folder` (nil: not asked), asked first since what
    /// prepared audio next stops: *Stop Preparing* (`PrepareCenter.turnOff`, what is prepared
    /// stays) or *Cancel*. One question for every way in, each attaching it to the control that
    /// asks (on iOS 26 it shows as a popover pointing there): the folder header's Prepare control
    /// and *More*, a folder row's ⋯ (its long press too), the screen's ⋯.
    func turnOffPrepareQuestion(_ folder: Binding<Folder?>) -> some View {
        modifier(TurnOffPrepareQuestion(folder: folder))
    }
}

private struct TurnOffPrepareQuestion: ViewModifier {
    @Binding var folder: Folder?
    @Environment(PrepareCenter.self) private var preparedAudio

    func body(content: Content) -> some View {
        content.confirmationDialog(Verbs.turnOffPrepare, isPresented: Binding(get: { folder != nil },
                                                                                set: { if !$0 { folder = nil } }),
                                   titleVisibility: .hidden, presenting: folder) { folder in
            Button(Verbs.turnOffPrepare, role: .destructive) { preparedAudio.turnOff(folder) }
            Button(Verbs.cancel, role: .cancel) {}
        } message: { _ in
            Text("Prepared audio stays. New articles won’t be prepared.")
        }
    }
}

private struct LibraryDialogs: ViewModifier {
    @Bindable var state: LibraryScreenState
    let onDeleted: () -> Void

    @Environment(LibraryStore.self) private var library
    @Environment(ShellState.self) private var shell
    @Environment(FollowCenter.self) private var follow
    @Environment(\.speechController) private var speech

    func body(content: Content) -> some View {
        content
            .confirmationDialog(prompt.title, isPresented: deleting, titleVisibility: .visible) {
                deleteButtons
            } message: {
                Text(prompt.message)
            }
            .alert(Verbs.title(Verbs.rename), isPresented: Binding(get: { state.renaming != nil },
                                                        set: { if !$0 { state.renaming = nil } })) {
                TextField(Verbs.name, text: $state.renameText)
                    .accessibilityIdentifier("renameFolderField")
                Button(Verbs.cancel, role: .cancel) { state.renaming = nil }
                Button(Verbs.title(Verbs.rename)) {
                    if let folder = state.renaming {
                        shell.attempt(String(localized: "Couldn’t rename")) { try library.rename(folder, to: state.renameText) }
                    }
                    state.renaming = nil
                }
            }
            .newFolderAlert(isPresented: Binding(get: { state.newFolder != nil },
                                                 set: { if !$0 { state.newFolder = nil } }),
                            name: $state.newFolderName) {
                if let target = state.newFolder,
                   let made = MoveTreeList.makeFolder(named: state.newFolderName, in: target.parent, library: library, shell: shell),
                   !target.items.isEmpty {
                    if shell.attempt(String(localized: "Couldn’t move into the folder"), { try library.move(target.items, to: made) }) != nil {
                        state.selection = []
                    }
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
        Button(Verbs.cancel, role: .cancel) { state.cancelDelete() }
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

/// *Paste Text…* (C127): an optional title and the text, the pasteboard's when it held some.
/// *Save* makes a new article of it in the folder on screen and opens it in Library Read.
struct PasteTextSheet: View {
    let parentID: UUID?
    @State private var title = ""
    @State private var text = UIPasteboard.general.hasStrings ? UIPasteboard.general.string ?? "" : ""
    @Environment(LibraryStore.self) private var library
    @Environment(ShellState.self) private var shell
    @Environment(FollowCenter.self) private var follow
    @Environment(\.speechController) private var speech
    @FocusState private var editing: Bool

    private var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        InputSheet(title: Verbs.title(Verbs.pasteText), onCancel: { shell.sheet = nil }) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                TextField(String(localized: "Title (optional)"), text: $title,
                          prompt: Text(isEmpty ? String(localized: "Title (optional)") : LibraryStore.defaultTitle(for: text)))
                    .inputSheetField()
                    .accessibilityIdentifier("pasteTextTitle")
                TextEditor(text: $text)
                    .focused($editing)
                    .typeStyle(.row)
                    .scrollContentBackground(.hidden)
                    .padding(Spacing.s)
                    .background(Palette.chrome, in: RoundedRectangle(cornerRadius: Radius.surface, style: .continuous))
                    .accessibilityIdentifier("pasteTextBody")
            }
            .padding(Spacing.pageMargin)
            .onAppear { if isEmpty { editing = true } }
        } actions: {
            PillButton(Verbs.save, style: isEmpty ? .neutral : .filled, expands: true, action: save)
                .disabled(isEmpty)
                .accessibilityIdentifier("pasteTextSave")
        }
        .presentationDetents([.medium, .large])
        .sheetToastLayer()
    }

    private func save() {
        let folder = parentID.flatMap(library.folder(id:))
        if LibraryActions(library: library, speech: speech, shell: shell, follow: follow)
            .savePastedText(title: title, text: text, in: folder) {
            shell.sheet = nil
        }
    }
}
