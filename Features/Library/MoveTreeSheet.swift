import SwiftData
import SwiftUI

/// The Move tree: one sheet for Move, *Save to Library…*, 🔖's *Save to Folder…* and *Change
/// Folder* (the import sheet's *Add to* pushes the same list, `MoveTreeList`). The whole tree as one indented list, like Safari's bookmark-folder picker; one tap
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

    @Environment(ShellState.self) private var shell

    var body: some View {
        NavigationStack {
            MoveTreeList(current: request.current, moving: request.moving) { folder in
                shell.sheet = nil
                request.onPick(folder)
            }
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
    }
}

/// The Move tree's list, for the sheet above and for the import sheet's *Add to*, which pushes it.
/// `pick` gets the folder tapped, or nil for the top level.
struct MoveTreeList: View {
    /// Marked ✓.
    var current: MoveRequest.Place?
    /// Folders being moved: they and everything inside them can't be picked (no cycles).
    var moving: Set<UUID> = []
    let pick: (Folder?) -> Void

    @Environment(LibraryStore.self) private var library
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
                      isCurrent: current == .topLevel, isEnabled: true, id: "moveTopLevel") { pick(nil) }
                ForEach(tree, id: \.folder.id) { entry in
                    let folder = entry.folder
                    place(folder.displayName, symbol: folder.rowSymbol, depth: entry.depth,
                          isCurrent: current == .folder(folder.id),
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
        moving.contains(folder.id) || folder.ancestors.contains { moving.contains($0.id) }
    }

    private func name(in parent: Folder?) {
        newParent = parent
        naming = true
    }

    private func createAndPick() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        newName = ""
        guard let folder = try? library.makeFolder(name: name.isEmpty ? String(localized: "New Folder") : name,
                                                   in: newParent) else { return }
        pick(folder)
    }
}
