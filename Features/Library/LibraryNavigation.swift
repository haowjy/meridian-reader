import SwiftUI

/// The screen for a pushed `LibraryRoute`: a folder (a book or series as any other, decision D19).
struct LibraryRouteView: View {
    let route: LibraryRoute

    @Environment(LibraryStore.self) private var library

    var body: some View {
        screen.environment(\.libraryScreenKey, .route(route))
    }

    @ViewBuilder
    private var screen: some View {
        switch route {
        case .folder(let id):
            if let folder = library.folder(id: id) {
                FolderScreen(folder: folder)
            } else {
                FolderGoneView()
            }
        }
    }
}

/// A folder's screen once the folder is gone (deleted, or a remembered path to one that isn't
/// there any more).
struct FolderGoneView: View {
    var body: some View {
        EmptyState(String(localized: "This Folder Is Gone"), symbol: Icons.folder)
    }
}

/// The bottom toolbar while a folder screen is in Edit: the same 5-slot row of symbols as at
/// rest, so the chrome doesn't change shape. *Move to…* in slot 1, *Mark as Finished* in the
/// middle, *Remove* in ⋯'s place, acting on the selection (Remove asks before deleting folders;
/// `LibraryActions.removeSelection`). The selection clears once an action is saved and stays
/// when it can't be.
///
/// ```
///  [📁]        [✓]  [＋]  [🗑]
/// ```
struct LibraryEditBar: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.speechController) private var speech
    @Environment(ShellState.self) private var shell
    @Environment(FollowCenter.self) private var follow
    @Environment(LibraryScreenState.self) private var screen

    private var actions: LibraryActions { LibraryActions(library: library, speech: speech, shell: shell, follow: follow) }

    var body: some View {
        let nothing = screen.selection.isEmpty
        BottomToolbarLayout {
            BandToolbarButton(systemImage: Icons.move, label: Verbs.moveTo, identifier: "editMove") {
                let selected = actions.selected(in: screen)
                actions.move(selected.folders.map(LibraryItem.folder) + selected.articles.map(LibraryItem.article)) {
                    screen.selection = []
                }
            }
            .disabled(nothing)
            .toolbarSlot(0)
            BandToolbarButton(systemImage: Icons.markFinished, label: Verbs.markFinished,
                              identifier: "editMarkFinished") {
                if actions.setFinished(actions.selected(in: screen).articles.filter(\.isSaved), true) { screen.selection = [] }
            }
            .disabled(actions.selected(in: screen).articles.allSatisfy { !$0.isSaved })
            .toolbarSlot(2)
            if let folder = editedFolder, !createRows(in: folder).isEmpty {
                Menu { MenuRows(createRows(in: folder)) } label: {
                    Image(systemName: Icons.add).toolbarIconFrame()
                }
                .accessibilityLabel(Verbs.create)
                .accessibilityIdentifier("editCreate")
                .toolbarSlot(3)
            }
            BandToolbarButton(systemImage: Icons.delete, label: Verbs.remove, identifier: "editRemove") {
                actions.removeSelection(of: screen)
            }
            .disabled(nothing)
            .toolbarSlot(BottomToolbarLayout.moreSlot)
        }
    }
}

extension LibraryEditBar {
    /// The folder whose screen is in Edit.
    var editedFolder: Folder? { screen.editing.flatMap { library.folder(id: $0.folderID) } }

    /// Slot 3's ＋ (C122, C126): the create group at `.edit`, its New Folder filing the selection.
    func createRows(in folder: Folder) -> [MenuRow] {
        LibraryCreateMenu(library: library, shell: shell, screen: screen, folder: folder, place: .edit) {
            let selected = actions.selected(in: screen)
            return selected.folders.map(LibraryItem.folder) + selected.articles.map(LibraryItem.article)
        }.rows
    }
}

extension LibraryStore {
    /// The Library's path to `folder`: the folders above it, then it.
    func path(to folder: Folder) -> [LibraryRoute] {
        (folder.ancestors.reversed() + [folder]).map { .folder($0.id) }
    }
}
