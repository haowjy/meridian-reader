import SwiftUI

/// A folder header's action row, for any folder whose pages play (a book or story too): the
/// round *Continue* / *Playing* button (`title`) and *From Start*, both through `LibraryActions`.
/// One `ActionButtonRow`, so it never wraps (decision D21). *From Start* keeps its name at every
/// width: the place after Continue gives way first, then both show their symbols alone. The
/// folder's Download is the switch under it (`FolderDownloadSwitch`).
///
/// ```
/// ( ▶ Continue  4 of 18                  ) ( ⏮ From Start )
/// ```
struct FolderPlayButtons: View {
    let folder: Folder
    /// The round button's title and the lighter place after it ("Continue" "24 of 61").
    let title: (title: String, detail: String?)
    let actions: LibraryActions

    var body: some View {
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
        }
    }
}

/// A folder's Download, Spotify-style: a switch under its play buttons. On, every page in it
/// downloads, and so does every page added later (Follow's new chapters, a page filed in); off,
/// nothing new downloads and what is downloaded stays (`DownloadCenter.turnOff`). A page whose
/// downloads were deleted stays out until the switch is turned on again (decision P8).
///
/// ```
/// ╭──────────────────────────────────────────╮
/// │ ⬇ Download                          ( ●) │
/// │   On · 12 of 107 downloaded              │
/// ╰──────────────────────────────────────────╯
/// ```
struct FolderDownloadSwitch: View {
    let folder: Folder

    @Environment(DownloadCenter.self) private var downloads
    @Environment(ShellState.self) private var shell

    var body: some View {
        let isOn = downloads.isOn(folder)
        SwitchCard(title: Verbs.download, symbol: Icons.download, detail: detail(isOn: isOn),
                   isOn: Binding(get: { isOn }, set: { on in
                       if on { DownloadActions(downloads: downloads, shell: shell).download(folder) } else { downloads.turnOff(folder) }
                   }), identifier: "folderDownload")
    }

    private func detail(isOn: Bool) -> String {
        guard isOn, let record = downloads.record(for: .folder(folder.id)) else {
            return String(localized: "Off · downloads when played or tapped")
        }
        if record.hasQueuedPages {
            return String(localized: "On · \(record.finishedCount) of \(record.entries.count) downloaded")
        }
        return folder.kind.isBookOrSeries ? String(localized: "On · new chapters download too")
            : String(localized: "On · pages added later download too")
    }
}
