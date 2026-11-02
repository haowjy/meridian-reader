import SwiftUI

/// Four ways to add something, shared by empty screens. Link, import and paste
/// open over the Library at their destination folder.
struct AddToLibraryTiles: View {
    /// Where an import, pasted text or a link goes; nil: the Library's top level.
    let folder: Folder?

    @Environment(ShellState.self) private var shell
    @Environment(LibraryStore.self) private var library
    @Environment(LibraryScreenState.self) private var screen
    @Environment(FollowCenter.self) private var follow

    var body: some View {
        ActionTileGrid(tiles: [
            ActionTile(title: String(localized: "Browse the Web"), symbol: Icons.browser, prominent: true,
                       identifier: "emptyBrowse") {
                shell.sheet = nil
                shell.showBrowser()
            },
            ActionTile(title: Verbs.title(Verbs.addLink), symbol: Icons.link, identifier: "emptyLink") {
                showLibrary()
                screen.addLink(into: folder, shell: shell, follow: follow)
            },
            ActionTile(title: String(localized: "Import a File"), symbol: Icons.importFile, identifier: "emptyImport") {
                showLibrary()
                BookImportActions(library: library, shell: shell).pickBook(into: folder)
            },
            ActionTile(title: String(localized: "Paste Text"), symbol: Icons.paste, identifier: "emptyPaste") {
                showLibrary()
                screen.pasteText(into: folder, shell: shell)
            },
        ])
    }

    /// The Library at the destination, nothing over it.
    private func showLibrary() {
        shell.sheet = nil
        shell.showLibrary(at: folder.map(library.path(to:)) ?? [])
    }
}
