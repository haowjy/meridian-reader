import SwiftUI

/// ⋯ on the Reader sheet and on Listen: opens the page's menu (`ArticleActions.readingPageMenu`), a
/// toolbar glyph cell. At regular width the transport row holds it; on compact width the player
/// card's tools row (`compact`, the compact menu's tiles). `extraRows` are the page's own, first
/// among the screen's rows (*Play from a Paragraph*, which compact Listen has no top bar button for).
struct ReadingPageMoreButton: View {
    let id: String
    var compact = false
    var extraRows: [MenuRow] = []

    @Environment(LibraryStore.self) private var library
    @Environment(ShellState.self) private var shell
    @Environment(\.speechController) private var speech
    @Environment(FollowCenter.self) private var follow
    @Environment(PrepareCenter.self) private var preparedAudio

    var body: some View {
        MoreMenuButton(id: id) {
            var menu = ArticleActions.readingPageMenu(shell: shell, library: library, speech: speech,
                                                      preparedAudio: preparedAudio, follow: follow, compact: compact)
            menu.screen = extraRows + menu.screen
            return menu
        }
    }
}
