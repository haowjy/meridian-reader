import SwiftData
import SwiftUI

/// The Move tree: one sheet for Move, *Save to Library…*, 🔖's *Save to Folder…* and *Change
/// Folder*. The whole tree as one indented list, like Safari's bookmark-folder picker; one tap
/// files, ✓ marks the current place. *New Folder* makes one at the top level; a folder's
/// long-press, *New Folder Inside*, makes one in it; either way what is being filed goes into the
/// new folder. Books and series aren't destinations (they take pages only from their source); a
/// folder being moved, and everything inside it, can't be picked.
///
/// ```
/// Move to…                                    ✕
///  ＋ New Folder
///  Library (no folder)
///  ★ Favorites
///      📁 Serial sites
///  📁 Fiction                                 ✓   ← long-press: New Folder Inside
///      📁 Short stories
/// Books and series can't hold other pages.
/// ```
struct MoveTreeSheet: View {
    let request: MoveRequest

    @Environment(LibraryStore.self) private var library
    @Environment(ShellState.self) private var shell
    @Query private var folders: [Folder]
    @State private var naming = false
    @State private var newName = ""
    /// Where the folder being named goes (nil: the top level).
    @State private var newParent: Folder?

    /// Each folder that can hold others, depth first, with its depth (0 at the top level).
    private var tree: [(folder: Folder, depth: Int)] {
        func walk(_ level: [Folder], depth: Int) -> [(Folder, Int)] {
            LibraryStore.ordered(level).filter { !$0.kind.isFixed }.flatMap { folder in
                [(folder, depth)] + walk(folder.children ?? [], depth: depth + 1)
            }
        }
        return walk(folders.filter { $0.parent == nil }, depth: 0)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { name(in: nil) } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                            .typeStyle(.row)
                            .foregroundStyle(Palette.accent)
                            .frame(maxWidth: .infinity, minHeight: BottomChrome.minTapTarget, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("moveNewFolder")
                    place(String(localized: "Library (no folder)"), symbol: "books.vertical", depth: 0,
                          isCurrent: request.current == .topLevel, isEnabled: true, id: "moveTopLevel") { pick(nil) }
                    ForEach(tree, id: \.folder.id) { entry in
                        let folder = entry.folder
                        place(folder.displayName, symbol: folder.rowSymbol, depth: entry.depth,
                              isCurrent: request.current == .folder(folder.id),
                              isEnabled: !isMoving(folder), id: "moveFolder") { pick(folder) }
                            .contextMenu {
                                if !isMoving(folder) {
                                    Button("New Folder Inside", systemImage: "folder.badge.plus") { name(in: folder) }
                                        .accessibilityIdentifier("moveNewFolderInside")
                                }
                            }
                    }
                } footer: {
                    Text("Books and series can't hold other pages.")
                        .typeStyle(.caption)
                        .foregroundStyle(Palette.secondaryInk)
                }
                .listRowBackground(Palette.chrome)
            }
            .libraryListStyle()
            .navigationTitle(request.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { shell.sheet = nil } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                        .accessibilityIdentifier("moveCancel")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("moveTree")
        .alert("New Folder", isPresented: $naming) {
            TextField("Name", text: $newName)
                .accessibilityIdentifier("newFolderField")
            Button("Cancel", role: .cancel) { newName = "" }
            Button("Create") { createAndPick() }
                .accessibilityIdentifier("newFolderCreate")
        } message: {
            Text(newParent.map { "It goes inside “\($0.displayName)”, and this goes into it." }
                 ?? "It goes at the top level, and this goes into it.")
        }
    }

    private func place(_ title: String, symbol: String, depth: Int, isCurrent: Bool, isEnabled: Bool, id: String,
                       action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.s) {
                Image(systemName: symbol)
                    .foregroundStyle(Palette.accent)
                    .frame(width: ListRow.leadingWidth)
                Text(title)
                    .typeStyle(.row)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isCurrent {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Palette.accent)
                        .accessibilityHidden(true)
                }
            }
            .padding(.leading, Spacing.l * CGFloat(depth))
            .frame(minHeight: BottomChrome.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityLabel(title)
        .accessibilityValue(isCurrent ? "Current" : "")
        .accessibilityIdentifier(id)
    }

    /// The folder is one being moved, or inside one.
    private func isMoving(_ folder: Folder) -> Bool {
        request.moving.contains(folder.id) || folder.ancestors.contains { request.moving.contains($0.id) }
    }

    private func pick(_ folder: Folder?) {
        shell.sheet = nil
        request.onPick(folder)
    }

    private func name(in parent: Folder?) {
        newParent = parent
        naming = true
    }

    /// A folder that can't be saved closes the tree, filing nothing, and the toast says so.
    private func createAndPick() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        newName = ""
        guard let folder = shell.attempt(String(localized: "Couldn’t make the folder"), {
            try library.makeFolder(name: name.isEmpty ? String(localized: "New Folder") : name, in: newParent)
        }) else {
            shell.sheet = nil
            return
        }
        pick(folder)
    }
}
