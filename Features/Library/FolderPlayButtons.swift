import SwiftUI

/// A folder header's action row, for any folder whose pages play (a book or series too): the
/// round *Continue* / *Playing* button (`title`), *From Start*, both through `LibraryActions`,
/// and the folder's Download, drawn as a row's (the same ⬇ / ✓ as the rows under it). One
/// `ActionButtonRow`, so it never wraps (decision D21). *From Start* keeps its name at every
/// width: the place after Continue gives way first, then both show their symbols alone.
///
/// ```
/// ( ▶ Continue  4 of 18          ) ( ⏮ From Start )  ⬇
/// ```
struct FolderPlayButtons: View {
    let folder: Folder
    /// The round button's title and the lighter place after it ("Continue" "24 of 61").
    let title: (title: String, detail: String?)
    let actions: LibraryActions

    @Environment(DownloadCenter.self) private var downloads
    @Environment(ShellState.self) private var shell

    var body: some View {
        let pages = (folder.pages ?? []).filter(\.isLive)
        ActionButtonRow { fit in
            PlayStateButton(state: actions.playState(of: folder),
                            look: .pill(title: title.title, detail: title.detail, expands: true, fit: fit)) {
                actions.playFolder(folder)
            }
            .accessibilityIdentifier("folderContinue")
            PillButton(Verbs.fromStart, systemImage: Icons.previous, style: .neutral, fit: fit) {
                actions.playFolderFromStart(folder)
            }
            .accessibilityLabel(Verbs.playFromStart)
            .accessibilityIdentifier("folderPlayFromStart")
            if !pages.isEmpty {
                DownloadStateButton(state: downloads.state(of: .folder(folder.id),
                                                           isDownloaded: downloads.isDownloaded(folder, pages: pages))) {
                    DownloadActions(downloads: downloads, shell: shell).download(folder)
                }
                .accessibilityIdentifier("folderDownload")
            }
        }
    }
}
