import SwiftUI

/// A folder header's play buttons, for any folder whose pages play (a book or series too): the
/// round *Continue* / *Playing* button (`title`) and *Play from Start*, both through
/// `LibraryActions`.
///
/// ```
/// ( ▶ Continue  24 of 61             ) ( Play from Start )
/// ```
struct FolderPlayButtons: View {
    let folder: Folder
    /// The round button's title and the lighter place after it ("Continue" "24 of 61").
    let title: (title: String, detail: String?)
    let actions: LibraryActions

    var body: some View {
        FolderHeaderButtons { expands in
            PlayStateButton(state: actions.playState(of: folder),
                            look: .pill(title: title.title, detail: title.detail, expands: expands)) {
                actions.playFolder(folder)
            }
            .accessibilityIdentifier("folderContinue")
        } secondary: { expands in
            PillButton(String(localized: "Play from Start"), style: .neutral, expands: expands) {
                actions.playFolderFromStart(folder)
            }
            .accessibilityIdentifier("folderPlayFromStart")
        }
    }
}
