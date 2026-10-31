import SwiftUI

/// The four ways to add something to listen to, the tiles of every empty screen (`EmptyState`):
/// *Browse the Web* (accent-tinted), *Import a File*, *Paste Text* and *Add a Link*. Each first
/// closes whatever is over the screen (a shell sheet, Listen) and lands where its result shows: the
/// Browser, or the Library at `folder` (nil: its home, on the Library tab) with the Files picker,
/// the paste editor or the address field up over it. The Library's own ＋ menu offers the same three
/// (`LibraryCreateMenu`).
struct AddToLibraryTiles: View {
    /// Where an import, pasted text or a link goes; nil: the Library's top level.
    let folder: Folder?

    @Environment(ShellState.self) private var shell
    @Environment(LibraryStore.self) private var library
    @Environment(LibraryScreenState.self) private var screen

    var body: some View {
        ActionTile(title: String(localized: "Browse the Web"), symbol: Icons.browser, prominent: true,
                   identifier: "emptyBrowse") {
            shell.sheet = nil
            shell.showBrowser()
        }
        ActionTile(title: String(localized: "Import a File"), symbol: Icons.importFile, identifier: "emptyImport") {
            showLibrary()
            BookImportActions(library: library, shell: shell).pickBook(into: folder)
        }
        ActionTile(title: String(localized: "Paste Text"), symbol: Icons.paste, identifier: "emptyPaste") {
            showLibrary()
            screen.pasteText(into: folder)
        }
        ActionTile(title: String(localized: "Add a Link"), symbol: Icons.link, identifier: "emptyLink") {
            showLibrary()
            screen.addLink(into: folder)
        }
    }

    /// The Library at the destination, nothing over it.
    private func showLibrary() {
        shell.sheet = nil
        shell.showLibrary(at: folder.map(library.path(to:)) ?? [])
    }
}
