import SwiftUI

/// A folder header's action row, for any folder whose pages play (a book or series too): the
/// round *Continue* / *Playing* button (`title`), *From Start*, both through `LibraryActions`,
/// and the folder's Download, icon only. One `ActionButtonRow`, so it never wraps (decision D21).
///
/// ```
/// ( ▶ Continue  4 of 18          ) ( ⏮ From Start ) (⬇)
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
            PillButton(String(localized: "From Start"), shortTitle: String(localized: "Start"),
                       systemImage: Icons.previous, style: .neutral, fit: fit) {
                actions.playFolderFromStart(folder)
            }
            .accessibilityLabel(String(localized: "Play from Start"))
            .accessibilityIdentifier("folderPlayFromStart")
            if !pages.isEmpty {
                DownloadStateButton(state: downloads.state(of: .folder(folder.id),
                                                           isDownloaded: downloads.isDownloaded(folder, pages: pages)),
                                    look: .round) {
                    DownloadActions(downloads: downloads, shell: shell).download(folder)
                }
                .accessibilityIdentifier("folderDownload")
            }
        }
    }
}
