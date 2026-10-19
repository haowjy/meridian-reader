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
///  [📁]        [✓]        [🗑]
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
                actions.move(selected.folders.map(LibraryItem.folder) + selected.pages.map(LibraryItem.page)) {
                    screen.selection = []
                }
            }
            .disabled(nothing)
            .toolbarSlot(0)
            BandToolbarButton(systemImage: Icons.markFinished, label: Verbs.markFinished,
                              identifier: "editMarkFinished") {
                if actions.setFinished(actions.selected(in: screen).pages.filter(\.isSaved), true) { screen.selection = [] }
            }
            .disabled(actions.selected(in: screen).pages.allSatisfy { !$0.isSaved })
            .toolbarSlot(2)
            BandToolbarButton(systemImage: Icons.delete, label: Verbs.remove, identifier: "editRemove") {
                actions.removeSelection(of: screen)
            }
            .disabled(nothing)
            .toolbarSlot(BottomToolbarLayout.moreSlot)
        }
    }
}

extension LibraryStore {
    /// The Library's path to `folder`: the folders above it, then it.
    func path(to folder: Folder) -> [LibraryRoute] {
        (folder.ancestors.reversed() + [folder]).map { .folder($0.id) }
    }
}
