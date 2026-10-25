import SwiftUI

/// ⋯ on the Reader sheet and on Now Playing: opens the page's menu (`ArticleActions.readingPageMenu`).
/// The compact chrome draws it (`chrome`) as its own ⋯, so the reading page has one; at regular
/// width, where there is no chrome host, the transport row holds it.
struct ReadingPageMoreButton: View {
    let id: String
    var chrome = false

    @Environment(LibraryStore.self) private var library
    @Environment(ShellState.self) private var shell
    @Environment(\.speechController) private var speech
    @Environment(FollowCenter.self) private var follow
    @Environment(PrepareCenter.self) private var preparedAudio

    var body: some View {
        MoreMenuButton(id: id, chrome: chrome) {
            ArticleActions.readingPageMenu(shell: shell, library: library, speech: speech,
                                           preparedAudio: preparedAudio, follow: follow)
        }
    }
}
