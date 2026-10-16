import SwiftUI

/// The screen for a pushed `LibraryRoute`: a folder (a book or series as any other, decision D19),
/// or the pages in no folder.
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
        case .pages:
            FolderScreen(folder: nil)
        }
    }
}

/// A folder's screen once the folder is gone (deleted, or a remembered path to one that isn't
/// there any more).
struct FolderGoneView: View {
    var body: some View {
        ContentUnavailableView("This folder is gone", systemImage: Icons.folder)
    }
}

/// The bottom bar while a folder screen is in Edit: *Move…*, *Mark Finished*, *Remove*, acting on
/// the selection (Remove asks before deleting folders; `LibraryActions.removeSelection`). The
/// selection clears once an action is saved and stays when it can't be.
struct LibraryEditBar: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.speechController) private var speech
    @Environment(ShellState.self) private var shell
    @Environment(LibraryScreenState.self) private var screen

    private var actions: LibraryActions { LibraryActions(library: library, speech: speech, shell: shell) }

    var body: some View {
        let nothing = screen.selection.isEmpty
        BottomToolbarSpanLayout {
            Button("Move…") {
                let selected = actions.selected(in: screen)
                actions.move(selected.folders.map(LibraryItem.folder) + selected.pages.map(LibraryItem.page)) {
                    screen.selection = []
                }
            }
            .toolbarTextFrame()
            .disabled(nothing)
            .accessibilityIdentifier("editMove")
            Button("Mark Finished") {
                if actions.setFinished(actions.selected(in: screen).pages.filter(\.isSaved), true) { screen.selection = [] }
            }
            .toolbarTextFrame()
            .disabled(actions.selected(in: screen).pages.allSatisfy { !$0.isSaved })
            .accessibilityIdentifier("editMarkFinished")
            Button("Remove") { actions.removeSelection(of: screen) }
            .toolbarTextFrame()
            .disabled(nothing)
            .accessibilityIdentifier("editRemove")
        }
        .tint(Palette.ink)
    }
}

extension LibraryStore {
    /// The Library's path to `folder`: the folders above it, then it.
    func path(to folder: Folder) -> [LibraryRoute] {
        (folder.ancestors.reversed() + [folder]).map { .folder($0.id) }
    }
}
