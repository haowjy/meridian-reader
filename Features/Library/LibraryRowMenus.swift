import SwiftUI

/// A page row's menu: one builder for its ⋯ and its long press, so both have the same rows in the
/// same order. Each row goes through `MenuAvailability` (DR-09): hidden only when it can never
/// apply to this page (*Play from Here*, *Mark All Above* and the play-order row out of a folder,
/// *Share* without a web address, *Select* where the screen has no Edit), dimmed when it applies
/// but can't run now (a page not in the Library can't be moved, marked or downloaded until it is
/// saved; *Remove from Recent* out of the Library while the page isn't in Recent, a starred page
/// removed earlier). *Save to Library* / *Remove from Library* is one row, and *Remove from Recent*
/// never shows on a page in the Library. *Download* / *Remove Download* is one row showing the face for where the page's download
/// stands (`DownloadCenter.state(of:)`); *Remove Download* takes the page out of every download
/// and keeps it out (P8).
struct PageMenu: View {
    let page: Page
    let actions: LibraryActions
    let downloads: DownloadCenter
    /// *Select*: enters Edit with this row selected (folder screens only).
    var onSelect: (() -> Void)?

    var body: some View {
        let inLibrary = page.isInLibrary
        let inFolder = page.folder != nil
        let isSaved = page.isSavedToLibrary
        Button(Verbs.read, systemImage: Icons.reader) { actions.open(page) }
        Button("Play from Here", systemImage: Icons.play) { actions.playFromStart(page) }
            .menuAvailability(MenuAvailability(applies: inFolder, when: isSaved || page.isWaitingChapter))
        let hasDownload = downloads.state(of: page) != .notDownloaded
        Button(hasDownload ? Verbs.removeDownload : Verbs.download,
               systemImage: hasDownload ? Icons.removeDownload : Icons.download) {
            if hasDownload {
                downloads.deleteDownloads(of: page)
            } else {
                DownloadActions(downloads: downloads, shell: actions.shell).download(page)
            }
        }
        .menuAvailability(MenuAvailability(when: inLibrary))
        let isFavorite = page.isFavorite
        Button(isFavorite ? Verbs.removeFromFavorites : Verbs.addToFavorites,
               systemImage: isFavorite ? Icons.unfavorite : Icons.favorite) {
            FavoriteFlow(library: actions.library, shell: actions.shell).toggle(page)
        }
        .menuAvailability(MenuAvailability(when: LibraryStore.canFavorite(page)))
        Button(Verbs.moveTo, systemImage: Icons.move) { actions.move([.page(page)]) }
            .menuAvailability(MenuAvailability(when: inLibrary))
        Button(page.finishedAt == nil ? Verbs.markFinished : Verbs.markUnfinished,
               systemImage: page.finishedAt == nil ? Icons.markFinished : Icons.markUnfinished) {
            actions.setFinished([page], page.finishedAt == nil)
        }
        .menuAvailability(MenuAvailability(when: isSaved))
        Button("Mark All Above as Finished", systemImage: Icons.markAllAboveFinished) { actions.markAllAbove(page) }
            .menuAvailability(MenuAvailability(applies: inFolder, when: isSaved))
        Button(page.skipsInPlayback ? "Play in Playback" : "Skip in Playback",
               systemImage: page.skipsInPlayback ? Icons.includeInPlayback : Icons.skipInPlayback) {
            actions.toggleSkipsInPlayback(page)
        }
        // A waiting chapter too: one whose text can't be had is skipped so playback goes past it.
        .menuAvailability(MenuAvailability(applies: inFolder, when: isSaved || page.isWaitingChapter))
        Button("Share", systemImage: Icons.share) { actions.share(page) }
            .menuAvailability(MenuAvailability(applies: page.url?.isWeb == true))
        Button("Select", systemImage: Icons.select) { onSelect?() }
            .menuAvailability(MenuAvailability(applies: onSelect != nil))
        Button(inLibrary ? Verbs.removeFromLibrary : Verbs.saveToLibrary, systemImage: inLibrary ? Icons.unsave : Icons.save,
               role: inLibrary ? .destructive : nil) {
            if inLibrary { actions.remove([page]) } else { actions.save(page) }
        }
        // The same remove as the Library's (`LibraryStore.remove`): in no list after, the star kept.
        Button(Verbs.removeFromRecent, systemImage: Icons.removeFromRecent, role: .destructive) { actions.remove([page]) }
            .menuAvailability(MenuAvailability(applies: !inLibrary, when: LibraryQueries.isInRecent(page)))
    }
}

/// A folder's menu: one builder for its row's ⋯, its row's long press and its header's *More*
/// (`MenuAvailability`, DR-09). *Select* only where the screen has Edit (not in the header);
/// *Continue* and *Play from Start* dimmed while none of its pages play. *Download* / *Turn Off
/// Download* is one row, its face the folder's Download toggle (`DownloadCenter.isOn`), whatever
/// its header's control shows: *Download* turns it on (`DownloadCenter.download`), dimmed while
/// the folder has no pages; *Turn Off Download* asks, as the header's control does, then turns it
/// off and keeps what is downloaded.
struct FolderMenu: View {
    let folder: Folder
    let progress: FolderProgress
    let hasPages: Bool
    let actions: LibraryActions
    let downloads: DownloadCenter
    let screen: LibraryScreenState
    /// *Select*: enters Edit with this row selected (folder screens only).
    var onSelect: (() -> Void)?

    var body: some View {
        Button("Select", systemImage: Icons.select) { onSelect?() }
            .menuAvailability(MenuAvailability(applies: onSelect != nil))
        Button("Continue", systemImage: Icons.play) { actions.playFolder(folder) }
            .menuAvailability(MenuAvailability(when: progress.hasPagesToPlay))
        Button(Verbs.playFromStart, systemImage: Icons.previous) { actions.playFolderFromStart(folder) }
            .menuAvailability(MenuAvailability(when: progress.hasPagesToPlay))
        let isOn = downloads.isOn(folder)
        Button(isOn ? Verbs.turnOffDownload : Verbs.download, systemImage: isOn ? Icons.turnOffDownload : Icons.download) {
            if isOn {
                screen.confirmTurnOffDownload(folder)
            } else {
                DownloadActions(downloads: downloads, shell: actions.shell).download(folder)
            }
        }
        .menuAvailability(MenuAvailability(when: isOn || hasPages))
        Button(folder.isFavorite ? Verbs.removeFromFavorites : Verbs.addToFavorites,
               systemImage: folder.isFavorite ? Icons.unfavorite : Icons.favorite) {
            FavoriteFlow(library: actions.library, shell: actions.shell).toggle(folder)
        }
        Button(Verbs.moveTo, systemImage: Icons.move) { actions.move([.folder(folder)]) }
        Button("Rename", systemImage: Icons.rename) { screen.rename(folder) }
        Button("Edit Details", systemImage: Icons.editDetails) { actions.shell.present(.folderDetails(folder.id)) }
        Button("Delete…", systemImage: Icons.delete, role: .destructive) { screen.confirmDelete([folder]) }
    }
}
