import SwiftUI

/// ⋯ on the Reader sheet and on regular width's Listen: opens the page's ⋯ panel
/// (`ArticleActions.readingPageMenu`), a toolbar glyph cell in the transport row.
struct ReadingPageMoreButton: View {
    let id: String

    @Environment(LibraryStore.self) private var library
    @Environment(ShellState.self) private var shell
    @Environment(\.speechController) private var speech
    @Environment(FollowCenter.self) private var follow
    @Environment(PrepareCenter.self) private var preparedAudio

    var body: some View {
        MoreMenuButton(id: id) {
            ArticleActions.readingPageMenu(shell: shell, library: library, speech: speech,
                                           preparedAudio: preparedAudio, follow: follow)
        }
    }
}
