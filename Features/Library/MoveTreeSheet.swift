import SwiftData
import SwiftUI

/// The Move tree: one sheet for Move, *Save to Library…* and 🔖's *Save to Folder…* (the import
/// sheet's *Add to* pushes the same list, `MoveTreeList`). The whole tree as
/// one indented list, like Safari's bookmark-folder picker; one tap files, ✓ marks the current
/// place. *New Folder* makes one at the top level; a folder's
/// long-press, *New Folder Inside*, makes one in it; either way what is being filed goes into the
/// new folder. Every folder is a destination, books and series too (decision D19); a folder being
/// moved, and everything inside it, can't be picked. The tree closes once what was
/// picked is saved; a pick or a new folder that can't be saved leaves it up, with the toast over
/// it.
///
/// ```
/// Move to…                                    ✕
///  ＋ New Folder
///  Library (no folder)
///  📁 Fiction                                 ✓   ← long-press: New Folder Inside
///      📕 Pride and Prejudice
/// ```
struct MoveTreeSheet: View {
    let request: MoveRequest

    @Environment(ShellState.self) private var shell
    @Environment(LibraryStore.self) private var library

    var body: some View {
        NavigationStack {
            MoveTreeList(current: request.current, moving: request.moving) { folder in
                request.pick(folder, shell: shell)
            } pickNewFolder: { name, parent in
                request.pickNewFolder(named: name, in: parent, library: library, shell: shell)
            }
            .sheetToastLayer()
            .navigationTitle(request.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                SheetBarButton(Verbs.cancel, placement: .cancellationAction, identifier: "moveCancel") {
                    shell.sheet = nil
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("moveTree")
    }
}

/// The Move tree's list, for the sheet above and for the import sheet's *Add to*, which pushes it.
/// `pick` gets the folder tapped, or nil for the top level; `pickNewFolder` the name given to *New
/// Folder* (or *New Folder Inside*) and where it goes, for the caller to make the folder and pick
/// it (`MoveRequest.pickNewFolder`, `BookImportFlow.chooseNewFolder`).
struct MoveTreeList: View {
    /// Marked ✓.
    var current: MoveRequest.Place?
    /// Folders being moved: they and everything inside them can't be picked (no cycles).
    var moving: Set<UUID> = []
    let pick: (Folder?) -> Void
    let pickNewFolder: (_ name: String, _ parent: Folder?) -> Void

    @Query private var folders: [Folder]
    @State private var naming = false
    @State private var newName = ""
    /// Where the folder being named goes (nil: the top level).
    @State private var newParent: Folder?

    /// Every folder, depth first, with its depth (0 at the top level).
    private var tree: [(folder: Folder, depth: Int)] {
        func walk(_ level: [Folder], depth: Int) -> [(Folder, Int)] {
            LibraryStore.ordered(level).flatMap { folder in
                [(folder, depth)] + walk(folder.children ?? [], depth: depth + 1)
            }
        }
        return walk(LibraryQueries.topLevel(folders), depth: 0)
    }

    var body: some View {
        List {
            Section {
                Button { name(in: nil) } label: {
                    SymbolRow(String(localized: "New Folder"), symbol: Icons.newFolder, ink: Palette.accent)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("moveNewFolder")
                place(String(localized: "Library (no folder)"), symbol: Icons.library, depth: 0,
                      isCurrent: current == .topLevel, isEnabled: true, id: "moveTopLevel") { pick(nil) }
                ForEach(tree, id: \.folder.id) { entry in
                    let folder = entry.folder
                    place(folder.name, symbol: folder.rowSymbol, depth: entry.depth,
                          isCurrent: current == .folder(folder.id),
                          isEnabled: !isMoving(folder), id: "moveFolder") { pick(folder) }
                        .contextMenu {
                            Button("New Folder Inside", systemImage: Icons.newFolder) { name(in: folder) }
                                .accessibilityIdentifier("moveNewFolderInside")
                                .menuAvailability(MenuAvailability(when: !isMoving(folder)))
                        }
                }
            }
            .listCard()
        }
        .cardListStyle()
        .newFolderAlert(isPresented: $naming, name: $newName,
                        message: newParent.map { "It goes inside “\($0.name)”, and this goes into it." }
                            ?? "It goes at the top level, and this goes into it.") {
            pickNewFolder(newName, newParent)
        }
    }

    private func place(_ title: String, symbol: String, depth: Int, isCurrent: Bool, isEnabled: Bool, id: String,
                       action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SymbolRow(title) {
                Image(systemName: symbol).foregroundStyle(Palette.accent)
            } trailing: {
                if isCurrent {
                    Image(systemName: Icons.checkmark)
                        .foregroundStyle(Palette.accent)
                        .accessibilityHidden(true)
                }
            }
            .padding(.leading, Spacing.l * CGFloat(depth))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : Palette.disabledOpacity)
        .accessibilityLabel(title)
        .accessibilityValue(isCurrent ? "Current" : "")
        .accessibilityIdentifier(id)
    }

    /// The folder is one being moved, or inside one.
    private func isMoving(_ folder: Folder) -> Bool {
        moving.contains(folder.id) || folder.ancestors.contains { moving.contains($0.id) }
    }

    private func name(in parent: Folder?) {
        newParent = parent
        newName = ""
        naming = true
    }

    /// *New Folder* / *New Folder Inside*: a folder named `name` ("New Folder" when blank) in
    /// `parent`, or nil when it can't be saved, once the toast has said so.
    @MainActor
    @discardableResult
    static func makeFolder(named name: String, in parent: Folder?, library: LibraryStore, shell: ShellState) -> Folder? {
        shell.attempt(String(localized: "Couldn’t make the folder")) { try library.makeFolder(name: name, in: parent) }
    }
}

extension MoveRequest {
    /// A place picked in the tree: the tree closes once the pick is saved, unless the pick put
    /// up another sheet. One that can't be saved leaves it up, under its toast.
    @MainActor
    func pick(_ folder: Folder?, shell: ShellState) {
        guard onPick(folder), shell.sheet == .moveTo(self) else { return }
        shell.sheet = nil
    }

    /// *New Folder* / *New Folder Inside*: a folder named `name` ("New Folder" when blank) in
    /// `parent`, then picked. A folder that can't be saved files nothing and leaves the tree up;
    /// the toast says so.
    @MainActor
    func pickNewFolder(named name: String, in parent: Folder?, library: LibraryStore, shell: ShellState) {
        guard let folder = MoveTreeList.makeFolder(named: name, in: parent, library: library, shell: shell) else { return }
        pick(folder, shell: shell)
    }
}
