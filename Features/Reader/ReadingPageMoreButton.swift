import SwiftUI

/// ⋯ on the Reader sheet and on Now Playing: opens the page's menu (`ArticleActions.readingPageMenu`).
/// The compact chrome draws it (`chrome`) as its own ⋯, so the reading page has one; at regular
/// width, where there is no chrome host, the transport row holds it. `extraRows` are the page's
/// own, first among the screen's rows (*Play from a Paragraph*, which the compact page has no
/// top bar button for).
struct ReadingPageMoreButton: View {
    let id: String
    var chrome = false
    var extraRows: [MenuRow] = []

    @Environment(LibraryStore.self) private var library
    @Environment(ShellState.self) private var shell
    @Environment(\.speechController) private var speech
    @Environment(FollowCenter.self) private var follow
    @Environment(PrepareCenter.self) private var preparedAudio

    var body: some View {
        MoreMenuButton(id: id, chrome: chrome) {
            var menu = ArticleActions.readingPageMenu(shell: shell, library: library, speech: speech,
                                                      preparedAudio: preparedAudio, follow: follow, compact: chrome)
            menu.screen = extraRows + menu.screen
            return menu
        }
    }
}
