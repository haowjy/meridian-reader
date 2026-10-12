import SwiftUI

/// A folder header's play buttons, for a book, a series or any folder whose pages play: the round
/// *Continue* / *Playing* button (`title`) and *Play from Start*, both through `LibraryActions`.
/// The book screen and the folder screen share it, so the two headers play the same way.
///
/// ```
/// ( ▶ Continue  Ch 24                ) ( Play from Start )
/// ```
struct FolderPlayButtons: View {
    let folder: Folder
    /// The round button's title and the lighter place after it ("Continue" "Ch 24").
    let title: (title: String, detail: String?)
    /// Accessibility identifiers: "<prefix>Continue", "<prefix>PlayFromStart".
    let identifierPrefix: String
    let actions: LibraryActions

    var body: some View {
        FolderHeaderButtons { expands in
            PlayStateButton(state: actions.playState(of: folder),
                            look: .pill(title: title.title, detail: title.detail, expands: expands)) {
                actions.playFolder(folder)
            }
            .accessibilityIdentifier("\(identifierPrefix)Continue")
        } secondary: { expands in
            PillButton(String(localized: "Play from Start"), style: .neutral, expands: expands) {
                actions.playFolderFromStart(folder)
            }
            .accessibilityIdentifier("\(identifierPrefix)PlayFromStart")
        }
    }
}
