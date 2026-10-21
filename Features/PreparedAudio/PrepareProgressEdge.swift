import SwiftUI

/// The progress line on a surface's bottom chrome (the browser's, the Library's, the Reader's,
/// Now Playing's), a `ProgressLine` on the edge track:
/// shown while prepared audio run, gone when nothing is queued, everything queued is paused, or no
/// on-device voice renders prepared audio (decision D16). Laid over the top edge of the band
/// (`.overlay(alignment: .top)`); it always takes the band's width and the line's height, so a
/// toast laid beside it keeps its place. VoiceOver reads it as a button that opens Prepared audio.
struct PrepareProgressEdge: View {
    @Environment(PrepareCenter.self) private var preparedAudio
    @Environment(ShellState.self) private var shell

    var body: some View {
        let progress = preparedAudio.progress
        ZStack {
            if let progress {
                ProgressLine(fraction: progress, height: ProgressLine.edgeHeight, track: .edge)
                    .animation(Motion.standard, value: progress)
                    .transition(.opacity)
                    .accessibilityElement()
                    .accessibilityLabel(Verbs.preparedAudio)
                    .accessibilityValue("\(Int((progress * 100).rounded())) percent")
                    .accessibilityHint(String(localized: "Opens \(Verbs.preparedAudio)"))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { shell.present(.preparedAudio) }
                    .accessibilityIdentifier("downloadProgress")
            }
        }
        .frame(maxWidth: .infinity, minHeight: ProgressLine.edgeHeight, maxHeight: ProgressLine.edgeHeight)
        .animation(Motion.snappy, value: progress == nil)
    }
}

/// Asking for a prepare from a row's menu, a folder header or a ⋯ panel: the request, then a
/// toast only when nothing on screen shows it. One that starts (or resumes) has no toast: its row's
/// mark and the header's control already show it (C96).
@MainActor
struct PrepareActions {
    let preparedAudio: PrepareCenter
    let shell: ShellState

    func prepare(_ article: Article) {
        report(preparedAudio.prepare(article), title: article.lineOne)
    }

    func prepare(_ folder: Folder) {
        report(preparedAudio.prepare(folder), title: folder.name)
    }

    private func report(_ request: PrepareCenter.Request, title: String) {
        let message: String
        switch request {
        case .added, .resumed: return
        case .alreadyQueued: message = String(localized: "“\(title)” is already being prepared")
        case .waitingForNew:
            shell.showToast(ShellToast(message: String(localized: "New articles in “\(title)” will be prepared"), systemImage: Icons.prepare))
            return
        case .nothingToPrepare:
            shell.showToast(ShellToast(message: String(localized: "Nothing to prepare"), systemImage: Icons.prepare))
            return
        }
        shell.showToast(ShellToast(message: message, systemImage: Icons.prepare, actionTitle: String(localized: "View")) {
            [shell] in shell.present(.preparedAudio)
        })
    }
}
