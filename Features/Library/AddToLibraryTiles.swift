import SwiftUI

/// The five ways to add something to listen to, the tiles of every empty screen (`EmptyState`):
/// *Browse the Web* (accent-tinted) and *Follow a Site*, *Import a File* and *Paste Text*, two by
/// two, then *Add a Link* across the full width. Each first closes whatever is over the screen (a
/// shell sheet, Listen) and lands where its result shows: the Browser, the Follow sheet asking for
/// a story's address (always into the Library's top level), or the Library at `folder` (nil: its
/// home, on the Library tab) with the Files picker, the paste editor or the address field up over
/// it. The Library's own ＋ menu offers the import, paste and link (`LibraryCreateMenu`).
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
            ActionTile(title: Verbs.followSite, symbol: Icons.follow, identifier: "emptyFollow") {
                // In place of any sheet up, with Listen down: the screen under it is where the story's folder shows.
                shell.hideNowPlaying()
                shell.present(.follow(FollowFlow(url: nil, parentID: nil, center: follow)))
            },
            ActionTile(title: String(localized: "Import a File"), symbol: Icons.importFile, identifier: "emptyImport") {
                showLibrary()
                BookImportActions(library: library, shell: shell).pickBook(into: folder)
            },
            ActionTile(title: String(localized: "Paste Text"), symbol: Icons.paste, identifier: "emptyPaste") {
                showLibrary()
                screen.pasteText(into: folder)
            },
        ], wide: ActionTile(title: String(localized: "Add a Link"), symbol: Icons.link, identifier: "emptyLink") {
            showLibrary()
            screen.addLink(into: folder)
        })
    }

    /// The Library at the destination, nothing over it.
    private func showLibrary() {
        shell.sheet = nil
        shell.showLibrary(at: folder.map(library.path(to:)) ?? [])
    }
}
