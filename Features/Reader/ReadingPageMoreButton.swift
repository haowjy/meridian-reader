import SwiftUI

/// ⋯ on the Reader sheet and on regular width's Listen: the page's menu as a system menu
/// (`ArticleActions.readingPageMenu`), a toolbar glyph cell in the transport row.
struct ReadingPageMoreButton: View {
    let id: String

    @Environment(LibraryStore.self) private var library
    @Environment(ShellState.self) private var shell
    @Environment(\.speechController) private var speech
    @Environment(FollowCenter.self) private var follow
    @Environment(PrepareCenter.self) private var preparedAudio

    private func blocks() -> [[MenuRow]] {
        ArticleActions.readingPageMenu(shell: shell, library: library, speech: speech,
                                       preparedAudio: preparedAudio, follow: follow).blocks
    }

    var body: some View {
        TitleMenuButton(id: id, blocks: blocks()) {
            Image(systemName: Icons.more).toolbarIconFrame()
        }
        #if DEBUG
        .onAppear { MenuProbeState.shared.offerPageMenu(blocks) }
        #endif
    }
}
